defmodule SahlaWeb.InsurersLive do
  @moduledoc """
  Public insurers directory (§5.4, §3.3).

  - `:index` lists active insurers, ordered by curated position.
  - `:show` renders one insurer's profile: logo, rating, ACAPS ref, the
    guarantees matrix across its active products, Conditions Générales PDF
    download links, related published guides, and a CTA into the quote funnel.

  An inactive or missing slug redirects to the index with a flash — the
  established convention for public resource pages (matching `GuidesLive`),
  which keeps the profile for private or absent insurers from ever rendering.
  """

  use SahlaWeb, :live_view

  alias Sahla.Content
  alias Sahla.Directory
  alias Sahla.Format
  alias SahlaWeb.SEO

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(params, uri, socket) do
    locale = socket.assigns.locale
    path = URI.parse(uri).path || "/assureurs"

    socket =
      case socket.assigns.live_action do
        :index ->
          insurers = Directory.list_active_insurers()
          assign_index(socket, insurers, path, locale)

        :show ->
          slug = Map.fetch!(params, "slug")

          case Directory.get_active_insurer_by_slug(slug) do
            nil ->
              socket
              |> put_flash(:error, gettext("Insurer not found"))
              |> redirect(to: index_path(locale))

            insurer ->
              products = Directory.list_public_products_for_insurer(insurer.id)
              guarantees = Directory.list_guarantees()
              related = related_guides(locale)
              assign_show(socket, insurer, products, guarantees, related, path, locale)
          end
      end

    {:noreply, socket}
  end

  defp assign_index(socket, insurers, path, locale) do
    socket
    |> assign(:page_title, gettext("Insurers"))
    |> assign(:meta_description, gettext("Compare car insurance offers from Moroccan insurers."))
    |> assign(:canonical_path, path)
    |> assign(:breadcrumb_schema, index_breadcrumb_schema(locale))
    |> assign(:insurers, insurers)
  end

  defp assign_show(socket, insurer, products, guarantees, related, path, locale) do
    name = name_for(insurer, locale)

    socket
    |> assign(:page_title, name)
    |> assign(
      :meta_description,
      gettext("Car insurance offers from %{insurer}: guarantees, conditions and ratings.",
        insurer: name
      )
    )
    |> assign(:canonical_path, path)
    |> assign(:breadcrumb_schema, show_breadcrumb_schema(insurer, locale))
    |> assign(:insurer, insurer)
    |> assign(:products, products)
    |> assign(:guarantees, guarantees)
    |> assign(:related, related)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-surface">
      <Layouts.topbar locale={@locale} dir={@dir} />

      <%= if @live_action == :index do %>
        <.index insurers={@insurers} locale={@locale} />
      <% else %>
        <.profile
          insurer={@insurer}
          products={@products}
          guarantees={@guarantees}
          related={@related}
          locale={@locale}
        />
      <% end %>

      <Layouts.footer locale={@locale} dir={@dir} />
      <Layouts.flash_group flash={@flash} />
    </div>
    """
  end

  attr :insurers, :list, required: true
  attr :locale, :string, required: true

  defp index(assigns) do
    ~H"""
    <section class="px-4 py-10 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-6xl">
        <header class="mb-8">
          <h1 class="text-3xl font-bold text-ink">{gettext("Insurers")}</h1>
          <p class="mt-2 text-ink/70">
            {gettext("Compare car insurance offers from leading Moroccan insurers.")}
          </p>
        </header>

        <%= if @insurers == [] do %>
          <p class="py-16 text-center text-lg text-ink/70">
            {gettext("No insurers available yet. Check back soon.")}
          </p>
        <% else %>
          <ul class="grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
            <li :for={insurer <- @insurers}>
              <.insurer_card insurer={insurer} locale={@locale} />
            </li>
          </ul>
        <% end %>
      </div>
    </section>
    """
  end

  attr :insurer, :map, required: true
  attr :locale, :string, required: true

  defp insurer_card(assigns) do
    assigns =
      assign(assigns,
        name: name_for(assigns.insurer, assigns.locale),
        path: ~p"/assureurs/#{assigns.insurer.slug}"
      )

    ~H"""
    <.card class="h-full">
      <.link navigate={@path} class="block">
        <div class="flex items-center gap-4">
          <%= if @insurer.logo_path do %>
            <img
              src={~p"/images/#{@insurer.logo_path}"}
              alt={@name}
              class="h-10 w-auto object-contain"
              loading="lazy"
            />
          <% else %>
            <span class="text-lg font-semibold text-ink">{@name}</span>
          <% end %>
        </div>
      </.link>

      <div class="mt-4 flex items-center gap-3">
        <.rating_badge rating={@insurer.rating} />
        <span :if={@insurer.acaps_ref} class="text-xs text-ink/60">
          {gettext("ACAPS %{ref}", ref: @insurer.acaps_ref)}
        </span>
      </div>

      <div class="mt-4">
        <.link navigate={@path} class="text-primary hover:underline">
          {gettext("View profile")} →
        </.link>
      </div>
    </.card>
    """
  end

  attr :insurer, :map, required: true
  attr :products, :list, required: true
  attr :guarantees, :list, required: true
  attr :related, :list, default: []
  attr :locale, :string, required: true

  defp profile(assigns) do
    assigns =
      assign(assigns,
        name: name_for(assigns.insurer, assigns.locale),
        matrix: build_matrix(assigns.products, assigns.guarantees),
        product_label: &product_label(&1, assigns.locale)
      )

    ~H"""
    <article class="px-4 py-10 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-6xl">
        <header class="mb-8">
          <.link
            navigate={index_path(@locale)}
            class="text-sm text-ink/60 hover:text-ink hover:underline"
          >
            {gettext("Insurers")}
          </.link>
          <h1 class="mt-2 text-3xl font-bold text-ink">{@name}</h1>

          <div class="mt-4 flex flex-wrap items-center gap-4">
            <.rating_badge rating={@insurer.rating} />
            <span :if={@insurer.acaps_ref} class="text-sm text-ink/70">
              {gettext("ACAPS agreement: %{ref}", ref: @insurer.acaps_ref)}
            </span>
            <a
              :if={@insurer.phone}
              href={"tel:#{@insurer.phone}"}
              class="inline-flex items-center gap-1 text-sm text-primary hover:underline"
            >
              <.icon name="hero-phone" class="size-4" />
              {@insurer.phone}
            </a>
          </div>
        </header>

        <%= if @products == [] do %>
          <p class="py-8 text-ink/70">
            {gettext("No active products listed for this insurer yet.")}
          </p>
        <% else %>
          <.matrix_table
            products={@products}
            guarantees={@guarantees}
            matrix={@matrix}
            locale={@locale}
          />
        <% end %>
      </div>
    </article>

    <section :if={@related != []} class="px-4 py-10 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-6xl">
        <h2 class="text-xl font-semibold text-ink">{gettext("Related guides")}</h2>
        <ul class="mt-4 grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
          <li :for={guide <- @related}>
            <.related_guide guide={guide} locale={@locale} />
          </li>
        </ul>
      </div>
    </section>

    <section class="px-4 py-10 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-6xl">
        <div class="rounded-card border border-ink/10 bg-surface p-6 text-center shadow-soft">
          <h2 class="text-xl font-semibold text-ink">
            {gettext("Compare %{insurer} with other insurers", insurer: @name)}
          </h2>
          <p class="mt-2 text-sm text-ink/70">
            {gettext("Get ranked quotes in 3 minutes — free and no obligation.")}
          </p>
          <.link navigate={~p"/devis/new"} class="btn btn-primary mt-4">
            {gettext("Start a quote")}
          </.link>
        </div>
      </div>
    </section>
    """
  end

  attr :products, :list, required: true
  attr :guarantees, :list, required: true
  attr :matrix, :map, required: true
  attr :locale, :string, required: true

  defp matrix_table(assigns) do
    ~H"""
    <div class="overflow-x-auto rounded-card border border-ink/10 shadow-soft">
      <table class="w-full text-sm">
        <caption class="sr-only">{gettext("Guarantees matrix by product")}</caption>
        <thead class="bg-ink/5">
          <tr>
            <th scope="col" class="px-4 py-3 text-left font-semibold text-ink">
              {gettext("Guarantee")}
            </th>
            <th
              :for={product <- @products}
              scope="col"
              class="px-4 py-3 text-center font-semibold text-ink"
            >
              {product_label(product, @locale)}
            </th>
          </tr>
        </thead>
        <tbody class="divide-y divide-ink/10">
          <tr :for={guarantee <- @guarantees}>
            <th scope="row" class="px-4 py-3 text-left font-medium text-ink">
              {guarantee_name(guarantee, @locale)}
            </th>
            <td :for={product <- @products} class="px-4 py-3 text-center">
              <.matrix_cell
                row={Map.fetch!(@matrix, {product.id, guarantee.code})}
                locale={@locale}
              />
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <section class="mt-8">
      <h2 class="text-lg font-semibold text-ink">{gettext("Conditions générales")}</h2>
      <ul class="mt-4 space-y-2">
        <li :for={product <- @products} class="flex items-center gap-2">
          <span class="text-sm font-medium text-ink">{product_label(product, @locale)}</span>
          <%= if product.cg_document_path do %>
            <.link
              href={~p"/uploads/#{product.cg_document_path}"}
              class="inline-flex items-center gap-1 text-sm text-primary hover:underline"
              download
            >
              <.icon name="hero-document-arrow-down" class="size-4" />
              {gettext("Download CG")}
            </.link>
          <% else %>
            <span class="text-sm text-ink/40">{gettext("Not available")}</span>
          <% end %>
        </li>
      </ul>
    </section>
    """
  end

  attr :row, :map, required: true
  attr :locale, :string, required: true

  defp matrix_cell(assigns) do
    ~H"""
    <%= if @row == nil do %>
      <span class="text-ink/30">—</span>
    <% else %>
      <%= if @row.included do %>
        <.icon name="hero-check" class="mx-auto size-5 text-primary" />
        <div :if={@row.ceiling_centimes} class="mt-1 text-xs text-ink/60">
          {gettext("up to")} {Format.money(@row.ceiling_centimes, @locale)}
        </div>
        <div :if={@row.franchise_centimes} class="text-xs text-ink/60">
          {gettext("franchise")} {Format.money(@row.franchise_centimes, @locale)}
        </div>
      <% else %>
        <.icon name="hero-x-mark" class="mx-auto size-5 text-ink/30" />
      <% end %>
    <% end %>
    """
  end

  attr :guide, :map, required: true
  attr :locale, :string, required: true

  defp related_guide(assigns) do
    assigns =
      assign(assigns,
        title: guide_title(assigns.guide, assigns.locale),
        excerpt: guide_excerpt(assigns.guide, assigns.locale),
        path: ~p"/guides/#{assigns.guide.slug}"
      )

    ~H"""
    <.card class="h-full">
      <.link navigate={@path} class="block">
        <h3 class="text-lg font-semibold text-ink hover:text-primary hover:underline">
          {@title}
        </h3>
      </.link>
      <p :if={@excerpt not in [nil, ""]} class="mt-3 text-sm text-ink/70 line-clamp-3">
        {@excerpt}
      </p>
      <div class="mt-4">
        <.link navigate={@path} class="text-sm text-primary hover:underline">
          {gettext("Read guide")} →
        </.link>
      </div>
    </.card>
    """
  end

  attr :rating, :any, default: nil

  defp rating_badge(assigns) do
    assigns = assign(assigns, rating_string: format_rating(assigns.rating))

    ~H"""
    <span class="inline-flex items-center gap-1 text-sm text-ink/80">
      <.icon name="hero-star" class="size-4 text-primary" />
      {@rating_string}
    </span>
    """
  end

  defp format_rating(nil), do: gettext("Not rated")
  defp format_rating(%Decimal{} = d), do: Decimal.to_string(d)
  defp format_rating(rating) when is_number(rating), do: to_string(rating)

  # Builds a map keyed by `{product_id, guarantee_code}` → `%ProductGuarantee{}`
  # (or `nil` when the product does not offer that guarantee), so the matrix
  # renders the full canonical guarantee list per product in §8 order.
  defp build_matrix(products, guarantees) do
    pairs =
      for product <- products,
          guarantee <- guarantees do
        row =
          Enum.find(product.product_guarantees, fn pg ->
            pg.guarantee_code == guarantee.code
          end)

        {{product.id, guarantee.code}, row}
      end

    Map.new(pairs)
  end

  defp product_label(product, "ar"), do: product.name_ar || product.name_fr
  defp product_label(product, _locale), do: product.name_fr

  defp guarantee_name(guarantee, "ar"), do: guarantee.name_ar || guarantee.name_fr
  defp guarantee_name(guarantee, _locale), do: guarantee.name_fr

  defp guide_title(guide, "ar"), do: guide.title_ar || guide.title_fr
  defp guide_title(guide, _locale), do: guide.title_fr

  defp guide_excerpt(guide, "ar"), do: guide.excerpt_ar || guide.excerpt_fr
  defp guide_excerpt(guide, _locale), do: guide.excerpt_fr

  defp name_for(insurer, "ar"), do: insurer.name_ar || insurer.name_fr
  defp name_for(insurer, _locale), do: insurer.name_fr

  defp related_guides(locale) do
    locale
    |> String.to_existing_atom()
    |> Content.list_published(kind: :guide)
    |> Enum.take(3)
  end

  defp index_path("ar"), do: "/ar/assureurs"
  defp index_path(_locale), do: "/assureurs"

  defp index_breadcrumb_schema(locale) do
    SEO.breadcrumb_schema([
      {gettext("Home"), home_path(locale)},
      {gettext("Insurers"), index_path(locale)}
    ])
  end

  defp show_breadcrumb_schema(insurer, locale) do
    SEO.breadcrumb_schema([
      {gettext("Home"), home_path(locale)},
      {gettext("Insurers"), index_path(locale)},
      {name_for(insurer, locale), nil}
    ])
  end

  defp home_path("ar"), do: "/ar"
  defp home_path(_locale), do: "/"
end
