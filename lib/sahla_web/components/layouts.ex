defmodule SahlaWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use SahlaWeb, :html

  import SahlaWeb.SEO

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true
  attr :current_scope, :map, default: nil
  attr :locale, :string, default: "fr"
  attr :dir, :string, default: "ltr"
  slot :head
  slot :language_switcher
  attr :inner_content, :any, required: true

  def app(assigns) do
    ~H"""
    <.topbar locale={@locale} dir={@dir}>
      <:language_switcher>
        {render_slot(@language_switcher)}
      </:language_switcher>
    </.topbar>

    <main class="min-h-[60vh] px-4 py-8 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-6xl">
        {@inner_content}
      </div>
    </main>

    <.footer locale={@locale} dir={@dir} />

    <.flash_group flash={@flash} />
    """
  end

  attr :locale, :string, default: "fr"
  attr :dir, :string, default: "ltr"
  slot :brand
  slot :language_switcher

  def topbar(assigns) do
    ~H"""
    <header class="bg-surface shadow-soft">
      <nav
        class="mx-auto flex max-w-6xl items-center justify-between gap-4 px-4 py-4 sm:px-6 lg:px-8"
        aria-label={gettext("Main navigation")}
      >
        <div class="flex items-center gap-6">
          <a href={home_path(@locale)} class="flex items-center gap-2 text-ink">
            <.icon name="hero-shield-check" class="size-8 text-primary" />
            <span class="text-lg font-semibold">{Sahla.Settings.display_name()}</span>
          </a>

          <ul class="hidden items-center gap-1 md:flex">
            <li>
              <.link href={page_path(@locale, "/guides")} class="btn btn-ghost btn-sm">
                {gettext("Guides")}
              </.link>
            </li>
            <li>
              <.link href={page_path(@locale, "/assureurs")} class="btn btn-ghost btn-sm">
                {gettext("Insurers")}
              </.link>
            </li>
          </ul>
        </div>

        <div class="flex items-center gap-3">
          <div class="hidden sm:block">
            {render_slot(@language_switcher)}
          </div>

          <.link
            href={phone_uri()}
            class="btn btn-primary btn-sm hidden items-center gap-2 sm:inline-flex"
          >
            <.icon name="hero-phone" class="size-4" />
            {gettext("Call us")}
          </.link>

          <button
            type="button"
            class="btn btn-ghost btn-sm md:hidden"
            aria-label={gettext("Open menu")}
            aria-expanded="false"
            phx-click={JS.toggle(to: "#mobile-nav", in: "block", out: "hidden")}
          >
            <.icon name="hero-bars-3" class="size-6" />
          </button>
        </div>
      </nav>

      <div id="mobile-nav" class="hidden border-t border-ink/10 px-4 py-4 md:hidden">
        <ul class="space-y-2">
          <li>
            <.link
              href={page_path(@locale, "/guides")}
              class="btn btn-ghost btn-sm w-full justify-start"
            >
              {gettext("Guides")}
            </.link>
          </li>
          <li>
            <.link
              href={page_path(@locale, "/assureurs")}
              class="btn btn-ghost btn-sm w-full justify-start"
            >
              {gettext("Insurers")}
            </.link>
          </li>
          <li class="pt-2">
            {render_slot(@language_switcher)}
          </li>
          <li>
            <.link href={phone_uri()} class="btn btn-primary btn-sm w-full">
              <.icon name="hero-phone" class="me-2 size-4" />
              {gettext("Call us")}
            </.link>
          </li>
        </ul>
      </div>
    </header>
    """
  end

  attr :locale, :string, default: "fr"
  attr :dir, :string, default: "ltr"

  def footer(assigns) do
    ~H"""
    <footer class="bg-surface mt-auto border-t border-ink/10 px-4 py-12 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-6xl">
        <div class="grid gap-8 sm:grid-cols-2 lg:grid-cols-4">
          <div>
            <p class="font-semibold text-ink">{Sahla.Settings.display_name()}</p>
            <p class="mt-2 text-sm text-ink/70">
              {gettext("ACAPS-agrément courtier: %{number}", number: agrement_number())}
            </p>
          </div>

          <div>
            <p class="font-semibold text-ink">{gettext("Legal")}</p>
            <ul class="mt-2 space-y-2 text-sm">
              <li>
                <.link
                  href={page_path(@locale, "/mentions-legales")}
                  class="text-ink/70 hover:text-ink"
                >
                  {gettext("Legal notices")}
                </.link>
              </li>
              <li>
                <.link
                  href={page_path(@locale, "/politique-confidentialite")}
                  class="text-ink/70 hover:text-ink"
                >
                  {gettext("Privacy policy")}
                </.link>
              </li>
              <li>
                <.link href={page_path(@locale, "/cgu")} class="text-ink/70 hover:text-ink">
                  {gettext("Terms of use")}
                </.link>
              </li>
            </ul>
          </div>

          <div>
            <p class="font-semibold text-ink">{gettext("Service")}</p>
            <ul class="mt-2 space-y-2 text-sm">
              <li>
                <.link href={page_path(@locale, "/guides")} class="text-ink/70 hover:text-ink">
                  {gettext("Guides")}
                </.link>
              </li>
              <li>
                <.link href={page_path(@locale, "/assureurs")} class="text-ink/70 hover:text-ink">
                  {gettext("Insurers")}
                </.link>
              </li>
              <li>
                <.link href={page_path(@locale, "/contact")} class="text-ink/70 hover:text-ink">
                  {gettext("Contact")}
                </.link>
              </li>
            </ul>
          </div>

          <div>
            <p class="font-semibold text-ink">{gettext("Need help?")}</p>
            <.link
              href={phone_uri()}
              class="mt-2 inline-flex items-center gap-2 text-primary hover:underline"
            >
              <.icon name="hero-phone" class="size-4" />
              {phone_number()}
            </.link>
          </div>
        </div>

        <p class="mt-10 text-center text-xs text-ink/50">
          {gettext("© %{year} %{brand}. All rights reserved.",
            year: Date.utc_today().year,
            brand: Sahla.Settings.display_name()
          )}
        </p>
      </div>
    </footer>
    """
  end

  defp home_path("ar"), do: ~p"/ar"
  defp home_path(_locale), do: ~p"/"

  defp page_path("ar", path), do: "/ar" <> path
  defp page_path(_locale, path), do: path

  defp phone_number, do: Sahla.Settings.get("contact.phone", "+212 5XX-XXXXXX")
  defp phone_uri, do: "tel:" <> String.replace(phone_number(), ~r/\s|-/, "")

  defp agrement_number, do: Sahla.Settings.get("agrement_number", "--")

  @doc """
  Renders the Plausible analytics script in <head> when a domain is configured
  and analytics are enabled. Disabled in dev/test so local runs never phone
  home (§11, Appendix D).
  """
  attr :domain, :string, required: true

  def plausible_script(assigns) do
    if analytics_enabled?() and assigns.domain not in [nil, ""] do
      ~H"""
      <script
        defer
        data-domain={@domain}
        data-api={plausible_api()}
        src="https://plausible.io/js/script.manual.outbound-links.js"
      >
      </script>
      <script>
        window.plausible = window.plausible || function() { (window.plausible.q = window.plausible.q || []).push(arguments) };
      </script>
      """
    else
      ~H"""
      <!-- analytics off -->
      """
    end
  end

  defp analytics_enabled? do
    Application.get_env(:sahla, :analytics_enabled, true)
  end

  defp plausible_api do
    # Proxy API through a first-party subdomain avoids ad-blockers and keeps
    # data on the site's own origin. Falls back to Plausible's default API.
    Application.get_env(:sahla, :plausible_api_host, "https://plausible.io/api/event")
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  attr :breadcrumbs, :list, default: []

  def admin_breadcrumbs(assigns) do
    ~H"""
    <nav aria-label={gettext("Breadcrumb")}>
      <ol class="flex flex-wrap items-center gap-1 text-sm text-ink/60">
        <%= for {{label, path}, idx} <- Enum.with_index(@breadcrumbs) do %>
          <li class="flex items-center gap-1">
            <%= if idx > 0 do %>
              <.icon name="hero-chevron-right" class="size-4 shrink-0" />
            <% end %>
            <%= if idx == length(@breadcrumbs) - 1 and not is_nil(path) do %>
              <.link
                href={path}
                class="font-medium text-ink hover:underline"
                aria-current="page"
              >
                {label}
              </.link>
            <% else %>
              <%= if is_nil(path) do %>
                <span class="font-medium text-ink">{label}</span>
              <% else %>
                <.link href={path} class="hover:text-ink hover:underline">
                  {label}
                </.link>
              <% end %>
            <% end %>
          </li>
        <% end %>
      </ol>
    </nav>
    """
  end

  def admin_role_label(admin) do
    role = admin && admin.role

    if role do
      Gettext.gettext(Sahla.Gettext, "Admin role: %{role}", role: role)
    else
      Gettext.gettext(Sahla.Gettext, "No role")
    end
  end

  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
