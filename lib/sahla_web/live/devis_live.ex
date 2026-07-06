defmodule SahlaWeb.DevisLive do
  @moduledoc """
  Resumable quote funnel shell (§5.2, §6.2, §7.3).

  Mount loads or creates a quote by token and resumes at its current step.
  phx-change autosaves the active step through `Quoting.upsert_step/3`.
  Continuer/Retour navigate between steps; current_step only advances.
  Expired quotes render a guarded state outside any stream container.

  Step forms are rendered as function components that receive the current
  quote and changeset. Server-side autocomplete, OTP verification and consent
  capture are handled via dedicated handle_event clauses.
  """
  use SahlaWeb, :live_view

  alias Sahla.Accounts.OTP
  alias Sahla.AntiBot
  alias Sahla.Cities
  alias Sahla.Compliance
  alias Sahla.Directory
  alias Sahla.Quoting
  alias Sahla.Quoting.Enums
  alias Sahla.Telemetry.Funnel, as: FunnelTelemetry
  alias Sahla.Uploads
  alias Sahla.Vehicles
  alias Sahla.Vehicles.Catalog

  @steps Quoting.steps()
  @step_count length(@steps)

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Quoting.get_quote_for_resume(token) do
        {:error, :not_found} ->
          {:ok, quote} = Quoting.create_quote(locale: socket.assigns.locale)
          redirect(socket, to: ~p"/devis/#{quote.token}")

        {:error, :expired, quote} ->
          socket
          |> assign(:expired, true)
          |> assign(:quote, quote)
          |> assign(:current_step, nil)
          |> assign(:step, nil)
          |> assign(:changeset, nil)
          |> assign(:turnstile_token, nil)

        {:ok, quote} ->
          step = step_atom(quote.current_step)

          socket
          |> push_event("plausible-event", %{name: "funnel_start", props: %{source: "resume"}})
          |> assign(:expired, false)
          |> assign(:quote, quote)
          |> assign(:current_step, quote.current_step)
          |> assign(:step, step)
          |> assign(:changeset, nil)
          |> assign(:turnstile_token, nil)
          |> reset_otp_state()
          |> allow_uploads()
      end

    {:ok, socket}
  end

  def mount(_params, _session, socket) do
    {:ok, quote} = Quoting.create_quote(locale: socket.assigns.locale)

    socket =
      socket
      |> push_event("plausible-event", %{name: "funnel_start", props: %{source: "new"}})
      |> redirect(to: ~p"/devis/#{quote.token}")

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("autosave", %{"step" => params}, socket) do
    step = socket.assigns.step
    quote = socket.assigns.quote

    params = normalize_step_params(params, step)

    # Record free-text vehicles only when the user is typing them intentionally.
    maybe_record_unmatched(params)

    case Quoting.upsert_step(quote, step, params) do
      {:ok, quote} ->
        socket =
          socket
          |> assign(:quote, quote)
          |> assign(:current_step, quote.current_step)
          |> assign(:changeset, nil)

        # If the phone changed, reset OTP verification UI.
        socket = maybe_reset_otp_on_phone_change(socket, step, params)

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  def handle_event("continue", _params, socket) do
    current = socket.assigns.current_step

    cond do
      current == 1 and not anti_bot_passes?(socket) ->
        {:noreply, anti_bot_blocked(socket)}

      current < @step_count ->
        next_step = current + 1
        {:ok, quote} = update_step(socket.assigns.quote, next_step)
        next_atom = step_atom(next_step)

        FunnelTelemetry.step_completed(
          quote.token,
          next_atom,
          next_step,
          socket.assigns.locale
        )

        socket =
          socket
          |> assign(:current_step, next_step)
          |> assign(:step, next_atom)
          |> assign(:quote, quote)
          |> assign(:changeset, nil)
          |> assign(:turnstile_token, nil)
          |> maybe_allow_uploads(next_atom)

        {:noreply, socket}

      true ->
        complete_and_redirect(socket)
    end
  end

  def handle_event("set_turnstile_token", %{"token" => token}, socket) do
    {:noreply, assign(socket, :turnstile_token, token)}
  end

  def handle_event("back", _params, socket) do
    current = socket.assigns.current_step

    if current > 1 do
      prev_step = current - 1
      {:ok, quote} = update_step(socket.assigns.quote, prev_step)

      {:noreply,
       socket
       |> assign(:current_step, prev_step)
       |> assign(:step, step_atom(prev_step))
       |> assign(:quote, quote)
       |> assign(:changeset, nil)
       |> maybe_allow_uploads(step_atom(prev_step))}
    else
      {:noreply, socket}
    end
  end

  # --- Step 1: vehicle autocomplete ------------------------------------------

  def handle_event("suggest_makes", %{"query" => query}, socket) do
    suggestions = Catalog.search_makes(query, limit: 6)
    {:noreply, assign(socket, :make_suggestions, suggestions)}
  end

  def handle_event("suggest_models", %{"query" => query, "make_id" => make_id}, socket) do
    suggestions =
      if make_id != "" do
        Catalog.search_models(make_id, query, limit: 6)
      else
        []
      end

    {:noreply, assign(socket, :model_suggestions, suggestions)}
  end

  def handle_event("suggest_versions", %{"query" => query, "model_id" => model_id}, socket) do
    suggestions =
      if model_id != "" do
        Catalog.search_versions(model_id, query, limit: 6)
      else
        []
      end

    {:noreply, assign(socket, :version_suggestions, suggestions)}
  end

  def handle_event("pick_make", %{"make_id" => id, "make_name" => name}, socket) do
    {:ok, quote} = Quoting.upsert_step(socket.assigns.quote, :vehicle, %{"make_id" => id})

    {:noreply,
     socket
     |> assign(:quote, quote)
     |> assign(:make_suggestions, [])
     |> push_event("autofill-make", %{name: name})}
  end

  def handle_event("pick_model", %{"model_id" => id, "model_name" => name}, socket) do
    {:ok, quote} = Quoting.upsert_step(socket.assigns.quote, :vehicle, %{"model_id" => id})

    {:noreply,
     socket
     |> assign(:quote, quote)
     |> assign(:model_suggestions, [])
     |> push_event("autofill-model", %{name: name})}
  end

  def handle_event("pick_version", %{"version_id" => id, "version_name" => name}, socket) do
    power = Vehicles.fiscal_power_for_version(id) || ""

    attrs = %{"version_id" => id, "fiscal_power" => power}

    {:ok, quote} = Quoting.upsert_step(socket.assigns.quote, :vehicle, attrs)

    {:noreply,
     socket
     |> assign(:quote, quote)
     |> assign(:version_suggestions, [])
     |> push_event("autofill-version", %{name: name, power: to_string(power)})}
  end

  # --- Step 2: driver / relevé upload ----------------------------------------

  def handle_event("upload_releve", _params, socket) do
    quote = socket.assigns.quote

    results =
      consume_uploaded_entries(socket, :releve_doc, fn %{path: path}, entry ->
        Uploads.store(%Plug.Upload{path: path, filename: entry.client_name})
      end)

    case results do
      [%Uploads{} = upload] ->
        attrs = %{
          "releve_doc_path" => Path.basename(upload.path),
          "releve_doc_meta" => %{
            "original_name" => upload.original_name,
            "content_type" => upload.content_type,
            "size" => upload.size,
            "stored_at" => DateTime.utc_now() |> DateTime.to_iso8601()
          }
        }

        case Quoting.upsert_step(quote, :driver, attrs) do
          {:ok, quote} ->
            {:noreply,
             socket
             |> assign(:quote, quote)
             |> assign(:changeset, nil)}

          {:error, changeset} ->
            {:noreply, assign(socket, :changeset, changeset)}
        end

      [{:error, reason}] ->
        {:noreply,
         socket
         |> put_flash(:error, upload_error_message(reason))
         |> assign(:changeset, nil)}

      [] ->
        {:noreply, put_flash(socket, :error, gettext("No file selected"))}
    end
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :releve_doc, ref)}
  end

  # --- Step 4: OTP -----------------------------------------------------------

  def handle_event("request_otp", _params, socket) do
    quote = socket.assigns.quote
    phone = quote.phone_hash && raw_phone(quote)

    if is_binary(phone) do
      case OTP.request_otp(phone, ip: client_ip(socket)) do
        {:ok, _otp} ->
          {:noreply,
           socket
           |> assign(:otp_requested_at, DateTime.utc_now())
           |> assign(:otp_error, nil)
           |> put_flash(:info, gettext("Code sent"))}

        {:error, {:rate_limited, retry_after}} ->
          {:noreply,
           socket
           |> assign(:otp_error, gettext("Too many attempts; wait %{s}s", s: retry_after))}

        {:error, reason} ->
          {:noreply, assign(socket, :otp_error, otp_error_message(reason))}
      end
    else
      {:noreply, assign(socket, :otp_error, gettext("Enter a phone number first"))}
    end
  end

  def handle_event("verify_otp", %{"code" => code}, socket) do
    quote = Quoting.get_quote_by_token(socket.assigns.quote.token)
    phone = raw_phone(quote)

    if is_binary(phone) do
      case OTP.verify_otp(quote, phone, code) do
        {:ok, _quote} ->
          FunnelTelemetry.otp_verified(quote.token, socket.assigns.locale)

          {:noreply,
           socket
           |> assign(:quote, Quoting.get_quote_by_token(quote.token))
           |> assign(:otp_error, nil)}

        {:error, reason} ->
          {:noreply, assign(socket, :otp_error, otp_verify_error_message(reason))}
      end
    else
      {:noreply, assign(socket, :otp_error, gettext("Enter a phone number first"))}
    end
  end

  # --- Consent capture -------------------------------------------------------

  def handle_event(
        "capture_consents",
        %{
          "consent_cgu" => cgu,
          "consent_transmission" => transmission,
          "consent_marketing" => marketing
        },
        socket
      ) do
    quote = socket.assigns.quote

    case Compliance.capture_consents(quote, %{
           cgu: cgu == "true",
           transmission: transmission == "true",
           marketing: marketing == "true",
           ip: client_ip(socket)
         }) do
      {:ok, _consents} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Consent recorded"))
         |> push_event("consents-captured", %{})}

      {:error, :consent_required} ->
        {:noreply, assign(socket, :consent_error, gettext("Required consents are missing"))}

      {:error, changeset} ->
        {:noreply, assign(socket, :consent_error, format_changeset_errors(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-[60vh]">
      <%= if @expired do %>
        <section class="py-16 text-center">
          <h1 class="text-2xl font-bold text-ink">{gettext("This quote link has expired")}</h1>
          <p class="mt-4 text-ink/70">
            {gettext("Please start a new quote to get an up-to-date price estimate.")}
          </p>
          <div class="mt-8">
            <.link navigate={~p"/devis/new"} class="btn btn-primary">
              {gettext("Start a new quote")}
            </.link>
          </div>
        </section>
      <% else %>
        <section>
          <.progress current_step={@current_step} />

          <.card class="mt-6">
            <.step_form
              step={@step}
              quote={@quote}
              changeset={@changeset}
              current_step={@current_step}
              make_suggestions={Map.get(assigns, :make_suggestions, [])}
              model_suggestions={Map.get(assigns, :model_suggestions, [])}
              version_suggestions={Map.get(assigns, :version_suggestions, [])}
              otp_error={Map.get(assigns, :otp_error)}
              otp_requested_at={Map.get(assigns, :otp_requested_at)}
              consent_error={Map.get(assigns, :consent_error)}
              uploads={@uploads}
            />
          </.card>

          <div class="mt-6 flex items-center justify-between gap-4">
            <.button
              variant="ghost"
              phx-click="back"
              disabled={@current_step == 1}
            >
              {gettext("Back")}
            </.button>

            <.button
              variant="primary"
              phx-click="continue"
              disabled={!can_continue?(@step, @quote, @changeset)}
            >
              {gettext("Continue")}
            </.button>
          </div>
        </section>
      <% end %>
    </div>
    """
  end

  attr :current_step, :integer, required: true

  defp progress(assigns) do
    steps = Quoting.steps()
    total = length(steps)

    assigns =
      assign(assigns,
        steps: steps,
        total: total
      )

    ~H"""
    <div class="flex items-center justify-center gap-2" aria-label={gettext("Quote progress")}>
      <div :for={{name, number} <- @steps} class="flex items-center gap-2">
        <div class={[
          "flex size-10 items-center justify-center rounded-full border-2 font-semibold",
          @current_step >= number && "border-primary bg-primary text-white",
          @current_step < number && "border-ink/20 bg-surface text-ink/50"
        ]}>
          {number}
        </div>
        <span class={[
          "hidden text-sm sm:inline",
          @current_step >= number && "font-medium text-ink",
          @current_step < number && "text-ink/50"
        ]}>
          {step_label(name)}
        </span>
        <span :if={number != @total} class="me-2 ms-2 hidden h-0.5 w-8 bg-ink/10 sm:inline-block" />
      </div>
    </div>
    """
  end

  attr :step, :atom, required: true
  attr :quote, :any, required: true
  attr :changeset, :any, default: nil
  attr :current_step, :integer, required: true
  attr :make_suggestions, :list, default: []
  attr :model_suggestions, :list, default: []
  attr :version_suggestions, :list, default: []
  attr :otp_error, :any, default: nil
  attr :otp_requested_at, :any, default: nil
  attr :consent_error, :any, default: nil
  attr :uploads, :any, required: true

  defp step_form(%{step: :vehicle} = assigns) do
    quote = assigns.quote

    assigns =
      assigns
      |> assign(:makes, Vehicles.list_makes())
      |> assign(:cities, Cities.list_cities())
      |> assign(:autocomplete_mode, Map.get(assigns, :autocomplete_mode, true))
      |> assign(:vehicle, vehicle_defaults(quote))
      |> assign(:errors, step_errors(assigns.changeset))
      |> assign(:value_required, quote.formula in Enums.valued_formulas())
      |> assign(:turnstile_enabled, turnstile_enabled?())
      |> assign(:turnstile_site_key, turnstile_site_key())

    ~H"""
    <form phx-change="autosave" class="space-y-5" id="vehicle-form">
      <h2 class="text-xl font-semibold text-ink">{gettext("Your vehicle")}</h2>

      <.turnstile_widget
        :if={@turnstile_enabled and @turnstile_site_key}
        site_key={@turnstile_site_key}
        token={Map.get(assigns, :turnstile_token)}
      />

      <.input type="hidden" name="step[is_new_ww]" value={to_string(@vehicle[:is_new_ww])} />

      <div class="flex items-center justify-between gap-4 rounded-card border border-ink/10 bg-surface p-4">
        <span class="text-sm font-medium text-ink">{gettext("New vehicle / hors-série (WW)")}</span>
        <button
          type="button"
          phx-click={
            JS.push("autosave", value: %{step: %{is_new_ww: to_string(!@vehicle[:is_new_ww])}})
          }
          class={[
            "relative inline-flex h-7 w-12 shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-2",
            @vehicle[:is_new_ww] && "bg-primary",
            !@vehicle[:is_new_ww] && "bg-ink/20"
          ]}
          role="switch"
          aria-checked={to_string(@vehicle[:is_new_ww])}
        >
          <span class={[
            "inline-block h-6 w-6 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out",
            @vehicle[:is_new_ww] && "translate-x-5",
            !@vehicle[:is_new_ww] && "translate-x-0"
          ]} />
        </button>
      </div>

      <div :if={!@vehicle[:is_new_ww]} class="space-y-2">
        <.input
          name="step[plate]"
          label={gettext("Licence plate")}
          value={@vehicle[:plate]}
          placeholder="12345-A-67"
          phx-hook="PlateMask"
          maxlength="10"
          errors={@errors[:plate] || []}
        />
        <p class="text-xs text-ink/60">{gettext("Format: 12345-A-67")}</p>
      </div>

      <.input type="hidden" name="step[autocomplete]" value={to_string(@vehicle[:autocomplete])} />

      <div :if={@vehicle[:autocomplete]} class="space-y-3">
        <.autocomplete_input
          name="make"
          label={gettext("Make")}
          selected_id={@vehicle[:make_id]}
          selected_name={@vehicle[:make_name]}
          event="suggest_makes"
          suggestions={@make_suggestions}
        />
        <.autocomplete_input
          name="model"
          label={gettext("Model")}
          selected_id={@vehicle[:model_id]}
          selected_name={@vehicle[:model_name]}
          event="suggest_models"
          suggestions={@model_suggestions}
        />
        <.autocomplete_input
          name="version"
          label={gettext("Version")}
          selected_id={@vehicle[:version_id]}
          selected_name={@vehicle[:version_name]}
          event="suggest_versions"
          suggestions={@version_suggestions}
        />
      </div>

      <div :if={!@vehicle[:autocomplete]} class="space-y-3">
        <.input
          name="step[raw_make]"
          label={gettext("Make (free text)")}
          value={@vehicle[:raw_make]}
          errors={@errors[:raw_make] || []}
        />
        <.input
          name="step[raw_model]"
          label={gettext("Model (free text)")}
          value={@vehicle[:raw_model]}
          errors={@errors[:raw_model] || []}
        />
        <.input
          name="step[raw_version]"
          label={gettext("Version (free text)")}
          value={@vehicle[:raw_version]}
          errors={@errors[:raw_version] || []}
        />
      </div>

      <button
        type="button"
        phx-click={
          JS.push("autosave", value: %{step: %{autocomplete: to_string(!@vehicle[:autocomplete])}})
        }
        class="text-sm font-medium text-primary hover:underline"
      >
        <%= if @vehicle[:autocomplete] do %>
          {gettext("My vehicle is not in the list — type it manually")}
        <% else %>
          {gettext("Choose from the catalog instead")}
        <% end %>
      </button>

      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <.input
          name="step[fiscal_power]"
          type="number"
          label={gettext("Fiscal power (CV)")}
          value={@vehicle[:fiscal_power]}
          min="1"
          errors={@errors[:fiscal_power] || []}
        />
        <.input
          name="step[fuel]"
          type="select"
          label={gettext("Fuel")}
          options={fuel_options()}
          value={@vehicle[:fuel]}
          prompt={gettext("Choose fuel")}
          errors={@errors[:fuel] || []}
        />
      </div>

      <.input
        name="step[first_registration]"
        type="date"
        label={gettext("First registration date")}
        value={@vehicle[:first_registration]}
        errors={@errors[:first_registration] || []}
      />

      <.input
        :if={@value_required}
        name="step[vehicle_value_centimes]"
        type="number"
        label={gettext("Vehicle value (MAD)")}
        value={@vehicle[:vehicle_value_centimes]}
        min="1"
        required
        errors={@errors[:vehicle_value_centimes] || []}
      />

      <fieldset class="space-y-2">
        <legend class="text-sm font-medium text-ink">{gettext("Usage")}</legend>
        <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <.option_card
            :for={{label, value} <- usage_options()}
            name="step[usage]"
            value={value}
            label={label}
            selected={@vehicle[:usage] == value}
          />
        </div>
      </fieldset>

      <fieldset class="space-y-2">
        <legend class="text-sm font-medium text-ink">{gettext("City")}</legend>
        <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <.option_card
            :for={city <- @cities}
            name="step[city_id]"
            value={city.id}
            label={city.name_fr}
            selected={@vehicle[:city_id] == to_string(city.id)}
          />
        </div>
      </fieldset>

      <fieldset class="space-y-2">
        <legend class="text-sm font-medium text-ink">{gettext("Parking")}</legend>
        <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <.option_card
            :for={{label, value} <- parking_options()}
            name="step[parking]"
            value={value}
            label={label}
            selected={@vehicle[:parking] == value}
          />
        </div>
      </fieldset>
    </form>
    """
  end

  defp step_form(%{step: :coverage} = assigns) do
    coverage = coverage_defaults(assigns.quote)
    errors = step_errors(assigns.changeset)

    assigns =
      assigns
      |> assign(:coverage, coverage)
      |> assign(:errors, errors)

    ~H"""
    <form phx-change="autosave" class="space-y-5" id="coverage-form">
      <h2 class="text-xl font-semibold text-ink">{gettext("Coverage")}</h2>

      <fieldset class="space-y-2">
        <legend class="text-sm font-medium text-ink">{gettext("Choose your formula")}</legend>
        <div class="grid grid-cols-1 gap-3 sm:grid-cols-3">
          <.option_card
            name="step[formula]"
            value="rc"
            label={gettext("RC seule")}
            description={gettext("Civil liability — mandatory third-party coverage.")}
            selected={@coverage[:formula] == "rc"}
          />
          <.option_card
            name="step[formula]"
            value="tiers_etendu"
            label={gettext("Tiers étendu")}
            description={gettext("Third-party plus theft, fire and glass breakage.")}
            selected={@coverage[:formula] == "tiers_etendu"}
          />
          <.option_card
            name="step[formula]"
            value="tous_risques"
            label={gettext("Tous risques")}
            description={gettext("Full cover including accidental damage to your vehicle.")}
            selected={@coverage[:formula] == "tous_risques"}
          />
        </div>
      </fieldset>

      <fieldset class="space-y-2">
        <legend class="text-sm font-medium text-ink">{gettext("Guarantee options")}</legend>
        <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <.coverage_option
            :for={{label, code} <- guarantee_options()}
            code={code}
            label={label}
            checked={code in @coverage[:options]}
            disabled={code == "evcat"}
          />
        </div>
      </fieldset>

      <fieldset :if={@coverage[:formula] not in [nil, "rc"]} class="space-y-2">
        <legend class="text-sm font-medium text-ink">{gettext("Franchise preference")}</legend>
        <div class="grid grid-cols-1 gap-3 sm:grid-cols-3">
          <.option_card
            :for={{label, value} <- franchise_options()}
            name="step[franchise_pref]"
            value={value}
            label={label}
            selected={@coverage[:franchise_pref] == value}
          />
        </div>
      </fieldset>

      <.input
        name="step[effect_date]"
        type="date"
        label={gettext("Coverage effective date")}
        value={@coverage[:effect_date]}
        errors={@errors[:effect_date] || []}
      />

      <input type="hidden" name="step[options][]" value="evcat" />
    </form>
    """
  end

  defp step_form(%{step: :driver} = assigns) do
    quote = assigns.quote
    errors = step_errors(assigns.changeset)
    driver = driver_defaults(quote)
    insurers = Directory.list_active_insurers()
    crm_known = not is_nil(driver[:crm]) and driver[:crm] != ""

    assigns =
      assigns
      |> assign(:driver, driver)
      |> assign(:errors, errors)
      |> assign(:insurers, insurers)
      |> assign(:crm_known, crm_known)

    ~H"""
    <form phx-change="autosave" phx-submit="upload_releve" class="space-y-5" id="driver-form">
      <h2 class="text-xl font-semibold text-ink">{gettext("Driver profile")}</h2>

      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <.input
          name="step[birth_date]"
          type="date"
          label={gettext("Birth date")}
          value={@driver[:birth_date]}
          errors={@errors[:birth_date] || []}
        />
        <.input
          name="step[license_date]"
          type="date"
          label={gettext("Licence date")}
          value={@driver[:license_date]}
          errors={@errors[:license_date] || []}
        />
      </div>

      <fieldset class="space-y-2">
        <legend class="text-sm font-medium text-ink">{gettext("Public servant?")}</legend>
        <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <.option_card
            name="step[is_public_servant]"
            value="true"
            label={gettext("Yes")}
            selected={@driver[:is_public_servant] == true}
          />
          <.option_card
            name="step[is_public_servant]"
            value="false"
            label={gettext("No")}
            selected={@driver[:is_public_servant] == false}
          />
        </div>
      </fieldset>

      <.input
        name="step[current_insurer_id]"
        type="select"
        label={gettext("Current insurer")}
        options={insurer_options(@insurers)}
        value={@driver[:current_insurer_id]}
        prompt={gettext("None / First insurance")}
        errors={@errors[:current_insurer_id] || []}
      />

      <.input
        name="step[current_expiry]"
        type="date"
        label={gettext("Current policy expiry date")}
        value={@driver[:current_expiry]}
        errors={@errors[:current_expiry] || []}
      />

      <fieldset class="space-y-2">
        <legend class="text-sm font-medium text-ink">
          {gettext("At-fault claims in the last 36 months")}
        </legend>
        <div class="grid grid-cols-1 gap-3 sm:grid-cols-3">
          <.option_card
            name="step[at_fault_claims_36m]"
            value="0"
            label={gettext("0")}
            selected={@driver[:at_fault_claims_36m] == "0"}
          />
          <.option_card
            name="step[at_fault_claims_36m]"
            value="1"
            label={gettext("1")}
            selected={@driver[:at_fault_claims_36m] == "1"}
          />
          <.option_card
            name="step[at_fault_claims_36m]"
            value="2_or_more"
            label={gettext("2 or more")}
            selected={@driver[:at_fault_claims_36m] == "2_or_more"}
          />
        </div>
      </fieldset>

      <div class="space-y-3 rounded-card border border-ink/10 bg-surface p-4">
        <div class="flex items-center justify-between">
          <span class="text-sm font-medium text-ink">{gettext("Current CRM")}</span>
          <label class="inline-flex items-center gap-2 text-sm text-ink/80">
            <input
              type="hidden"
              name="step[crm]"
              value={if @crm_known, do: @driver[:crm], else: ""}
            />
            <input
              type="checkbox"
              phx-click={JS.push("autosave", value: %{step: %{crm: ""}})}
              checked={not @crm_known}
              class="checkbox checkbox-sm"
            />
            {gettext("I don't know")}
          </label>
        </div>

        <input
          :if={@crm_known}
          type="range"
          name="step[crm]"
          min="0.50"
          max="2.50"
          step="0.01"
          value={@driver[:crm]}
          class="w-full"
        />
        <p :if={@crm_known} class="text-sm font-medium text-primary">
          {@driver[:crm]}
        </p>
      </div>

      <div class="space-y-2">
        <label class="block text-sm font-medium text-ink">
          {gettext("Relevé d'information (optional)")}
        </label>
        <.live_file_input upload={@uploads.releve_doc} class="w-full input" accept="image/*,.pdf" />
        <p class="text-xs text-ink/60">{gettext("Upload an image or PDF (max 8 MB).")}</p>

        <div :for={entry <- @uploads.releve_doc.entries} class="space-y-1">
          <div class="flex items-center justify-between text-sm">
            <span class="text-ink/80">{entry.client_name}</span>
            <button
              type="button"
              phx-click="cancel-upload"
              phx-value-ref={entry.ref}
              class="text-error hover:underline"
            >
              {gettext("Cancel")}
            </button>
          </div>
          <p :for={err <- upload_errors(@uploads.releve_doc, entry)} class="mt-1.5 text-sm text-error">
            {err}
          </p>
        </div>

        <div :if={@driver[:releve_doc_path]}>
          <p class="text-sm text-ink/80">
            {gettext("Uploaded document:")} {@driver[:releve_doc_meta]["original_name"] ||
              @driver[:releve_doc_path]}
          </p>
        </div>
      </div>
    </form>
    """
  end

  defp step_form(%{step: :contact} = assigns) do
    quote = assigns.quote
    verified? = not is_nil(quote.phone_verified_at)

    assigns =
      assigns
      |> assign(:contact, contact_defaults(quote))
      |> assign(:cities, Cities.list_cities())
      |> assign(:verified, verified?)
      |> assign(:errors, step_errors(assigns.changeset))
      |> assign(:otp_requested_at, Map.get(assigns, :otp_requested_at))

    ~H"""
    <form phx-change="autosave" phx-submit="capture_consents" class="space-y-5" id="contact-form">
      <h2 class="text-xl font-semibold text-ink">{gettext("Contact details")}</h2>

      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <.input
          name="step[first_name]"
          label={gettext("First name")}
          value={@contact[:first_name]}
          required
        />
        <.input
          name="step[last_name]"
          label={gettext("Last name")}
          value={@contact[:last_name]}
          required
        />
      </div>

      <.input
        name="step[phone]"
        type="tel"
        label={gettext("Phone")}
        value={@contact[:phone]}
        placeholder="0612345678"
        required
      />

      <.input
        name="step[email]"
        type="email"
        label={gettext("Email (optional)")}
        value={@contact[:email]}
      />
      <p class="text-xs text-ink/60">{gettext("Receive your quote summary by email.")}</p>

      <.input
        name="step[city_id]"
        type="select"
        label={gettext("City")}
        options={Enum.map(@cities, fn c -> {c.name_fr, c.id} end)}
        value={@contact[:city_id]}
        prompt={gettext("Choose city")}
      />

      <div class="rounded-card border border-ink/10 bg-surface p-4 space-y-3">
        <h3 class="font-medium text-ink">{gettext("Verify your phone")}</h3>

        <.button type="button" variant="secondary" phx-click="request_otp" disabled={@verified}>
          {gettext("Send verification code")}
        </.button>

        <%= if @verified do %>
          <p class="text-sm text-success">{gettext("Phone verified")}</p>
        <% else %>
          <div id="otp-inputs" phx-hook="OtpAutoAdvance" class="flex gap-2">
            <input
              :for={idx <- 0..5}
              type="text"
              inputmode="numeric"
              maxlength="1"
              data-otp-index={idx}
              class="w-10 input text-center"
              autocomplete="one-time-code"
            />
          </div>
        <% end %>

        <label :if={not @verified} class="block space-y-1">
          <span class="text-sm font-medium text-ink">{gettext("Verification code")}</span>
          <input
            type="text"
            name="code"
            maxlength="6"
            placeholder="123456"
            phx-change="verify_otp"
            class="w-full input"
          />
        </label>

        <p :if={@otp_error} class="text-sm text-error">{@otp_error}</p>
      </div>

      <fieldset class="space-y-2">
        <legend class="text-sm font-medium text-ink">{gettext("Consents")}</legend>

        <label class="flex items-start gap-3 rounded-card border border-ink/10 bg-surface p-3">
          <input
            type="checkbox"
            name="consent_cgu"
            value="true"
            class="checkbox checkbox-sm mt-0.5"
            required
          />
          <span class="text-sm text-ink/80">
            {gettext("I accept the CGU and privacy policy")} *
          </span>
        </label>

        <label class="flex items-start gap-3 rounded-card border border-ink/10 bg-surface p-3">
          <input
            type="checkbox"
            name="consent_transmission"
            value="true"
            class="checkbox checkbox-sm mt-0.5"
            required
          />
          <span class="text-sm text-ink/80">
            {gettext("I agree to share my data with partner insurers")} *
          </span>
        </label>

        <label class="flex items-start gap-3 rounded-card border border-ink/10 bg-surface p-3">
          <input
            type="checkbox"
            name="consent_marketing"
            value="true"
            class="checkbox checkbox-sm mt-0.5"
          />
          <span class="text-sm text-ink/80">
            {gettext("I agree to receive offers and news (optional)")}
          </span>
        </label>
      </fieldset>

      <p :if={@consent_error} class="text-sm text-error">{@consent_error}</p>
    </form>
    """
  end

  defp step_form(assigns) do
    ~H"""
    <p class="text-ink/70">{gettext("Unknown step")}</p>
    """
  end

  attr :name, :string, required: true
  attr :label, :string, required: true
  attr :selected_id, :any, default: nil
  attr :selected_name, :string, default: nil
  attr :event, :string, required: true
  attr :suggestions, :list, default: []

  defp autocomplete_input(assigns) do
    ~H"""
    <div class="autocomplete relative space-y-1" data-kind={@name}>
      <label class="label" for={"autocomplete-#{@name}"}>{@label}</label>
      <input
        type="text"
        id={"autocomplete-#{@name}"}
        name="autocomplete_#{@name}"
        value={@selected_name}
        placeholder={gettext("Search…")}
        phx-debounce="300"
        phx-change={@event}
        class="w-full input"
        autocomplete="off"
      />
      <input type="hidden" name="step[#{@name}_id]" value={@selected_id} />
      <ul
        :if={@suggestions != []}
        class="absolute z-10 mt-1 max-h-60 w-full overflow-auto rounded-card border border-ink/10 bg-surface shadow-soft"
      >
        <li
          :for={item <- @suggestions}
          class="cursor-pointer px-3 py-2 text-sm hover:bg-bg"
          phx-click={"pick_#{@name}"}
          phx-value-id={item.id}
          phx-value-name={item.name}
        >
          {item.name}
        </li>
      </ul>
    </div>
    """
  end

  attr :code, :string, required: true
  attr :label, :string, required: true
  attr :checked, :boolean, default: false
  attr :disabled, :boolean, default: false

  defp coverage_option(assigns) do
    ~H"""
    <label class={[
      "group relative flex cursor-pointer items-center gap-3 rounded-card border-2 p-4 transition-colors",
      @checked && !@disabled && "border-primary bg-primary/5",
      !@checked && !@disabled && "border-ink/10 bg-surface hover:border-ink/20",
      @disabled && "cursor-default border-ink/10 bg-surface opacity-80"
    ]}>
      <input
        type="checkbox"
        name="step[options][]"
        value={@code}
        checked={@checked}
        disabled={@disabled}
        class="checkbox checkbox-sm"
      />
      <span class={["font-medium text-ink", @disabled && "text-ink/70"]}>{@label}</span>
    </label>
    """
  end

  attr :site_key, :string, required: true
  attr :token, :any, default: nil

  defp turnstile_widget(assigns) do
    assigns = assign(assigns, :verified, is_binary(assigns.token) and assigns.token != "")

    ~H"""
    <div class="space-y-2 rounded-card border border-ink/10 bg-surface p-4">
      <div class="flex items-center justify-between">
        <span class="text-sm font-medium text-ink">
          {gettext("Security check")}
        </span>
        <span :if={@verified} class="text-sm text-success">{gettext("Verified")}</span>
      </div>
      <div
        id="turnstile-widget"
        phx-hook="Turnstile"
        data-sitekey={@site_key}
        data-token-target="turnstile-token"
      >
      </div>
      <input type="hidden" id="turnstile-token" name="turnstile_token" value={@token || ""} />
      <p class="text-xs text-ink/60">
        {gettext("Complete the challenge to continue.")}
      </p>
    </div>
    """
  end

  # --- Helpers ---------------------------------------------------------------

  defp vehicle_defaults(quote) do
    %{
      plate: quote.plate || "",
      is_new_ww: quote.is_new_ww || false,
      autocomplete: true,
      make_id: safe_string_id(quote.make_id),
      make_name: "",
      model_id: safe_string_id(quote.model_id),
      model_name: "",
      version_id: safe_string_id(quote.version_id),
      version_name: "",
      raw_make: "",
      raw_model: "",
      raw_version: "",
      fiscal_power: quote.fiscal_power || "",
      fuel: to_string(quote.fuel || ""),
      first_registration: format_date(quote.first_registration),
      usage: to_string(quote.usage || ""),
      city_id: safe_string_id(quote.city_id),
      parking: to_string(quote.parking || ""),
      vehicle_value_centimes: quote.vehicle_value_centimes || ""
    }
  end

  defp coverage_defaults(quote) do
    formula = quote.formula || :rc
    formula_str = to_string(formula)

    options =
      case quote.options do
        nil -> ["evcat"]
        list -> Enum.uniq(list ++ ["evcat"])
      end

    effect_date =
      format_non_empty_date(quote.effect_date) ||
        format_non_empty_date(quote.current_expiry) ||
        Date.to_iso8601(Date.utc_today())

    %{
      formula: formula_str,
      options: options,
      franchise_pref: to_string(quote.franchise_pref || ""),
      effect_date: effect_date,
      value_required: formula in Enums.valued_formulas()
    }
  end

  defp contact_defaults(quote) do
    %{
      first_name: quote.first_name || "",
      last_name: quote.last_name || "",
      phone: raw_phone(quote) || "",
      email: quote.email || "",
      city_id: safe_string_id(quote.city_id)
    }
  end

  defp driver_defaults(quote) do
    at_fault =
      case quote.at_fault_claims_36m do
        nil -> ""
        n when is_integer(n) and n >= 2 -> "2_or_more"
        n -> to_string(n)
      end

    %{
      birth_date: format_date(quote.birth_date),
      license_date: format_date(quote.license_date),
      is_public_servant: quote.is_public_servant || false,
      current_insurer_id: safe_string_id(quote.current_insurer_id),
      current_expiry: format_date(quote.current_expiry),
      at_fault_claims_36m: at_fault,
      crm: format_decimal(quote.crm),
      releve_doc_path: quote.releve_doc_path || "",
      releve_doc_meta: quote.releve_doc_meta_enc || %{}
    }
  end

  defp format_decimal(nil), do: ""
  defp format_decimal(%Decimal{} = d), do: Decimal.to_string(d)
  defp format_decimal(value), do: to_string(value)

  defp insurer_options(insurers) do
    Enum.map(insurers, fn i -> {i.name_fr, to_string(i.id)} end)
  end

  defp raw_phone(quote) do
    case quote.phone_enc do
      nil ->
        nil

      <<1, _::binary>> = enc ->
        case Sahla.Encrypted.Binary.load(enc) do
          {:ok, phone} -> phone
          _ -> nil
        end

      phone ->
        # Fallback for rows that store the phone in plaintext (legacy / test fixtures).
        phone
    end
  end

  defp safe_string_id(nil), do: nil
  defp safe_string_id(id), do: to_string(id)

  defp format_date(nil), do: ""
  defp format_date(%Date{} = date), do: Date.to_iso8601(date)

  defp format_non_empty_date(nil), do: nil
  defp format_non_empty_date(%Date{} = date), do: Date.to_iso8601(date)

  defp step_errors(nil), do: %{}

  defp step_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Regex.replace(~r/%\{(\w+)\}/, msg, fn _, key ->
        to_string(Keyword.get(opts, String.to_atom(key), "..."))
      end)
    end)
    |> Map.new(fn {field, [first | _]} -> {field, [first]} end)
  end

  defp step_label(:vehicle), do: gettext("Vehicle")
  defp step_label(:driver), do: gettext("Driver")
  defp step_label(:coverage), do: gettext("Coverage")
  defp step_label(:contact), do: gettext("Contact")

  defp step_atom(number) when is_integer(number) and number > 0 do
    @steps
    |> Enum.find(fn {_atom, n} -> n == number end)
    |> elem(0)
  end

  defp update_step(quote, next_step) do
    quote
    |> Ecto.Changeset.change(current_step: next_step)
    |> Sahla.Repo.update()
  end

  defp normalize_step_params(params, step) do
    params =
      params
      |> Map.new(fn {key, value} -> {key, value} end)
      |> normalize_driver_params(step)
      |> strip_consent_fields(step)

    Map.update(params, "options", ["evcat"], fn opts ->
      opts = List.wrap(opts)
      if "evcat" in opts, do: opts, else: opts ++ ["evcat"]
    end)
  end

  defp normalize_driver_params(params, :driver) do
    params
    |> Map.update("at_fault_claims_36m", nil, fn
      "2_or_more" -> "2"
      value when is_binary(value) -> value
      value -> value
    end)
    |> Map.update("is_public_servant", "false", fn
      value when value in ["true", "false"] -> value
      value when is_boolean(value) -> to_string(value)
      _ -> "false"
    end)
    |> nil_if_empty("crm")
    |> nil_if_empty("current_insurer_id")
  end

  defp normalize_driver_params(params, _step), do: params

  defp nil_if_empty(params, key) do
    case Map.get(params, key) do
      "" -> Map.put(params, key, nil)
      _ -> params
    end
  end

  defp strip_consent_fields(params, :contact) do
    Map.drop(params, ["consent_cgu", "consent_transmission", "consent_marketing"])
  end

  defp strip_consent_fields(params, _step), do: params

  defp maybe_record_unmatched(%{
         "autocomplete" => "false",
         "raw_make" => make,
         "raw_model" => model,
         "raw_version" => version
       })
       when is_binary(make) and make != "" and is_binary(model) and model != "" and
              is_binary(version) and version != "" do
    Vehicles.record_unmatched(%{raw_make: make, raw_model: model, raw_version: version})
  end

  defp maybe_record_unmatched(_params), do: :ok

  defp reset_otp_state(socket) do
    socket
    |> assign(:otp_requested_at, nil)
    |> assign(:otp_error, nil)
  end

  defp maybe_reset_otp_on_phone_change(socket, :contact, %{
         "phone" => phone
       }) do
    quote = socket.assigns.quote

    if raw_phone(quote) != phone do
      reset_otp_state(socket)
    else
      socket
    end
  end

  defp maybe_reset_otp_on_phone_change(socket, _step, _params), do: socket

  defp allow_uploads(socket) do
    allow_upload(socket, :releve_doc,
      accept: ~w(.jpg .jpeg .png .gif .pdf),
      max_entries: 1,
      max_file_size: 8_000_000
    )
  end

  defp maybe_allow_uploads(socket, :driver), do: allow_uploads(socket)
  defp maybe_allow_uploads(socket, _step), do: socket

  defp upload_error_message(:too_large), do: gettext("File is too large (max 8 MB)")
  defp upload_error_message(:disallowed_type), do: gettext("Only images and PDFs are accepted")
  defp upload_error_message(:unknown_type), do: gettext("Only images and PDFs are accepted")
  defp upload_error_message(_reason), do: gettext("Could not save file")

  defp complete_and_redirect(socket) do
    quote = socket.assigns.quote

    case Quoting.complete_quote(quote) do
      {:ok, %{quote: quote}} ->
        {:noreply, socket |> assign(:quote, quote) |> redirect(to: ~p"/offres/#{quote.token}")}

      {:error, :incomplete} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Please complete all steps before continuing."))
         |> assign(:changeset, nil)}

      {:error, changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, format_changeset_errors(changeset))
         |> assign(:changeset, nil)}
    end
  end

  # --- Step 1 anti-bot gate ---------------------------------------------------

  defp anti_bot_passes?(socket) do
    case AntiBot.verify(socket.assigns[:turnstile_token]) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  defp anti_bot_blocked(socket) do
    socket
    |> put_flash(:error, gettext("Please complete the security check to continue."))
    |> assign(:turnstile_token, nil)
  end

  defp turnstile_enabled?, do: Sahla.Settings.feature_enabled?(:turnstile)

  defp turnstile_site_key, do: AntiBot.site_key()

  defp can_continue?(:vehicle, quote, _changeset) do
    step = Quoting.validate_step(quote, :vehicle, Map.from_struct(quote) |> step_params())
    step.valid?
  end

  defp can_continue?(:driver, quote, _changeset) do
    step = Quoting.validate_step(quote, :driver, Map.from_struct(quote) |> step_params())
    step.valid?
  end

  defp can_continue?(:coverage, quote, _changeset) do
    step = Quoting.validate_step(quote, :coverage, Map.from_struct(quote) |> step_params())
    step.valid?
  end

  defp can_continue?(:contact, quote, _changeset) do
    phone_verified = not is_nil(quote.phone_verified_at)
    consents = Compliance.consents_for(quote)

    required_granted =
      [:cgu, :transmission]
      |> Enum.all?(fn kind ->
        Enum.any?(consents, fn c -> c.kind == kind and c.granted end)
      end)

    phone_verified and required_granted
  end

  defp step_params(map) do
    Map.take(map, [
      :plate,
      :is_new_ww,
      :make_id,
      :model_id,
      :version_id,
      :fiscal_power,
      :fuel,
      :first_registration,
      :vehicle_value_centimes,
      :usage,
      :city_id,
      :parking,
      :birth_date,
      :license_date,
      :is_public_servant,
      :current_insurer_id,
      :current_expiry,
      :at_fault_claims_36m,
      :crm,
      :formula,
      :options,
      :franchise_pref,
      :effect_date,
      :first_name,
      :last_name,
      :phone,
      :email
    ])
  end

  defp usage_options do
    [
      {gettext("Personal"), "personnel"},
      {gettext("Commute"), "trajet_domicile_travail"},
      {gettext("Professional"), "professionnel"},
      {gettext("Taxi / VTC"), "taxi_vtc"}
    ]
  end

  defp parking_options do
    [
      {gettext("Closed garage"), "garage"},
      {gettext("Guarded parking"), "parking_surveille"},
      {gettext("Street"), "rue"}
    ]
  end

  defp fuel_options do
    [
      {gettext("Petrol"), "essence"},
      {gettext("Diesel"), "diesel"},
      {gettext("Hybrid"), "hybride"},
      {gettext("Electric"), "electrique"}
    ]
  end

  defp guarantee_options do
    [
      {gettext("Bris de glace"), "bris_glace"},
      {gettext("Vol"), "vol"},
      {gettext("Incendie"), "incendie"},
      {gettext("PTA / Passagers"), "pta"},
      {gettext("Défense & recours"), "defense_recours"},
      {gettext("Assistance 0km"), "assistance"},
      {gettext("Individuelle conducteur"), "individuelle"},
      {gettext("Événements climatiques"), "evenements_climatiques"},
      {gettext("EVCAT (mandatory)"), "evcat"}
    ]
  end

  defp franchise_options do
    [
      {gettext("Low"), "basse"},
      {gettext("Standard"), "standard"},
      {gettext("High"), "elevee"}
    ]
  end

  defp client_ip(socket) do
    socket.private[:connect_info][:peer_data][:address]
    |> case do
      nil -> nil
      addr -> addr |> :inet.ntoa() |> to_string()
    end
  end

  defp otp_error_message(reason) do
    case reason do
      {:rate_limited, seconds} -> gettext("Too many attempts; wait %{s}s", s: seconds)
      :disabled -> gettext("SMS is currently disabled")
      :recipient_not_allowed -> gettext("Invalid Moroccan phone number")
      _ -> gettext("Could not send code")
    end
  end

  defp otp_verify_error_message(:invalid), do: gettext("Invalid code")
  defp otp_verify_error_message(:expired), do: gettext("Code expired")
  defp otp_verify_error_message(:locked), do: gettext("Too many failed attempts")
  defp otp_verify_error_message(:phone_mismatch), do: gettext("Phone changed after code was sent")
  defp otp_verify_error_message(_), do: gettext("Verification failed")

  defp format_changeset_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Regex.replace(~r/%\{(\w+)\}/, msg, fn _, key ->
        to_string(Keyword.get(opts, String.to_atom(key), "..."))
      end)
    end)
    |> Enum.map_join(", ", fn {_field, errors} -> Enum.join(errors, ", ") end)
  end
end
