defmodule SahlaWeb.GuidesLive do
  @moduledoc """
  Public guides hub: index of published guides and individual guide reader.

  - `:index` lists published `Content.Post` of kind `:guide`, newest first.
  - `:show` renders a single published guide by slug, with table of contents,
    related guides, and JSON-LD breadcrumbs.

  Missing or unpublished slugs raise a LiveView `:not_found` error so the
  branded 404 page is rendered with a 404 HTTP status.
  """
  use SahlaWeb, :live_view

  alias Sahla.Content
  alias SahlaWeb.SEO

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(params, uri, socket) do
    locale = String.to_existing_atom(socket.assigns.locale)
    path = URI.parse(uri).path || "/guides"

    socket =
      case socket.assigns.live_action do
        :index ->
          guides = Content.list_published(locale, kind: :guide)

          assign_index(socket, guides, path)

        :show ->
          slug = Map.fetch!(params, "slug")

          case Content.get_published_by_slug(slug, locale) do
            nil ->
              socket
              |> put_flash(:error, gettext("Guide not found"))
              |> redirect(to: ~p"/guides")

            guide ->
              related = related_guides(guide, locale)
              assign_show(socket, guide, related, path)
          end
      end

    {:noreply, socket}
  end

  defp assign_index(socket, guides, path) do
    socket
    |> assign(:page_title, gettext("Guides"))
    |> assign(:meta_description, default_meta_description(socket.assigns.locale))
    |> assign(:canonical_path, path)
    |> assign(:breadcrumb_schema, index_breadcrumb_schema(socket.assigns.locale))
    |> assign(:guides, guides)
    |> assign(:count, length(guides))
  end

  defp assign_show(socket, guide, related, path) do
    locale = socket.assigns.locale
    title = title_for(guide, locale)
    excerpt = excerpt_for(guide, locale)
    body_html = Content.render_html(body_for(guide, locale))
    toc = extract_toc(body_html)

    socket
    |> assign(:page_title, title)
    |> assign(:meta_description, excerpt)
    |> assign(:canonical_path, path)
    |> assign(:breadcrumb_schema, show_breadcrumb_schema(guide, locale))
    |> assign(:guide, guide)
    |> assign(:title, title)
    |> assign(:excerpt, excerpt)
    |> assign(:body_html, body_html)
    |> assign(:toc, toc)
    |> assign(:related, related)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-[60vh]">
      <%= if @live_action == :index do %>
        <.guides_index guides={@guides} count={@count} locale={@locale} />
      <% else %>
        <.guide_show
          guide={@guide}
          title={@title}
          excerpt={@excerpt}
          body_html={@body_html}
          toc={@toc}
          related={@related}
          locale={@locale}
        />
      <% end %>
    </div>
    """
  end

  attr :guides, :list, required: true
  attr :count, :integer, required: true
  attr :locale, :string, required: true

  defp guides_index(assigns) do
    ~H"""
    <section class="py-8">
      <header class="mb-8">
        <h1 class="text-3xl font-bold text-ink">{gettext("Guides")}</h1>
        <p class="mt-2 text-ink/70">
          {gettext("Practical guides to help you understand insurance in Morocco.")}
        </p>
      </header>

      <%= if @count > 0 do %>
        <ul id="guides-list" phx-update="stream" class="grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
          <%= for guide <- @guides do %>
            <li id={"guide-#{guide.id}"}>
              <.guide_card guide={guide} locale={@locale} />
            </li>
          <% end %>
        </ul>
      <% end %>

      <%= if @count == 0 do %>
        <section class="py-16 text-center">
          <p class="text-lg text-ink/70">
            {gettext("No guides published yet. Check back soon.")}
          </p>
        </section>
      <% end %>
    </section>
    """
  end

  attr :guide, :map, required: true
  attr :locale, :string, required: true

  defp guide_card(assigns) do
    assigns =
      assign(assigns,
        title: title_for(assigns.guide, assigns.locale),
        excerpt: excerpt_for(assigns.guide, assigns.locale),
        path: ~p"/guides/#{assigns.guide.slug}"
      )

    ~H"""
    <.card class="h-full">
      <.link navigate={@path} class="block">
        <h2 class="text-xl font-semibold text-ink hover:text-primary hover:underline">
          {@title}
        </h2>
      </.link>
      <p :if={@excerpt not in [nil, ""]} class="mt-3 text-ink/70 line-clamp-3">
        {@excerpt}
      </p>
      <div class="mt-4">
        <.link navigate={@path} class="text-primary hover:underline">
          {gettext("Read guide")} →
        </.link>
      </div>
    </.card>
    """
  end

  attr :guide, :map, required: true
  attr :title, :string, required: true
  attr :excerpt, :string, default: nil
  attr :body_html, :string, required: true
  attr :toc, :list, default: []
  attr :related, :list, default: []
  attr :locale, :string, required: true

  defp guide_show(assigns) do
    ~H"""
    <article class="py-8">
      <header class="mb-8">
        <.link navigate={~p"/guides"} class="text-sm text-ink/60 hover:text-ink hover:underline">
          {gettext("Guides")}
        </.link>
        <h1 class="mt-2 text-3xl font-bold text-ink">{@title}</h1>
        <p :if={@excerpt not in [nil, ""]} class="mt-4 text-lg text-ink/70">
          {@excerpt}
        </p>
      </header>

      <div class="grid gap-8 lg:grid-cols-[1fr_16rem]">
        <div>
          <%= if @toc != [] do %>
            <nav
              aria-label={gettext("Table of contents")}
              class="mb-8 rounded-card bg-surface p-4 shadow-soft lg:hidden"
            >
              <h2 class="font-semibold text-ink">{gettext("Table of contents")}</h2>
              <ul class="mt-2 space-y-1">
                <%= for %{id: id, text: text} <- @toc do %>
                  <li>
                    <a href={"#" <> id} class="text-sm text-primary hover:underline">
                      {text}
                    </a>
                  </li>
                <% end %>
              </ul>
            </nav>
          <% end %>

          <div class="prose prose-ink max-w-none">
            {Phoenix.HTML.raw(@body_html)}
          </div>
        </div>

        <aside class="hidden lg:block">
          <%= if @toc != [] do %>
            <div class="sticky top-4 rounded-card bg-surface p-4 shadow-soft">
              <h2 class="font-semibold text-ink">{gettext("Table of contents")}</h2>
              <ul class="mt-2 space-y-1">
                <%= for %{id: id, text: text} <- @toc do %>
                  <li>
                    <a href={"#" <> id} class="text-sm text-primary hover:underline">
                      {text}
                    </a>
                  </li>
                <% end %>
              </ul>
            </div>
          <% end %>
        </aside>
      </div>

      <%= if @related != [] do %>
        <section class="mt-12 border-t border-ink/10 pt-8">
          <h2 class="text-xl font-semibold text-ink">
            {gettext("Related guides")}
          </h2>
          <ul class="mt-4 grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
            <%= for guide <- @related do %>
              <li>
                <.guide_card guide={guide} locale={@locale} />
              </li>
            <% end %>
          </ul>
        </section>
      <% end %>
    </article>
    """
  end

  defp title_for(guide, "ar"), do: guide.title_ar || guide.title_fr
  defp title_for(guide, _locale), do: guide.title_fr

  defp excerpt_for(guide, "ar"), do: guide.excerpt_ar || guide.excerpt_fr
  defp excerpt_for(guide, _locale), do: guide.excerpt_fr

  defp body_for(guide, "ar"), do: guide.body_ar || guide.body_fr
  defp body_for(guide, _locale), do: guide.body_fr

  defp default_meta_description("ar") do
    gettext("Practical guides to help you understand insurance in Morocco.")
  end

  defp default_meta_description(_locale) do
    gettext("Practical guides to help you understand insurance in Morocco.")
  end

  defp related_guides(current_guide, locale) do
    Content.list_published(locale, kind: :guide)
    |> Enum.reject(&(&1.id == current_guide.id))
    |> Enum.take(3)
  end

  defp extract_toc(html) when is_binary(html) do
    # Regex extraction avoids adding a dependency. The HTML is already sanitized
    # by `Content.render_html/1`, so event-handler attributes are stripped.
    ~r/<h2[^>]*>(?:<a[^>]*>)?([^<]*)(?:<\/a>)?<\/h2>/
    |> Regex.scan(html)
    |> Enum.map(fn [full, text] ->
      id = slugify(text)
      %{id: id, text: String.trim(text), html: replace_h2_id(full, id)}
    end)
  end

  defp replace_h2_id(h2_html, id) do
    String.replace(h2_html, ~r/<h2/, "<h2 id=\"#{id}\"")
  end

  defp slugify(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^\w\s-]+/u, "")
    |> String.replace(~r/[\s_]+/, "-")
    |> String.trim("-")
  end

  defp index_breadcrumb_schema(locale) do
    SEO.breadcrumb_schema([{gettext("Home"), home_path(locale)}, {gettext("Guides"), "/guides"}])
  end

  defp show_breadcrumb_schema(guide, locale) do
    SEO.breadcrumb_schema([
      {gettext("Home"), home_path(locale)},
      {gettext("Guides"), "/guides"},
      {title_for(guide, locale), nil}
    ])
  end

  defp home_path("ar"), do: "/ar"
  defp home_path(_locale), do: "/"
end
