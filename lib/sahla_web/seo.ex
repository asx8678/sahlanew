defmodule SahlaWeb.SEO do
  @moduledoc """
  SEO `<head>` tags component.

  Drop `<.seo />` inside a root layout `<head>` block. It reads the following
  assigns and renders `<title>`, description, OpenGraph, Twitter card,
  canonical link, hreflang alternates, and JSON-LD structured data.

  ## Assigns

    * `:page_title` — page-specific title segment. Falls back to
      `Sahla.Settings.display_name/0`.
    * `:meta_description` — rendered as `<meta name="description">`. Omitted
      when blank.
    * `:canonical_path` — path segment of the canonical URL. Falls back to
      the current request path.
    * `:og_image` — absolute or root-relative image URL for OpenGraph and
      Twitter. Falls back to `/images/og-default.png`.

  Two JSON-LD helpers are also exposed for controllers and LiveViews:

    * `organization_schema/1`
    * `breadcrumb_schema/1`

  ## Example

      <.seo
        page_title={@page_title}
        meta_description={@meta_description}
        canonical_path={@canonical_path}
        og_image={@og_image}
      />

  """
  use SahlaWeb, :html

  alias Sahla.Settings

  @default_og_image "/images/og-default.png"

  attr :page_title, :string, default: nil
  attr :meta_description, :string, default: nil
  attr :canonical_path, :string, default: nil
  attr :og_image, :string, default: nil
  attr :breadcrumb_schema, :map, default: nil

  def seo(assigns) do
    page_title = assigns[:page_title]
    meta_description = assigns[:meta_description]
    canonical_path = assigns[:canonical_path] || current_path(assigns)
    og_image = assigns[:og_image] || @default_og_image
    brand = Settings.display_name()
    base_url = base_url()
    canonical_url = base_url <> canonical_path
    og_image_url = absolute_url(base_url, og_image)
    locale = Map.get(assigns, :locale, "fr")

    title =
      if is_binary(page_title) and String.trim(page_title) != "" do
        "#{page_title} · #{brand}"
      else
        brand
      end

    breadcrumb_json =
      if is_map(assigns[:breadcrumb_schema]) and map_size(assigns[:breadcrumb_schema]) > 0 do
        Jason.encode!(assigns[:breadcrumb_schema])
      else
        nil
      end

    assigns =
      assigns
      |> Map.put(:title, title)
      |> Map.put(:meta_description, meta_description)
      |> Map.put(:canonical_url, canonical_url)
      |> Map.put(:canonical_path, canonical_path)
      |> Map.put(:og_image_url, og_image_url)
      |> Map.put(:locale, locale)
      |> Map.put(:base_url, base_url)
      |> Map.put(:breadcrumb_json, breadcrumb_json)

    ~H"""
    <title>{@title}</title>
    <%= if @meta_description not in [nil, ""] do %>
      <meta name="description" content={@meta_description} />
    <% end %>
    <meta property="og:title" content={@title} />
    <%= if @meta_description not in [nil, ""] do %>
      <meta property="og:description" content={@meta_description} />
    <% end %>
    <meta property="og:type" content="website" />
    <meta property="og:url" content={@canonical_url} />
    <meta property="og:image" content={@og_image_url} />
    <meta property="og:locale" content={og_locale(@locale)} />
    <meta name="twitter:card" content="summary_large_image" />
    <meta name="twitter:title" content={@title} />
    <%= if @meta_description not in [nil, ""] do %>
      <meta name="twitter:description" content={@meta_description} />
    <% end %>
    <meta name="twitter:image" content={@og_image_url} />
    <link rel="canonical" href={@canonical_url} />
    <%= for locale <- ~w(fr ar) do %>
      <link
        rel="alternate"
        hreflang={locale}
        href={@base_url <> localised_path(@canonical_path, locale)}
      />
    <% end %>
    <link
      rel="alternate"
      hreflang="x-default"
      href={@base_url <> localised_path(@canonical_path, "fr")}
    />
    <%= if @breadcrumb_json do %>
      <script type="application/ld+json">
        <%= raw(@breadcrumb_json) %>
      </script>
    <% end %>
    """
  end

  @doc """
  Builds a JSON-LD Organization schema map.
  """
  def organization_schema(overrides \\ %{}) do
    Map.merge(
      %{
        "@context" => "https://schema.org",
        "@type" => "Organization",
        "name" => Settings.display_name(),
        "url" => base_url()
      },
      overrides
    )
  end

  @doc """
  Builds a JSON-LD BreadcrumbList schema map from a list of items.

  Each item may be a string label or a `{name, url}` tuple.
  """
  def breadcrumb_schema(items) when is_list(items) do
    item_list =
      items
      |> Enum.with_index(1)
      |> Enum.map(fn
        {{name, nil}, idx} ->
          %{
            "@type" => "ListItem",
            "position" => idx,
            "name" => name
          }

        {{name, url}, idx} when is_binary(url) ->
          %{
            "@type" => "ListItem",
            "position" => idx,
            "name" => name,
            "item" => absolute_url(base_url(), url)
          }

        {name, idx} ->
          %{
            "@type" => "ListItem",
            "position" => idx,
            "name" => name
          }
      end)

    %{
      "@context" => "https://schema.org",
      "@type" => "BreadcrumbList",
      "itemListElement" => item_list
    }
  end

  @doc """
  Renders a JSON-LD `<script>` tag for a schema map.
  """
  def json_ld_script(assigns) do
    schema = Map.fetch!(assigns, :schema)
    assigns = Map.put(assigns, :json, Jason.encode!(schema))

    ~H"""
    <script type="application/ld+json">
      <%= raw(@json) %>
    </script>
    """
  end

  defp base_url do
    site_url = Settings.get("site_url")

    if is_binary(site_url) and String.trim(site_url) != "" do
      String.trim_trailing(site_url, "/")
    else
      SahlaWeb.Endpoint.url()
    end
  end

  defp absolute_url(_base_url, "http" <> _rest = url), do: url
  defp absolute_url(_base_url, "//" <> _rest = url), do: "https:" <> url
  defp absolute_url(_base_url, "/" <> _ = path), do: base_url() <> path
  defp absolute_url(base_url, path), do: base_url <> "/" <> path

  defp current_path(%{request_path: request_path}) when is_binary(request_path), do: request_path
  defp current_path(%{socket: %{view: _view}}), do: "/"
  defp current_path(_assigns), do: "/"

  defp localised_path("/", "ar"), do: "/ar"
  defp localised_path("/" <> rest, "ar"), do: "/ar/" <> rest
  defp localised_path(path, "fr"), do: path
  defp localised_path(path, _locale), do: path

  defp og_locale("ar"), do: "ar_MA"
  defp og_locale(_locale), do: "fr_MA"
end
