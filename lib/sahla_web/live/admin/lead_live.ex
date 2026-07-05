defmodule SahlaWeb.Admin.LeadLive do
  @moduledoc """
  Admin lead detail page under `/admin/leads/:id`.

  Renders a mobile-first lead workspace: snapshot, contact/actions, and timeline.
  Supports live PubSub refresh, status transitions, call logging, notes, and
  callback scheduling while keeping decrypted PII out of logs and process state
  except for the current render.
  """
  use SahlaWeb, :live_view

  on_mount {SahlaWeb.AdminAuthz, :leads}

  alias Sahla.Leads
  alias Sahla.Leads.Lead
  alias Sahla.Quoting.Quote
  alias Sahla.Repo
  alias Sahla.Settings
  alias Sahla.Vehicles

  @call_outcomes [
    {"ne_repond_pas", gettext("No answer")},
    {"rdv_pris", gettext("Appointment booked")},
    {"pas_interesse", gettext("Not interested")},
    {"a_revenir", gettext("Callback later")},
    {"injoignable", gettext("Unreachable")},
    {"faux_numero", gettext("Wrong number")}
  ]

  @status_labels %{
    nouveau: gettext("New"),
    contacte: gettext("Contacted"),
    rdv_planifie: gettext("Appointment scheduled"),
    devis_envoye: gettext("Quote sent"),
    relance: gettext("Follow-up"),
    gagne: gettext("Won"),
    perdu: gettext("Lost")
  }

  @status_variants %{
    nouveau: "info",
    contacte: "info",
    rdv_planifie: "warning",
    devis_envoye: "warning",
    relance: "warning",
    gagne: "success",
    perdu: "error"
  }

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    lead = Leads.get_lead!(id) |> Repo.preload(:quote)
    quote_record = lead.quote
    activities = Leads.list_activities(lead)

    if connected?(socket) do
      Leads.subscribe()

      if lead.assigned_admin_id do
        Leads.subscribe_agent(lead.assigned_admin_id)
      end
    end

    socket =
      socket
      |> assign(:page_title, gettext("Lead #%{id}", id: String.slice(id, 0, 8)))
      |> assign(:lead, lead)
      |> assign(:quote, quote_record)
      |> assign(:activities, activities)
      |> assign(:call_outcomes, @call_outcomes)
      |> assign(:status_labels, @status_labels)
      |> assign(:status_variants, @status_variants)
      |> assign(:pending_status, nil)
      |> assign(:errors, [])

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("add_note", %{"note" => %{"body" => body}}, socket) do
    lead = socket.assigns.lead

    case Leads.log_activity(lead, %{
           kind: :note,
           body: body,
           admin_id: socket.assigns.current_admin && socket.assigns.current_admin.id
         }) do
      {:ok, _activity} ->
        {:noreply,
         socket
         |> refresh_activities()
         |> put_flash(:info, gettext("Note added"))}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Could not save note"))}
    end
  end

  def handle_event("log_call", %{"outcome" => outcome}, socket) do
    lead = socket.assigns.lead

    case Leads.log_activity(lead, %{
           kind: :appel,
           body: call_outcome_label(outcome),
           metadata: %{"outcome" => outcome}
         }) do
      {:ok, _activity} ->
        {:noreply,
         socket
         |> refresh_activities()
         |> put_flash(:info, gettext("Call logged"))}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Could not log call"))}
    end
  end

  def handle_event("transition_status", %{"status" => status} = params, socket) do
    lead = socket.assigns.lead
    new_status = String.to_existing_atom(status)

    opts = [admin_id: socket.assigns.current_admin && socket.assigns.current_admin.id]

    opts =
      if new_status == :perdu do
        loss_reason = Map.get(params, "loss_reason") || ""
        Keyword.put(opts, :loss_reason, loss_reason)
      else
        opts
      end

    case Leads.transition_status(lead, new_status, opts) do
      {:ok, lead} ->
        {:noreply,
         socket
         |> assign(:lead, lead)
         |> assign(:pending_status, nil)
         |> refresh_activities()
         |> put_flash(:info, gettext("Status updated"))}

      {:error, :terminal} ->
        {:noreply,
         socket
         |> assign(:pending_status, nil)
         |> put_flash(:error, gettext("This lead is already closed"))}

      {:error, {:illegal_transition, _from, _to}} ->
        {:noreply,
         socket
         |> assign(:pending_status, nil)
         |> put_flash(:error, gettext("Invalid status transition"))}

      {:error, _changeset} ->
        message =
          if new_status == :perdu,
            do: gettext("Loss reason is required to mark as lost"),
            else: gettext("Status update failed")

        {:noreply,
         socket
         |> assign(:pending_status, String.to_existing_atom(status))
         |> put_flash(:error, message)}
    end
  end

  def handle_event(
        "confirm_loss_reason",
        %{"loss_reason" => %{"status" => status, "loss_reason" => reason}},
        socket
      ) do
    handle_event("transition_status", %{"status" => status, "loss_reason" => reason}, socket)
  end

  def handle_event("cancel_loss_reason", _params, socket) do
    {:noreply, assign(socket, :pending_status, nil)}
  end

  def handle_event(
        "schedule_callback",
        %{"callback_at" => %{"callback_at" => callback_at}},
        socket
      ) do
    lead = socket.assigns.lead

    case parse_callback_at(callback_at) do
      {:ok, dt} ->
        changeset = Lead.assignment_changeset(lead, %{callback_at: dt})

        case Repo.update(changeset) do
          {:ok, lead} ->
            {:ok, _activity} =
              Leads.log_activity(lead, %{
                kind: :rdv,
                body: gettext("Callback scheduled for %{at}", at: format_datetime(dt)),
                admin_id: socket.assigns.current_admin && socket.assigns.current_admin.id
              })

            {:noreply,
             socket
             |> assign(:lead, lead)
             |> refresh_activities()
             |> push_event("plausible-event", %{name: "callback_booked", props: %{}})
             |> put_flash(:info, gettext("Callback scheduled"))}

          {:error, _changeset} ->
            {:noreply,
             socket
             |> put_flash(:error, gettext("Could not schedule callback"))}
        end

      :error ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Invalid callback datetime"))}
    end
  end

  @impl true
  def handle_info({:lead, :updated, id}, socket) do
    if id == socket.assigns.lead.id do
      lead = Leads.get_lead!(id) |> Repo.preload(:quote)
      activities = Leads.list_activities(lead)

      {:noreply,
       socket
       |> assign(:lead, lead)
       |> assign(:activities, activities)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:lead, :created, _id}, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-7xl space-y-6 p-4 lg:p-8">
      <.header>
        {gettext("Lead #%{id}", id: String.slice(@lead.id, 0, 8))}
        <:subtitle>
          <.badge variant={Map.fetch!(@status_variants, @lead.status)}>
            {Map.fetch!(@status_labels, @lead.status)}
          </.badge>
          <span :if={@lead.callback_at} class="ml-2 text-sm text-ink/70">
            {gettext("Callback:")} {format_datetime(@lead.callback_at)}
          </span>
        </:subtitle>
      </.header>

      <div class="grid grid-cols-1 gap-6 lg:grid-cols-2">
        <.card>
          <h2 class="mb-4 text-lg font-semibold text-ink">{gettext("Snapshot")}</h2>
          <.snapshot lead={@lead} quote={@quote} />
        </.card>

        <.card>
          <h2 class="mb-4 text-lg font-semibold text-ink">{gettext("Contact & actions")}</h2>
          <.contact_actions lead={@lead} quote={@quote} />
          <.status_transition
            lead={@lead}
            pending_status={@pending_status}
            status_labels={@status_labels}
            status_variants={@status_variants}
          />
          <.callback_form lead={@lead} />
          <.call_log_form lead={@lead} call_outcomes={@call_outcomes} />
          <.note_form />
        </.card>
      </div>

      <.card>
        <h2 class="mb-4 text-lg font-semibold text-ink">{gettext("Timeline")}</h2>
        <.timeline activities={@activities} />
      </.card>
    </div>
    """
  end

  attr :lead, Lead, required: true
  attr :quote, Quote, required: true

  defp snapshot(assigns) do
    assigns =
      assigns
      |> assign(:vehicle_labels, vehicle_labels(assigns.quote))
      |> assign(:vehicle_value, Sahla.Money.to_mad(assigns.quote.vehicle_value_centimes || 0))

    ~H"""
    <div class="space-y-6">
      <section>
        <h3 class="mb-2 text-sm font-semibold uppercase tracking-wide text-ink/60">
          {gettext("Vehicle")}
        </h3>
        <.list>
          <:item title={gettext("Make / model / version")}>
            {@vehicle_labels.make} {@vehicle_labels.model} {@vehicle_labels.version}
          </:item>
          <:item title={gettext("Plate")}>{@quote.plate}</:item>
          <:item title={gettext("Fuel")}>{to_string(@quote.fuel)}</:item>
          <:item title={gettext("First registration")}>
            {@quote.first_registration && Calendar.strftime(@quote.first_registration, "%x")}
          </:item>
          <:item title={gettext("Declared value")}>
            <.price cents={@quote.vehicle_value_centimes || 0} />
          </:item>
        </.list>
      </section>

      <section>
        <h3 class="mb-2 text-sm font-semibold uppercase tracking-wide text-ink/60">
          {gettext("Driver")}
        </h3>
        <.list>
          <:item title={gettext("Name")}>{@quote.first_name} {@quote.last_name}</:item>
          <:item title={gettext("Birth date")}>
            {@quote.birth_date && Calendar.strftime(@quote.birth_date, "%x")}
          </:item>
          <:item title={gettext("License date")}>
            {@quote.license_date && Calendar.strftime(@quote.license_date, "%x")}
          </:item>
        </.list>
      </section>

      <section>
        <h3 class="mb-2 text-sm font-semibold uppercase tracking-wide text-ink/60">
          {gettext("Coverage")}
        </h3>
        <.list>
          <:item title={gettext("Formula")}>{to_string(@quote.formula)}</:item>
          <:item title={gettext("Options")}>{Enum.join(@quote.options || [], ", ")}</:item>
          <:item title={gettext("Franchise preference")}>
            {to_string(@quote.franchise_pref)}
          </:item>
          <:item title={gettext("Effect date")}>
            {@quote.effect_date && Calendar.strftime(@quote.effect_date, "%x")}
          </:item>
        </.list>
      </section>

      <section>
        <h3 class="mb-2 text-sm font-semibold uppercase tracking-wide text-ink/60">
          {gettext("Offer summary")}
        </h3>
        <p class="text-ink/70">
          {gettext("Offer ID:")}
          <code class="rounded bg-bg px-1 py-0.5 text-xs">{@lead.offer_id || gettext("none")}</code>
        </p>
      </section>
    </div>
    """
  end

  attr :lead, Lead, required: true
  attr :quote, Quote, required: true

  defp contact_actions(assigns) do
    phone = decrypted_phone(assigns.quote)
    whatsapp_number = Settings.get("contact.whatsapp", "")

    assigns =
      assigns
      |> assign(:phone, phone)
      |> assign(:whatsapp_number, whatsapp_number)
      |> assign(
        :wa_link,
        whatsapp_link(assigns.quote.token, assigns.lead.offer_id, whatsapp_number)
      )
      |> assign(:tel_link, if(phone, do: "tel:#{phone}", else: nil))

    ~H"""
    <div class="space-y-4">
      <div class="flex flex-wrap gap-3">
        <.link
          :if={@tel_link}
          href={@tel_link}
          class="btn btn-primary inline-flex items-center gap-2"
        >
          <.icon name="hero-phone" class="size-4" />
          {gettext("Call")}
        </.link>

        <.link
          :if={@wa_link}
          href={@wa_link}
          target="_blank"
          rel="noopener noreferrer"
          class="btn btn-secondary inline-flex items-center gap-2"
        >
          <.icon name="hero-chat-bubble-left-ellipsis" class="size-4" />
          {gettext("WhatsApp")}
        </.link>
      </div>

      <dl class="space-y-1 text-sm">
        <div class="flex gap-2">
          <dt class="text-ink/60">{gettext("Email")}:</dt>
          <dd>{@quote.email || gettext("—")}</dd>
        </div>
        <div class="flex gap-2">
          <dt class="text-ink/60">{gettext("Phone")}:</dt>
          <dd :if={@phone}>{@phone}</dd>
          <dd :if={!@phone} class="text-ink/50">{gettext("not provided")}</dd>
        </div>
        <div class="flex gap-2">
          <dt class="text-ink/60">{gettext("Token")}:</dt>
          <dd><code class="text-xs">{@quote.token}</code></dd>
        </div>
      </dl>
    </div>
    """
  end

  attr :lead, Lead, required: true
  attr :pending_status, :any, default: nil
  attr :status_labels, :map, required: true
  attr :status_variants, :map, required: true

  defp status_transition(assigns) do
    transitions = Lead.statuses() |> Enum.map(&{&1, allowed_next_statuses(&1)})
    allowed = Map.new(transitions)

    assigns =
      assigns
      |> assign(:allowed, allowed)
      |> assign(:next_statuses, allowed[assigns.lead.status] || [])

    ~H"""
    <div class="mt-6">
      <h3 class="mb-2 text-sm font-semibold uppercase tracking-wide text-ink/60">
        {gettext("Move status")}
      </h3>

      <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
        <.option_card
          :for={status <- @next_statuses}
          name="status"
          value={to_string(status)}
          label={Map.fetch!(@status_labels, status)}
          selected={false}
          phx-click="transition_status"
          phx-value-status={to_string(status)}
        />
      </div>

      <.form
        :if={@pending_status == :perdu}
        for={%{}}
        phx-submit="confirm_loss_reason"
        class="mt-4 rounded-card border border-error/30 bg-error/5 p-4"
      >
        <input type="hidden" name="loss_reason[status]" value="perdu" />
        <p class="text-sm text-error">
          {gettext("A loss reason is required to mark this lead as lost.")}
        </p>
        <.input
          type="textarea"
          name="loss_reason[loss_reason]"
          value=""
          label={gettext("Loss reason")}
          required
        />
        <div class="mt-3 flex gap-3">
          <.button variant="danger" type="submit">{gettext("Mark as lost")}</.button>
          <.button variant="ghost" type="button" phx-click="cancel_loss_reason">
            {gettext("Cancel")}
          </.button>
        </div>
      </.form>
    </div>
    """
  end

  attr :lead, Lead, required: true

  defp callback_form(assigns) do
    ~H"""
    <.form
      :let={f}
      for={%{}}
      name="callback_at"
      phx-submit="schedule_callback"
      class="mt-6 space-y-3"
    >
      <h3 class="text-sm font-semibold uppercase tracking-wide text-ink/60">
        {gettext("Schedule callback")}
      </h3>
      <.input
        field={f[:callback_at]}
        type="datetime-local"
        label={gettext("Callback at")}
        value={callback_at_value(@lead.callback_at)}
        required
      />
      <.button type="submit" variant="secondary">
        {gettext("Save callback")}
      </.button>
    </.form>
    """
  end

  attr :lead, Lead, required: true
  attr :call_outcomes, :list, required: true

  defp call_log_form(assigns) do
    ~H"""
    <div class="mt-6">
      <h3 class="mb-2 text-sm font-semibold uppercase tracking-wide text-ink/60">
        {gettext("Log call outcome")}
      </h3>
      <div class="flex flex-wrap gap-2">
        <.button
          :for={{outcome, label} <- @call_outcomes}
          variant="outline"
          size="sm"
          phx-click="log_call"
          phx-value-outcome={outcome}
        >
          {label}
        </.button>
      </div>
    </div>
    """
  end

  defp note_form(assigns) do
    ~H"""
    <.form
      :let={f}
      for={%{}}
      name="note"
      phx-submit="add_note"
      class="mt-6 space-y-3"
    >
      <h3 class="text-sm font-semibold uppercase tracking-wide text-ink/60">
        {gettext("Note")}
      </h3>
      <.input
        field={f[:body]}
        type="textarea"
        name="note[body]"
        label={gettext("Add a note")}
        placeholder={gettext("What did you discuss?")}
        required
      />
      <.button type="submit" variant="primary">
        {gettext("Add note")}
      </.button>
    </.form>
    """
  end

  attr :activities, :list, required: true

  defp timeline(assigns) do
    ~H"""
    <ul id="timeline" class="space-y-4">
      <li :if={@activities == []} class="text-ink/50">
        {gettext("No activity yet")}
      </li>
      <li :for={activity <- @activities} id={"activity-#{activity.id}"} class="flex gap-3">
        <div class="flex size-8 shrink-0 items-center justify-center rounded-full bg-bg text-ink/70">
          <.icon name={activity_icon(activity.kind)} class="size-4" />
        </div>
        <div class="flex-1">
          <div class="flex items-center gap-2">
            <span class="text-sm font-semibold text-ink">
              {activity_kind_label(activity.kind)}
            </span>
            <span class="text-xs text-ink/50">
              {format_datetime(activity.happened_at)}
            </span>
          </div>
          <p :if={activity.body} class="mt-1 text-sm text-ink/80">{activity.body}</p>
          <p :if={map_size(activity.metadata || %{}) > 0} class="mt-1 text-xs text-ink/60">
            <code>{inspect(activity.metadata)}</code>
          </p>
        </div>
      </li>
    </ul>
    """
  end

  defp refresh_activities(socket) do
    activities = Leads.list_activities(socket.assigns.lead)
    assign(socket, :activities, activities)
  end

  defp allowed_next_statuses(status) do
    Map.get(Leads.transitions(), status, [])
  end

  defp vehicle_labels(%Quote{} = quote_record) do
    %{
      make: fetch_name(Vehicles.Make, quote_record.make_id),
      model: fetch_name(Vehicles.Model, quote_record.model_id),
      version: fetch_name(Vehicles.Version, quote_record.version_id)
    }
  end

  defp fetch_name(_schema, nil), do: gettext("—")

  defp fetch_name(schema, id) do
    case Repo.get(schema, id) do
      nil -> gettext("—")
      %{name: name} -> name
    end
  end

  defp decrypted_phone(%Quote{phone_enc: nil}), do: nil

  defp decrypted_phone(%Quote{} = quote_record) do
    case Sahla.Encrypted.Binary.load(quote_record.phone_enc) do
      {:ok, phone} -> phone
      _ -> nil
    end
  end

  defp whatsapp_link(_token, _offer_id, ""), do: nil
  defp whatsapp_link(_token, _offer_id, nil), do: nil

  defp whatsapp_link(token, offer_id, number) do
    message =
      gettext("Hello, following up on your Sahla quote %{token}", token: token)

    params =
      if offer_id do
        [{"offer_id", to_string(offer_id)} | []]
      else
        []
      end

    encoded = URI.encode_query([{"text", message} | params])
    "https://wa.me/#{strip_whatsapp_prefix(number)}?#{encoded}"
  end

  defp strip_whatsapp_prefix("+" <> rest), do: rest
  defp strip_whatsapp_prefix("00" <> rest), do: rest
  defp strip_whatsapp_prefix(number), do: number

  defp call_outcome_label(outcome) do
    Enum.find_value(@call_outcomes, gettext("Call"), fn {key, label} ->
      if key == outcome, do: label, else: nil
    end)
  end

  defp activity_icon(:note), do: "hero-pencil-square"
  defp activity_icon(:appel), do: "hero-phone"
  defp activity_icon(:sms), do: "hero-chat-bubble-bottom-center-text"
  defp activity_icon(:whatsapp), do: "hero-chat-bubble-left-ellipsis"
  defp activity_icon(:email), do: "hero-envelope"
  defp activity_icon(:statut), do: "hero-arrow-path"
  defp activity_icon(:rdv), do: "hero-calendar"
  defp activity_icon(_kind), do: "hero-document-text"

  defp activity_kind_label(:note), do: gettext("Note")
  defp activity_kind_label(:appel), do: gettext("Call")
  defp activity_kind_label(:sms), do: gettext("SMS")
  defp activity_kind_label(:whatsapp), do: gettext("WhatsApp")
  defp activity_kind_label(:email), do: gettext("Email")
  defp activity_kind_label(:statut), do: gettext("Status")
  defp activity_kind_label(:rdv), do: gettext("Appointment")
  defp activity_kind_label(_kind), do: gettext("Event")

  defp parse_callback_at(value) when is_binary(value) do
    case NaiveDateTime.from_iso8601(value) do
      {:ok, naive} ->
        dt = DateTime.from_naive!(naive, "Etc/UTC")
        {:ok, dt}

      _ ->
        :error
    end
  end

  defp parse_callback_at(_), do: :error

  defp callback_at_value(%DateTime{} = dt) do
    dt
    |> DateTime.to_naive()
    |> NaiveDateTime.to_iso8601()
    |> String.replace_suffix(":00", "")
    |> String.replace_suffix(":00", "")
  end

  defp callback_at_value(nil), do: ""

  defp format_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M UTC")
  end

  defp format_datetime(%NaiveDateTime{} = naive) do
    DateTime.from_naive!(naive, "Etc/UTC")
    |> format_datetime()
  end

  defp format_datetime(nil), do: gettext("—")
end
