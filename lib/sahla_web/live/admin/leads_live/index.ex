defmodule SahlaWeb.Admin.LeadsLive.Index do
  @moduledoc """
  Admin leads kanban at `/admin/leads`.

  One column per status, each backed by a LiveView stream. Filters compose on
  the server; PubSub keeps the board live as leads are created or updated.
  Drag-and-drop between columns calls `Leads.transition_status/3`; illegal
  moves revert automatically because the server simply does not update the
  lead's status.
  """
  use SahlaWeb, :live_view

  on_mount {SahlaWeb.AdminAuthz, :leads}

  alias Sahla.Accounts.Admin
  alias Sahla.Cities
  alias Sahla.Leads
  alias Sahla.Leads.Lead
  alias Sahla.Quoting.Enums
  alias Sahla.Repo

  require Ecto.Query
  import Ecto.Query, only: [from: 1, from: 2, order_by: 3]

  @statuses Lead.statuses()

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
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, gettext("Leads"))
      |> assign(:status_labels, @status_labels)
      |> assign(:status_variants, @status_variants)
      |> assign(:statuses, @statuses)
      |> assign(:agents, list_agents())
      |> assign(:sources, list_sources())
      |> assign(:cities, list_cities())
      |> assign(:formulas, formula_options())
      |> assign(:filters, %{})
      |> assign(:filter_changeset, filter_changeset(%{}))
      |> assign_counts()

    if connected?(socket) do
      Leads.subscribe()
    end

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = parse_filters(params)

    socket =
      socket
      |> assign(:filters, filters)
      |> assign(:filter_changeset, filter_changeset(filters))
      |> stream_leads(filters)

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter", %{"filter" => raw}, socket) do
    filters = parse_filters(raw)

    socket =
      socket
      |> assign(:filters, filters)
      |> assign(:filter_changeset, filter_changeset(filters))
      |> stream_leads(filters)

    {:noreply, push_patch(socket, to: ~p"/admin/leads?#{to_filter_params(filters)}")}
  end

  def handle_event("reset_filters", _params, socket) do
    filters = %{}

    socket =
      socket
      |> assign(:filters, filters)
      |> assign(:filter_changeset, filter_changeset(filters))
      |> stream_leads(filters)

    {:noreply, push_patch(socket, to: ~p"/admin/leads")}
  end

  def handle_event("drop", %{"id" => id, "status" => status}, socket) do
    lead = Leads.get_lead!(id)
    new_status = String.to_existing_atom(status)

    case Leads.transition_status(lead, new_status,
           admin_id: socket.assigns.current_admin && socket.assigns.current_admin.id
         ) do
      {:ok, updated} ->
        {:noreply, move_lead_in_stream(socket, updated)}

      {:error, _reason} ->
        # Illegal transition / terminal: the stream item stays where the user
        # dropped it until the next stream reset, which effectively reverts it.
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:lead, _event, id}, socket) do
    filters = socket.assigns.filters

    case Leads.get_lead(id) do
      nil ->
        {:noreply, socket}

      lead ->
        if matches_filters?(lead, filters) do
          {:noreply, move_lead_in_stream(socket, lead)}
        else
          {:noreply, remove_lead_from_stream(socket, lead)}
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-[100rem] space-y-4 p-4 lg:p-6">
      <.header>
        {gettext("Leads")}
        <:subtitle>
          {gettext("Drag cards between columns to update status.")}
        </:subtitle>
      </.header>

      <.filter_bar
        changeset={@filter_changeset}
        agents={@agents}
        sources={@sources}
        cities={@cities}
        formulas={@formulas}
      />

      <div class="grid gap-4 md:grid-cols-2 xl:grid-cols-4 2xl:grid-cols-7">
        <.kanban_column
          :for={status <- @statuses}
          status={status}
          label={Map.fetch!(@status_labels, status)}
          variant={Map.fetch!(@status_variants, status)}
          count={Map.fetch!(@counts, status)}
          streams={@streams}
        />
      </div>
    </div>
    """
  end

  attr :changeset, :any, required: true
  attr :agents, :list, required: true
  attr :sources, :list, required: true
  attr :cities, :list, required: true
  attr :formulas, :list, required: true

  defp filter_bar(assigns) do
    ~H"""
    <.form
      :let={f}
      for={@changeset}
      phx-change="filter"
      phx-submit="filter"
      class="rounded-card bg-surface p-4 shadow-soft"
    >
      <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-4 xl:grid-cols-6">
        <.input
          field={f[:assigned_admin_id]}
          type="select"
          label={gettext("Assigned agent")}
          prompt={gettext("All agents")}
          options={@agents}
        />
        <.input
          field={f[:source]}
          type="select"
          label={gettext("Source")}
          prompt={gettext("All sources")}
          options={@sources}
        />
        <.input
          field={f[:city_id]}
          type="select"
          label={gettext("City")}
          prompt={gettext("All cities")}
          options={@cities}
        />
        <.input
          field={f[:formula]}
          type="select"
          label={gettext("Formula")}
          prompt={gettext("All formulas")}
          options={@formulas}
        />
        <.input field={f[:priority]} type="number" label={gettext("Min priority")} min="0" />
        <div class="grid grid-cols-2 gap-2">
          <.input field={f[:from]} type="date" label={gettext("From")} />
          <.input field={f[:to]} type="date" label={gettext("To")} />
        </div>
      </div>
      <div class="mt-3 flex justify-end">
        <.button type="button" variant="ghost" phx-click="reset_filters">
          {gettext("Reset")}
        </.button>
      </div>
    </.form>
    """
  end

  attr :status, :atom, required: true
  attr :label, :string, required: true
  attr :variant, :string, required: true
  attr :count, :integer, required: true
  attr :streams, :map, required: true

  defp kanban_column(assigns) do
    stream_key = to_string(assigns.status)

    assigns =
      assigns
      |> assign(:stream_key, stream_key)
      |> assign(:stream, Map.get(assigns.streams, stream_key))

    ~H"""
    <div
      class="flex flex-col rounded-card bg-surface shadow-soft"
      data-status={@stream_key}
      phx-drop-target={@stream_key}
    >
      <div class="flex items-center justify-between border-b border-ink/10 p-3">
        <div class="flex items-center gap-2">
          <.badge variant={@variant}>{@label}</.badge>
          <span class="text-sm text-ink/60" id={"count-" <> @stream_key}>{@count}</span>
        </div>
      </div>

      <%= if @stream && @count > 0 do %>
        <ul
          id={"column-#{@stream_key}"}
          phx-update="stream"
          class="min-h-[8rem] flex-1 space-y-3 p-3"
          data-status={@stream_key}
        >
          <li
            :for={{dom_id, lead} <- @stream}
            id={dom_id}
            draggable="true"
            phx-value-id={lead.id}
            class="cursor-grab rounded-card border border-ink/10 bg-bg p-3 shadow-sm active:cursor-grabbing"
          >
            <.lead_card lead={lead} />
          </li>
        </ul>
      <% end %>

      <%= if !@stream || @count == 0 do %>
        <div class="flex flex-1 items-center justify-center p-6" id={"empty-" <> @stream_key}>
          <p class="text-sm text-ink/50">{gettext("No leads")}</p>
        </div>
      <% end %>
    </div>
    """
  end

  attr :lead, Lead, required: true

  defp lead_card(assigns) do
    agent_name =
      if assigns.lead.assigned_admin,
        do: assigns.lead.assigned_admin.email,
        else: gettext("Unassigned")

    age = lead_age(assigns.lead.inserted_at)
    price = lead_price(assigns.lead)

    assigns =
      assigns
      |> assign(:agent_name, agent_name)
      |> assign(:age, age)
      |> assign(:price, price)

    ~H"""
    <div class="space-y-2">
      <div class="flex items-start justify-between gap-2">
        <.link navigate={~p"/admin/leads/#{@lead.id}"} class="font-semibold text-ink hover:underline">
          {display_name(@lead)}
        </.link>
        <.badge :if={@lead.priority > 0} variant="warning">{"P#{@lead.priority}"}</.badge>
      </div>

      <div class="text-sm text-ink/70">
        <p :if={@lead.quote && @lead.quote.formula}>
          {to_string(@lead.quote.formula)}
        </p>
        <p :if={@price}>
          <.price cents={@price} />
        </p>
      </div>

      <div class="flex items-center justify-between text-xs text-ink/60">
        <span>{@agent_name}</span>
        <span>{@age}</span>
      </div>
    </div>
    """
  end

  defp stream_leads(socket, filters) do
    leads =
      filters
      |> filtered_query()
      |> Repo.all()
      |> Repo.preload([:quote, :assigned_admin])

    leads_by_status = Enum.group_by(leads, & &1.status)

    socket =
      Enum.reduce(@statuses, socket, fn status, socket ->
        status_leads = Map.get(leads_by_status, status, [])
        stream_key = to_string(status)
        stream(socket, stream_key, status_leads, reset: true)
      end)

    update_counts(socket)
  end

  defp filtered_query(filters) do
    from(l in Lead)
    |> maybe_join_quote(filters)
    |> maybe_filter(:assigned_admin_id, filters[:assigned_admin_id])
    |> maybe_filter(:source, filters[:source])
    |> maybe_filter_city(filters[:city_id])
    |> maybe_filter_formula(filters[:formula])
    |> maybe_filter_date_range(filters[:from], filters[:to])
    |> maybe_filter_priority(filters[:priority])
    |> order_by([l], desc: l.inserted_at, desc: l.id)
  end

  defp maybe_join_quote(query, filters) do
    needs_join = filters[:city_id] not in [nil, ""] or filters[:formula] not in [nil, ""]

    if needs_join do
      from l in query, join: q in assoc(l, :quote), as: :quote
    else
      query
    end
  end

  defp maybe_filter(query, _field, nil), do: query
  defp maybe_filter(query, _field, ""), do: query

  defp maybe_filter(query, :assigned_admin_id, admin_id) do
    from l in query, where: l.assigned_admin_id == ^admin_id
  end

  defp maybe_filter(query, :source, source) do
    from l in query, where: l.source == ^source
  end

  defp maybe_filter_city(query, nil), do: query
  defp maybe_filter_city(query, ""), do: query

  defp maybe_filter_city(query, city_id) do
    from [l, quote: q] in query, where: q.city_id == ^city_id
  end

  defp maybe_filter_formula(query, nil), do: query
  defp maybe_filter_formula(query, ""), do: query

  defp maybe_filter_formula(query, formula) do
    from [l, quote: q] in query, where: q.formula == ^formula
  end

  defp maybe_filter_date_range(query, nil, nil), do: query

  defp maybe_filter_date_range(query, from, to) do
    from_dt = parse_date(from)
    to_dt = parse_date(to)

    cond do
      from_dt && to_dt ->
        to_dt_end = DateTime.add(to_dt, 1, :day)
        from l in query, where: l.inserted_at >= ^from_dt and l.inserted_at < ^to_dt_end

      from_dt ->
        from l in query, where: l.inserted_at >= ^from_dt

      to_dt ->
        to_dt_end = DateTime.add(to_dt, 1, :day)
        from l in query, where: l.inserted_at < ^to_dt_end

      true ->
        query
    end
  end

  defp maybe_filter_priority(query, nil), do: query
  defp maybe_filter_priority(query, ""), do: query

  defp maybe_filter_priority(query, priority) do
    priority = if is_binary(priority), do: String.to_integer(priority), else: priority
    from l in query, where: l.priority >= ^priority
  end

  defp parse_filters(params) when is_map(params) do
    params
    |> Map.take(filter_fields())
    |> Enum.map(fn {key, value} ->
      {String.to_existing_atom(key), value}
    end)
    |> Enum.into(%{})
  end

  defp parse_filters(_), do: %{}

  defp to_filter_params(filters) do
    filters
    |> Enum.reject(fn {_k, v} -> v in [nil, ""] end)
    |> Enum.map(fn {k, v} -> {to_string(k), v} end)
  end

  defp filter_changeset(filters) do
    Sahla.Leads.Filter.changeset(%Sahla.Leads.Filter{}, filters)
  end

  defp filter_fields, do: ~w(assigned_admin_id source city_id formula priority from to)

  defp move_lead_in_stream(socket, lead) do
    lead = Repo.preload(lead, [:quote, :assigned_admin])
    dom_id = "lead-#{lead.id}"

    socket =
      Enum.reduce(@statuses, socket, fn status, socket ->
        stream_key = to_string(status)

        if lead.status == status do
          stream_insert(socket, stream_key, lead, dom_id: dom_id)
        else
          stream_delete_by_dom_id(socket, stream_key, dom_id)
        end
      end)

    update_counts(socket)
  end

  defp remove_lead_from_stream(socket, lead) do
    dom_id = "lead-#{lead.id}"

    socket =
      Enum.reduce(@statuses, socket, fn status, socket ->
        stream_delete_by_dom_id(socket, to_string(status), dom_id)
      end)

    update_counts(socket)
  end

  defp update_counts(socket) do
    counts =
      Map.new(@statuses, fn status ->
        stream_key = to_string(status)
        stream = Map.get(socket.assigns.streams, stream_key)
        count = if stream, do: stream.inserts |> length(), else: 0
        {status, count}
      end)

    assign(socket, :counts, counts)
  end

  defp assign_counts(socket) do
    assign(socket, :counts, Map.new(@statuses, &{&1, 0}))
  end

  defp matches_filters?(lead, filters) do
    lead = Repo.preload(lead, [:quote, :assigned_admin])

    Enum.all?(filters, fn
      {:assigned_admin_id, v} when v not in [nil, ""] ->
        lead.assigned_admin_id == v

      {:source, v} when v not in [nil, ""] ->
        lead.source == v

      {:city_id, v} when v not in [nil, ""] ->
        lead.quote && lead.quote.city_id == v

      {:formula, v} when v not in [nil, ""] ->
        lead.quote && to_string(lead.quote.formula) == v

      {:priority, v} when v not in [nil, ""] ->
        priority = if is_binary(v), do: String.to_integer(v), else: v
        lead.priority >= priority

      {:from, v} when v not in [nil, ""] ->
        from_dt = parse_date!(v) |> DateTime.add(-1, :microsecond)
        DateTime.compare(lead.inserted_at, from_dt) in [:gt, :eq]

      {:to, v} when v not in [nil, ""] ->
        to_dt = parse_date!(v) |> DateTime.add(1, :day)
        DateTime.compare(lead.inserted_at, to_dt) == :lt

      _ ->
        true
    end)
  end

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil

  defp parse_date(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> DateTime.new!(date, ~T[00:00:00])
      _ -> nil
    end
  end

  defp parse_date!(value) do
    case parse_date(value) do
      %DateTime{} = dt -> dt
      nil -> DateTime.utc_now()
    end
  end

  defp list_agents do
    from(a in Admin, where: a.active == true, order_by: [asc: a.email])
    |> Repo.all()
    |> Enum.map(fn a -> {a.email, to_string(a.id)} end)
  end

  defp list_cities do
    Cities.list_cities()
    |> Enum.map(fn city -> {city.name_fr, to_string(city.id)} end)
  end

  defp list_sources do
    from(l in Lead,
      where: not is_nil(l.source),
      distinct: true,
      order_by: [asc: l.source],
      select: l.source
    )
    |> Repo.all()
    |> Enum.reject(&is_nil/1)
    |> Enum.map(fn s -> {s, s} end)
  end

  defp formula_options do
    Enum.map(Enums.formulas(), fn f ->
      {Gettext.gettext(Sahla.Gettext, String.capitalize(to_string(f))), to_string(f)}
    end)
  end

  defp display_name(lead) do
    quote_record = lead.quote

    cond do
      quote_record && quote_record.last_name && quote_record.first_name ->
        "#{quote_record.first_name} #{quote_record.last_name}"

      quote_record && quote_record.last_name ->
        quote_record.last_name

      quote_record && quote_record.first_name ->
        quote_record.first_name

      quote_record && quote_record.email ->
        quote_record.email

      true ->
        gettext("Lead #%{id}", id: String.slice(lead.id, 0, 8))
    end
  end

  defp lead_price(lead) do
    cond do
      Map.get(lead, :offer) && lead.offer.annual_premium_centimes ->
        lead.offer.annual_premium_centimes

      lead.quote && lead.quote.vehicle_value_centimes ->
        lead.quote.vehicle_value_centimes

      true ->
        nil
    end
  end

  defp lead_age(%DateTime{} = inserted_at) do
    now = DateTime.utc_now()
    diff_seconds = DateTime.diff(now, inserted_at, :second)

    cond do
      diff_seconds < 60 ->
        gettext("just now")

      diff_seconds < 3600 ->
        n = div(diff_seconds, 60)
        gettext("%{n} min", n: n)

      diff_seconds < 86400 ->
        n = div(diff_seconds, 3600)
        gettext("%{n} h", n: n)

      diff_seconds < 604_800 ->
        n = div(diff_seconds, 86400)
        gettext("%{n} d", n: n)

      true ->
        Calendar.strftime(inserted_at, "%Y-%m-%d")
    end
  end
end
