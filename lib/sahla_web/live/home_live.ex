defmodule SahlaWeb.HomeLive do
  @moduledoc """
  Branded homepage and funnel front door (§6.2).

  The hero offers a fast plate-based quote start and a WW/new-vehicle fallback.
  Below the fold: insurer logo strip, proof cards, how-it-works, latest guides
  teaser, FAQ accordion, and the shared legal footer (`Layouts.footer/1`).
  """
  use SahlaWeb, :live_view

  alias Sahla.Content
  alias Sahla.Directory
  alias Sahla.Quoting

  @plate_pattern ~r/^[0-9]{1,5}\s*-?\s*[A-Za-z]{1,2}\s*-?\s*[0-9]{1,2}$/

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:plate, "")
     |> assign(:is_new_ww, false)
     |> assign(:plate_error, nil)
     |> assign(:insurers, Directory.list_active_insurers())
     |> assign(:guides, latest_guides(socket.assigns.locale))
     |> assign_page_meta()}
  end

  @impl true
  def handle_event("plate_change", %{"plate" => plate}, socket) do
    {:noreply, assign(socket, plate: normalize_plate(plate), plate_error: nil)}
  end

  def handle_event("toggle_ww", _params, socket) do
    {:noreply, update(socket, :is_new_ww, &not/1)}
  end

  def handle_event("start_quote", params, socket) do
    plate = Map.get(params, "plate", "")

    cond do
      socket.assigns.is_new_ww ->
        start_quote(socket, %{is_new_ww: true})

      String.trim(plate) == "" or plate =~ @plate_pattern ->
        start_quote(socket, %{plate: String.trim(plate)})

      true ->
        {:noreply,
         socket
         |> assign(:plate_error, gettext("Enter a valid Moroccan plate, e.g. 12345-A-67"))
         |> push_event("shake", %{})}
    end
  end

  defp start_quote(socket, vehicle_attrs) do
    attrs =
      Map.merge(
        %{
          locale: socket.assigns.locale,
          current_step: 1
        },
        vehicle_attrs
      )

    case Quoting.create_quote(attrs) do
      {:ok, quote} ->
        {:noreply,
         socket
         |> push_event("plausible-event", %{name: "funnel_start", props: %{source: "homepage"}})
         |> redirect(to: ~p"/devis/#{quote.token}")}

      {:error, _changeset} ->
        {:noreply,
         put_flash(socket, :error, gettext("Could not start a quote. Please try again."))}
    end
  end

  defp assign_page_meta(socket) do
    socket
    |> assign(:page_title, gettext("Compare car insurance in Morocco"))
    |> assign(
      :meta_description,
      gettext(
        "Compare RC, tiers étendu and tous risques car insurance offers from Moroccan insurers in 3 minutes."
      )
    )
    |> assign(:canonical_path, "/")
  end

  defp latest_guides(locale) do
    locale
    |> String.to_existing_atom()
    |> Content.list_published(kind: :guide)
    |> Enum.take(3)
  end

  defp normalize_plate(plate) when is_binary(plate) do
    plate
    |> String.upcase()
    |> String.replace(~r/\s+/, " ")
  end

  defp normalize_plate(_), do: ""

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-surface">
      <Layouts.topbar locale={@locale} dir={@dir} />

      <section class="relative overflow-hidden border-b border-ink/10 px-4 py-16 sm:px-6 lg:px-8">
        <svg class="absolute inset-0 -z-10 h-full w-full opacity-5" aria-hidden="true">
          <defs>
            <pattern id="zellige" x="0" y="0" width="80" height="80" patternUnits="userSpaceOnUse">
              <path
                d="M40 0 L80 20 L80 60 L40 80 L0 60 L0 20 Z"
                fill="none"
                stroke="currentColor"
                stroke-width="1"
              />
            </pattern>
          </defs>
          <rect width="100%" height="100%" fill="url(#zellige)" />
        </svg>

        <div class="relative mx-auto max-w-6xl">
          <div class="grid items-center gap-12 lg:grid-cols-2 lg:gap-8">
            <div class="space-y-6">
              <h1 class="text-4xl font-bold tracking-tight text-ink sm:text-5xl lg:text-6xl">
                {gettext("Find the right car insurance in 3 minutes")}
              </h1>
              <p class="text-lg text-ink/70">
                {gettext("Compare offers from %{count}+ Moroccan insurers. No phone call, no spam.",
                  count: length(@insurers)
                )}
              </p>

              <div class="rounded-card border border-ink/10 bg-surface p-6 shadow-soft">
                <form
                  phx-submit="start_quote"
                  phx-change="plate_change"
                  id="hero-form"
                  class="space-y-4"
                >
                  <div>
                    <label for="home-plate" class="block text-sm font-medium text-ink">
                      {gettext("Enter your plate number")}
                    </label>
                    <div class="mt-2 flex flex-col gap-3 sm:flex-row">
                      <input
                        id="home-plate"
                        type="text"
                        name="plate"
                        value={@plate}
                        placeholder="12345-A-67"
                        phx-debounce="300"
                        inputmode="text"
                        autocomplete="off"
                        class="input input-bordered w-full flex-1"
                        aria-invalid={@plate_error != nil}
                        aria-describedby={if @plate_error, do: "plate-error"}
                      />
                      <button type="submit" class="btn btn-primary">
                        {gettext("Compare now")}
                      </button>
                    </div>
                    <p :if={@plate_error} id="plate-error" class="mt-2 text-sm text-error">
                      {@plate_error}
                    </p>
                  </div>

                  <div class="flex items-center gap-3">
                    <button
                      type="button"
                      class={[
                        "relative inline-flex h-6 w-11 shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none focus-visible:ring-2 focus-visible:ring-primary",
                        @is_new_ww && "bg-primary",
                        !@is_new_ww && "bg-ink/20"
                      ]}
                      phx-click="toggle_ww"
                      role="switch"
                      aria-checked={to_string(@is_new_ww)}
                    >
                      <span class={[
                        "inline-block h-5 w-5 transform rounded-full bg-white shadow transition duration-200 ease-in-out",
                        @is_new_ww && "translate-x-5",
                        !@is_new_ww && "translate-x-0"
                      ]} />
                    </button>
                    <span class="text-sm text-ink/80">
                      {gettext("New vehicle / WW (no plate yet)")}
                    </span>
                  </div>
                </form>
              </div>
            </div>

            <div class="hidden lg:block">
              <div class="rounded-card border border-primary/10 bg-primary/5 p-8">
                <div class="grid grid-cols-2 gap-6">
                  <div class="space-y-2">
                    <p class="text-3xl font-bold text-primary">8</p>
                    <p class="text-sm text-ink/70">{gettext("Partner insurers")}</p>
                  </div>
                  <div class="space-y-2">
                    <p class="text-3xl font-bold text-primary">3 min</p>
                    <p class="text-sm text-ink/70">{gettext("Average quote time")}</p>
                  </div>
                  <div class="space-y-2">
                    <p class="text-3xl font-bold text-primary">100%</p>
                    <p class="text-sm text-ink/70">{gettext("Free \u0026 no-obligation")}</p>
                  </div>
                  <div class="space-y-2">
                    <p class="text-3xl font-bold text-primary">RCIMA</p>
                    <p class="text-sm text-ink/70">{gettext("Law 110-14 compliant")}</p>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      <section class="border-b border-ink/10 px-4 py-10 sm:px-6 lg:px-8">
        <div class="mx-auto max-w-6xl">
          <p class="text-center text-sm font-medium text-ink/60">
            {gettext("Compare offers from leading insurers")}
          </p>
          <div class="mt-6 flex flex-wrap items-center justify-center gap-8 opacity-70 grayscale transition-opacity hover:opacity-100">
            <div :for={insurer <- @insurers} class="flex items-center gap-2">
              <%= if insurer.logo_path do %>
                <img
                  src={~p"/images/#{insurer.logo_path}"}
                  alt={name_for(insurer, @locale)}
                  class="h-8 w-auto object-contain"
                  loading="lazy"
                />
              <% else %>
                <span class="text-sm font-semibold text-ink">{name_for(insurer, @locale)}</span>
              <% end %>
            </div>
          </div>
        </div>
      </section>

      <section class="px-4 py-16 sm:px-6 lg:px-8">
        <div class="mx-auto max-w-6xl">
          <h2 class="text-center text-2xl font-bold text-ink sm:text-3xl">
            {gettext("How it works")}
          </h2>
          <div class="mt-10 grid gap-8 sm:grid-cols-3">
            <%= for {icon, title, body} <- steps() do %>
              <div class="rounded-card border border-ink/10 bg-surface p-6 text-center">
                <.icon name={icon} class="mx-auto size-10 text-primary" />
                <h3 class="mt-4 font-semibold text-ink">{title}</h3>
                <p class="mt-2 text-sm text-ink/70">{body}</p>
              </div>
            <% end %>
          </div>
        </div>
      </section>

      <section :if={@guides != []} class="bg-surface px-4 py-16 sm:px-6 lg:px-8">
        <div class="mx-auto max-w-6xl">
          <div class="flex items-center justify-between">
            <h2 class="text-2xl font-bold text-ink">
              {gettext("Useful guides")}
            </h2>
            <.link href={~p"/guides"} class="btn btn-ghost btn-sm">
              {gettext("See all")}
            </.link>
          </div>
          <div class="mt-8 grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
            <div
              :for={guide <- @guides}
              class="rounded-card border border-ink/10 bg-surface p-5 transition hover:shadow-soft"
            >
              <.link href={~p"/guides/#{guide.slug}"} class="block">
                <h3 class="font-semibold text-ink">{title_for(guide, @locale)}</h3>
                <p class="mt-2 line-clamp-2 text-sm text-ink/70">
                  {excerpt_for(guide, @locale)}
                </p>
              </.link>
            </div>
          </div>
        </div>
      </section>

      <section class="px-4 py-16 sm:px-6 lg:px-8">
        <div class="mx-auto max-w-3xl">
          <h2 class="text-center text-2xl font-bold text-ink">
            {gettext("Frequently asked questions")}
          </h2>
          <div class="mt-10 space-y-4">
            <%= for {q, a} <- faq_items() do %>
              <details class="group rounded-card border border-ink/10 bg-surface">
                <summary class="flex cursor-pointer items-center justify-between p-4 font-medium text-ink">
                  {q}
                  <.icon
                    name="hero-chevron-down"
                    class="size-5 transition-transform group-open:rotate-180"
                  />
                </summary>
                <div class="border-t border-ink/10 px-4 py-4 text-sm text-ink/70">
                  {a}
                </div>
              </details>
            <% end %>
          </div>
        </div>
      </section>
      <Layouts.footer locale={@locale} dir={@dir} />
      <Layouts.flash_group flash={@flash} />
    </div>
    """
  end

  defp name_for(insurer, "ar"), do: insurer.name_ar || insurer.name_fr
  defp name_for(insurer, _locale), do: insurer.name_fr

  defp title_for(guide, "ar"), do: guide.title_ar || guide.title_fr
  defp title_for(guide, _locale), do: guide.title_fr

  defp excerpt_for(guide, "ar"), do: guide.excerpt_ar || guide.excerpt_fr
  defp excerpt_for(guide, _locale), do: guide.excerpt_fr

  defp steps do
    [
      {
        "hero-document-text",
        gettext("1. Describe your vehicle"),
        gettext("Plate, make/model or WW. We read the risk factors that matter.")
      },
      {
        "hero-adjustments-horizontal",
        gettext("2. Choose your cover"),
        gettext("RC, tiers étendu or tous risques — with the options you actually need.")
      },
      {
        "hero-banknotes",
        gettext("3. Compare offers"),
        gettext("See ranked offers, then request a callback or WhatsApp an advisor.")
      }
    ]
  end

  defp faq_items do
    [
      {
        gettext("Is the quote really free?"),
        gettext("Yes. Comparing offers is free and carries no obligation to buy.")
      },
      {
        gettext("How long does it take?"),
        gettext("Most users complete the funnel in under 3 minutes.")
      },
      {
        gettext("What documents do I need?"),
        gettext(
          "Just your vehicle details for the quote. A relevé d'information may help you get the best CRM discount."
        )
      },
      {
        gettext("Is my data protected?"),
        gettext("Phone and personal data are encrypted at rest under Law 09-08 / CNDP practices.")
      }
    ]
  end
end
