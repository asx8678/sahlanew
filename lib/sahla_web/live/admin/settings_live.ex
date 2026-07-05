defmodule SahlaWeb.Admin.SettingsLive do
  @moduledoc """
  Grouped admin settings editor at `/admin/settings`.

  The page is role-gated through `Sahla.Accounts.Policy` and
  `SahlaWeb.AdminAuthz`: `ops` can edit working hours, contact
  numbers and disclaimers; `superadmin` can additionally edit
  feature flags and data-retention windows.

  Every feature-flag toggle is persisted with an audit entry so
  configuration changes are traceable. Invalid values are rejected
  with inline errors and no DB write.
  """
  use SahlaWeb, :live_view

  on_mount {SahlaWeb.AdminAuthz, :settings}

  alias Sahla.Audit
  alias Sahla.Settings

  @page_title gettext("Settings")

  # Form key groupings -------------------------------------------------------

  @working_hours ["working_hours_start", "working_hours_end", "callback_slot_minutes"]
  @contacts ["contact.phone", "contact.whatsapp"]
  @feature_flags [
    "feature.sms",
    "feature.whatsapp",
    "feature.payments",
    "feature.ip_allowlist"
  ]
  @display ["display.vat_inclusive"]
  @disclaimers ["disclaimer_fr", "disclaimer_ar"]
  @retention [
    "retention.drafts_days",
    "retention.anonymize_months",
    "retention.otp_hours",
    "retention.payload_trim_months",
    "retention.audit_years"
  ]

  @all_groups @working_hours ++
                @contacts ++ @feature_flags ++ @display ++ @disclaimers ++ @retention

  @impl true
  def mount(_params, _session, socket) do
    role = socket.assigns.current_admin.role

    socket =
      socket
      |> assign(:page_title, @page_title)
      |> assign(:breadcrumbs, [{@page_title, nil}])
      |> assign(:superadmin?, role == :superadmin)
      |> assign(:editable_keys, editable_keys(role))
      |> assign(:feature_flags, @feature_flags)
      |> assign(:errors, %{})
      |> assign(:admin_ip, socket_ip(socket))
      |> load_settings()

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("save_section", params, socket) do
    {group, values} = extract_group(params)

    if can_edit_group?(socket.assigns.current_admin.role, group) do
      case validate_and_write(socket, group, values) do
        {:ok, socket} ->
          {:noreply, put_flash(socket, :info, gettext("Settings saved"))}

        {:error, socket} ->
          {:noreply, socket}
      end
    else
      {:noreply,
       socket
       |> put_flash(:error, gettext("You are not authorized to edit these settings"))
       |> push_navigate(to: ~p"/admin")}
    end
  end

  defp extract_group(params) do
    cond do
      Map.has_key?(params, "working_hours") -> {:working_hours, params["working_hours"]}
      Map.has_key?(params, "contact") -> {:contact, params["contact"]}
      Map.has_key?(params, "feature") -> {:feature, params["feature"]}
      Map.has_key?(params, "display") -> {:display, params["display"]}
      Map.has_key?(params, "disclaimer") -> {:disclaimer, params["disclaimer"]}
      Map.has_key?(params, "retention") -> {:retention, params["retention"]}
      true -> {:unknown, %{}}
    end
  end

  defp can_edit_group?(:superadmin, _group), do: true
  defp can_edit_group?(:ops, :working_hours), do: true
  defp can_edit_group?(:ops, :contact), do: true
  defp can_edit_group?(:ops, :display), do: true
  defp can_edit_group?(:ops, :disclaimer), do: true
  defp can_edit_group?(_role, _group), do: false

  defp validate_and_write(socket, :working_hours, values) do
    with {:ok, start_time} <- parse_time(values["working_hours_start"]),
         {:ok, end_time} <- parse_time(values["working_hours_end"]),
         {:ok, slot} <- parse_positive_integer(values["callback_slot_minutes"], 60),
         :ok <- validate_slot_within_hours(start_time, end_time, slot) do
      socket
      |> write("working_hours_start", format_time(start_time))
      |> write("working_hours_end", format_time(end_time))
      |> write("callback_slot_minutes", slot)
      |> ok()
    else
      {:error, field, msg} -> error(socket, field, msg)
    end
  end

  defp validate_and_write(socket, :contact, values) do
    phone = String.trim(values["contact.phone"] || "")
    whatsapp = String.trim(values["contact.whatsapp"] || "")

    with :ok <- validate_moroccan_phone(phone, "contact.phone"),
         :ok <- validate_moroccan_phone(whatsapp, "contact.whatsapp") do
      socket
      |> write("contact.phone", phone)
      |> write("contact.whatsapp", whatsapp)
      |> ok()
    else
      {:error, field, msg} -> error(socket, field, msg)
    end
  end

  defp validate_and_write(socket, :feature, values) do
    socket.assigns.current_admin.role == :superadmin or unauthorized(socket)

    socket
    |> write_flag("feature.sms", values["feature.sms"])
    |> write_flag("feature.whatsapp", values["feature.whatsapp"])
    |> write_flag("feature.payments", values["feature.payments"])
    |> write_flag("feature.ip_allowlist", values["feature.ip_allowlist"])
    |> ok()
  end

  defp validate_and_write(socket, :display, values) do
    socket
    |> write("display.vat_inclusive", truthy?(values["display.vat_inclusive"]))
    |> ok()
  end

  defp validate_and_write(socket, :disclaimer, values) do
    socket
    |> write("disclaimer_fr", values["disclaimer_fr"] || "")
    |> write("disclaimer_ar", values["disclaimer_ar"] || "")
    |> ok()
  end

  defp validate_and_write(socket, :retention, values) do
    socket.assigns.current_admin.role == :superadmin or unauthorized(socket)

    with {:ok, drafts} <- parse_positive_integer(values["retention.drafts_days"], 30),
         {:ok, anonymize} <- parse_positive_integer(values["retention.anonymize_months"], 24),
         {:ok, otp} <- parse_positive_integer(values["retention.otp_hours"], 1),
         {:ok, payload} <- parse_positive_integer(values["retention.payload_trim_months"], 3),
         {:ok, audit} <- parse_positive_integer(values["retention.audit_years"], 5) do
      socket
      |> write("retention.drafts_days", drafts)
      |> write("retention.anonymize_months", anonymize)
      |> write("retention.otp_hours", otp)
      |> write("retention.payload_trim_months", payload)
      |> write("retention.audit_years", audit)
      |> ok()
    else
      {:error, field, msg} -> error(socket, field, msg)
    end
  end

  defp validate_and_write(socket, _, _) do
    error(socket, :base, gettext("Unknown settings group"))
  end

  # Validators ---------------------------------------------------------------

  defp parse_time(<<h1, h2, ?:, m1, m2>> = value)
       when h1 in ?0..?2 and h2 in ?0..?9 and m1 in ?0..?5 and m2 in ?0..?9 do
    case Time.from_iso8601(value <> ":00") do
      {:ok, time} -> {:ok, time}
      _ -> {:error, :working_hours_start, gettext("Invalid time format")}
    end
  end

  defp parse_time(_), do: {:error, :working_hours_start, gettext("Use HH:MM format")}

  defp parse_positive_integer(value, _default) when is_integer(value) and value > 0,
    do: {:ok, value}

  defp parse_positive_integer(value, _default) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {n, ""} when n > 0 -> {:ok, n}
      {_n, ""} -> {:error, :base, gettext("Value must be positive")}
      _ -> {:error, :base, gettext("Enter a whole number")}
    end
  end

  defp parse_positive_integer(value, default) when value in [nil, ""], do: {:ok, default}
  defp parse_positive_integer(_, _), do: {:error, :base, gettext("Enter a whole number")}

  defp validate_slot_within_hours(start_time, end_time, _slot) do
    case Time.compare(start_time, end_time) do
      :lt -> :ok
      _ -> {:error, :working_hours_end, gettext("Closing time must be after opening time")}
    end
  end

  defp validate_moroccan_phone("", field),
    do: {:error, field, gettext("Phone number is required")}

  defp validate_moroccan_phone(value, field) do
    digits = String.replace(value, ~r/\s+/, "")

    if Regex.match?(~r/^(\+212|0)\d{9}$/, digits) do
      :ok
    else
      {:error, field, gettext("Enter a valid Moroccan phone number")}
    end
  end

  # Writers ------------------------------------------------------------------

  defp write(socket, key, value) do
    case Settings.put(key, value) do
      {:ok, _} -> socket
      {:error, _changeset} -> put_error(socket, key, gettext("Could not save setting"))
    end
  end

  defp write_flag(socket, key, value) do
    enabled? = truthy?(value)

    case Settings.put_feature(String.replace_prefix(key, "feature.", ""), enabled?) do
      {:ok, _} ->
        admin = socket.assigns.current_admin
        ip = socket.assigns.admin_ip

        {:ok, _} =
          Audit.log(%{
            admin_id: admin.id,
            action: "settings.update",
            entity: "setting",
            entity_id: key,
            after: %{"value" => enabled?},
            ip: ip
          })

        socket

      {:error, _changeset} ->
        put_error(socket, key, gettext("Could not save feature flag"))
    end
  end

  defp truthy?("true"), do: true
  defp truthy?("false"), do: false
  defp truthy?(true), do: true
  defp truthy?(false), do: false
  defp truthy?(nil), do: false
  defp truthy?(_), do: false

  defp error(socket, field, message) do
    {:error, put_error(socket, to_string(field), message)}
  end

  defp ok(socket), do: {:ok, socket}

  defp put_error(socket, field, message) do
    errors = Map.put(socket.assigns.errors, to_string(field), message)
    assign(socket, :errors, errors)
  end

  defp unauthorized(socket) do
    throw({:unauthorized, socket})
  end

  # Rendering ----------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-5xl space-y-6">
      <.header>
        {@page_title}
        <:subtitle>{gettext("Manage working hours, numbers, feature flags and retention")}</:subtitle>
      </.header>

      <.settings_section
        title={gettext("Working hours")}
        subtitle={gettext("Callback slots must fall within working hours")}
      >
        <.form
          for={%{}}
          phx-submit="save_section"
          class="grid gap-4 sm:grid-cols-3"
          id="working-hours-form"
        >
          <.input
            name="working_hours[working_hours_start]"
            type="time"
            label={gettext("Opening time")}
            value={@settings["working_hours_start"]}
            error_class="input-error"
            disabled={not can_edit?(:working_hours_start, @editable_keys)}
          />
          <.field_error :if={@errors["working_hours_start"]}>
            {@errors["working_hours_start"]}
          </.field_error>

          <.input
            name="working_hours[working_hours_end]"
            type="time"
            label={gettext("Closing time")}
            value={@settings["working_hours_end"]}
            error_class="input-error"
            disabled={not can_edit?(:working_hours_end, @editable_keys)}
          />
          <.field_error :if={@errors["working_hours_end"]}>
            {@errors["working_hours_end"]}
          </.field_error>

          <.input
            name="working_hours[callback_slot_minutes]"
            type="number"
            label={gettext("Callback slot minutes")}
            value={@settings["callback_slot_minutes"]}
            min="1"
            error_class="input-error"
            disabled={not can_edit?(:callback_slot_minutes, @editable_keys)}
          />
          <.field_error :if={@errors["callback_slot_minutes"]}>
            {@errors["callback_slot_minutes"]}
          </.field_error>
          <.field_error :if={@errors["base"]}>{@errors["base"]}</.field_error>

          <div class="sm:col-span-3">
            <.button
              type="submit"
              variant="primary"
              disabled={not can_edit?(:working_hours_start, @editable_keys)}
            >
              {gettext("Save working hours")}
            </.button>
          </div>
        </.form>
      </.settings_section>

      <.settings_section
        title={gettext("Contact numbers")}
        subtitle={gettext("Phone and WhatsApp numbers visible to customers")}
      >
        <.form
          for={%{}}
          phx-submit="save_section"
          class="grid gap-4 sm:grid-cols-2"
          id="contact-form"
        >
          <.input
            name="contact[contact.phone]"
            type="tel"
            label={gettext("Phone number")}
            value={@settings["contact.phone"]}
            placeholder="+212 5XX-XXXXXX"
            error_class="input-error"
            disabled={not can_edit?("contact.phone", @editable_keys)}
          />
          <.field_error :if={@errors["contact.phone"]}>{@errors["contact.phone"]}</.field_error>

          <.input
            name="contact[contact.whatsapp]"
            type="tel"
            label={gettext("WhatsApp number")}
            value={@settings["contact.whatsapp"]}
            placeholder="+212 6XX-XXXXXX"
            error_class="input-error"
            disabled={not can_edit?("contact.whatsapp", @editable_keys)}
          />
          <.field_error :if={@errors["contact.whatsapp"]}>{@errors["contact.whatsapp"]}</.field_error>
          <.field_error :if={@errors["base"]}>{@errors["base"]}</.field_error>

          <div class="sm:col-span-2">
            <.button
              type="submit"
              variant="primary"
              disabled={not can_edit?("contact.phone", @editable_keys)}
            >
              {gettext("Save contact numbers")}
            </.button>
          </div>
        </.form>
      </.settings_section>

      <.settings_section
        title={gettext("Feature flags")}
        subtitle={gettext("Only superadmins can change feature flags")}
      >
        <.form for={%{}} phx-submit="save_section" class="space-y-3" id="feature-form">
          <div class="grid gap-4 sm:grid-cols-2">
            <.feature_toggle
              :for={flag <- @feature_flags}
              name={flag}
              label={feature_label(flag)}
              value={@settings[flag]}
              error={@errors[flag]}
              disabled={not can_edit?(flag, @editable_keys)}
            />
          </div>
          <.button type="submit" variant="primary" disabled={not @superadmin?}>
            {gettext("Save feature flags")}
          </.button>
        </.form>
      </.settings_section>

      <.settings_section
        title={gettext("Display")}
        subtitle={gettext("Tax and fee display preferences")}
      >
        <.form for={%{}} phx-submit="save_section" class="space-y-3" id="display-form">
          <.feature_toggle
            name="display.vat_inclusive"
            label={gettext("Prices include VAT")}
            value={@settings["display.vat_inclusive"]}
            error={@errors["display.vat_inclusive"]}
            disabled={not can_edit?("display.vat_inclusive", @editable_keys)}
          />
          <.button
            type="submit"
            variant="primary"
            disabled={not can_edit?("display.vat_inclusive", @editable_keys)}
          >
            {gettext("Save display settings")}
          </.button>
        </.form>
      </.settings_section>

      <.settings_section
        title={gettext("Disclaimers")}
        subtitle={gettext("French and Arabic disclaimer texts shown to customers")}
      >
        <.form for={%{}} phx-submit="save_section" class="space-y-4" id="disclaimer-form">
          <.input
            name="disclaimer[disclaimer_fr]"
            type="textarea"
            label={gettext("French disclaimer")}
            value={@settings["disclaimer_fr"]}
            rows="3"
            error_class="textarea-error"
            disabled={not can_edit?("disclaimer_fr", @editable_keys)}
          />
          <.field_error :if={@errors["disclaimer_fr"]}>{@errors["disclaimer_fr"]}</.field_error>

          <.input
            name="disclaimer[disclaimer_ar]"
            type="textarea"
            label={gettext("Arabic disclaimer")}
            value={@settings["disclaimer_ar"]}
            rows="3"
            dir="rtl"
            error_class="textarea-error"
            disabled={not can_edit?("disclaimer_ar", @editable_keys)}
          />
          <.field_error :if={@errors["disclaimer_ar"]}>{@errors["disclaimer_ar"]}</.field_error>
          <.field_error :if={@errors["base"]}>{@errors["base"]}</.field_error>

          <.button
            type="submit"
            variant="primary"
            disabled={not can_edit?("disclaimer_fr", @editable_keys)}
          >
            {gettext("Save disclaimers")}
          </.button>
        </.form>
      </.settings_section>

      <.settings_section
        title={gettext("Data retention")}
        subtitle={gettext("Only superadmins can change retention windows")}
      >
        <.form
          for={%{}}
          phx-submit="save_section"
          class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3"
          id="retention-form"
        >
          <.input
            name="retention[retention.drafts_days]"
            type="number"
            label={gettext("Draft quote retention (days)")}
            value={@settings["retention.drafts_days"]}
            min="1"
            error_class="input-error"
            disabled={not can_edit?("retention.drafts_days", @editable_keys)}
          />
          <.input
            name="retention[retention.anonymize_months]"
            type="number"
            label={gettext("Anonymization (months)")}
            value={@settings["retention.anonymize_months"]}
            min="1"
            error_class="input-error"
            disabled={not can_edit?("retention.anonymize_months", @editable_keys)}
          />
          <.input
            name="retention[retention.otp_hours]"
            type="number"
            label={gettext("OTP retention (hours)")}
            value={@settings["retention.otp_hours"]}
            min="1"
            error_class="input-error"
            disabled={not can_edit?("retention.otp_hours", @editable_keys)}
          />
          <.input
            name="retention[retention.payload_trim_months]"
            type="number"
            label={gettext("Payload trim (months)")}
            value={@settings["retention.payload_trim_months"]}
            min="1"
            error_class="input-error"
            disabled={not can_edit?("retention.payload_trim_months", @editable_keys)}
          />
          <.input
            name="retention[retention.audit_years]"
            type="number"
            label={gettext("Audit retention (years)")}
            value={@settings["retention.audit_years"]}
            min="1"
            error_class="input-error"
            disabled={not can_edit?("retention.audit_years", @editable_keys)}
          />

          <div class="sm:col-span-2 lg:col-span-3">
            <.field_error :if={@errors["base"]}>{@errors["base"]}</.field_error>
            <.button type="submit" variant="primary" disabled={not @superadmin?}>
              {gettext("Save retention settings")}
            </.button>
          </div>
        </.form>
      </.settings_section>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  slot :inner_block, required: true

  defp settings_section(assigns) do
    ~H"""
    <.card>
      <h2 class="mb-1 text-lg font-semibold text-ink">{@title}</h2>
      <p :if={@subtitle} class="mb-4 text-sm text-ink/60">{@subtitle}</p>
      {render_slot(@inner_block)}
    </.card>
    """
  end

  attr :name, :string, required: true
  attr :label, :string, required: true
  attr :value, :any, default: false
  attr :error, :any, default: nil
  attr :disabled, :boolean, default: false

  defp feature_toggle(assigns) do
    assigns = assign(assigns, :checked, truthy?(assigns.value))

    ~H"""
    <div class="flex items-center justify-between rounded-card border border-ink/10 bg-bg p-4">
      <span class="text-sm font-medium text-ink">{@label}</span>
      <label class="inline-flex cursor-pointer items-center gap-3">
        <input type="hidden" name={"feature[#{@name}]"} value="false" />
        <input
          type="checkbox"
          name={"feature[#{@name}]"}
          value="true"
          checked={@checked}
          disabled={@disabled}
          class="toggle toggle-primary"
        />
      </label>
    </div>
    <.field_error :if={@error}>{@error}</.field_error>
    """
  end

  slot :inner_block, required: true

  defp field_error(assigns) do
    ~H"""
    <p class="mt-1 flex items-center gap-2 text-sm text-error">
      <.icon name="hero-exclamation-circle" class="size-4 shrink-0" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  # Helpers ------------------------------------------------------------------

  defp load_settings(socket) do
    settings =
      Map.new(@all_groups, fn key ->
        {key, Settings.get(key, default_for(key))}
      end)

    assign(socket, :settings, settings)
  end

  defp default_for("working_hours_start"), do: "09:00"
  defp default_for("working_hours_end"), do: "18:00"
  defp default_for("callback_slot_minutes"), do: 30
  defp default_for("contact.phone"), do: ""
  defp default_for("contact.whatsapp"), do: ""
  defp default_for("disclaimer_fr"), do: ""
  defp default_for("disclaimer_ar"), do: ""
  defp default_for("retention." <> _), do: nil
  defp default_for(_), do: false

  defp editable_keys(:superadmin), do: MapSet.new(@all_groups)

  defp editable_keys(:ops),
    do: MapSet.new(@working_hours ++ @contacts ++ @display ++ @disclaimers)

  defp editable_keys(_), do: MapSet.new()

  defp can_edit?(key, editable_keys) do
    to_string(key) in editable_keys
  end

  defp feature_label("feature.sms"), do: gettext("SMS integration")
  defp feature_label("feature.whatsapp"), do: gettext("WhatsApp integration")
  defp feature_label("feature.payments"), do: gettext("Payments")
  defp feature_label("feature.ip_allowlist"), do: gettext("Admin IP allowlist")

  defp format_time(%Time{} = time), do: Time.to_string(time) |> String.slice(0, 5)

  defp socket_ip(socket) do
    case Phoenix.LiveView.get_connect_info(socket, :peer_data) do
      %{address: address} ->
        address |> :inet.ntoa() |> to_string()

      _ ->
        nil
    end
  rescue
    _ -> nil
  end
end
