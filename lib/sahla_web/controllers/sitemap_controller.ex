defmodule SahlaWeb.SitemapController do
  @moduledoc """
  Generates SEO crawlers' sitemap.xml and robots.txt (§5.4).

  - `sitemap.xml` lists every public static route plus published content
    (posts, insurers, glossary, city pages) in both fr and ar, with hreflang
    alternates and an x-default pointing to the French URL.
  - `robots.txt` allows public routes, disallows /admin, and links the sitemap.

  Responses are short and cache-friendly; dynamic tokens and admin surfaces are
  excluded.
  """
  use SahlaWeb, :controller

  alias Sahla.Content

  # Pages that exist today. Future public surfaces (guides, insurers, glossary,
  # cities) are appended here as they are built.
  @static_paths [
    "/",
    "/devis/new"
  ]

  @locales ~w(fr ar)

  @doc "Robots policy: allow public, disallow admin, link sitemap."
  def robots(conn, _params) do
    sitemap_url = SahlaWeb.Endpoint.url() <> ~p"/sitemap.xml"

    body = """
    User-agent: *
    Allow: /
    Disallow: /admin
    Sitemap: #{sitemap_url}
    """

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, body)
  end

  @doc "Renders a bilingual sitemap.xml with hreflang alternates."
  def sitemap(conn, _params) do
    urls =
      Enum.flat_map(static_entries(), fn entry ->
        for locale <- @locales, do: build_url(entry.path, locale)
      end)

    body =
      [
        ~s(<?xml version="1.0" encoding="UTF-8"?>),
        ~s(<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">),
        Enum.map_join(urls, "\n", &render_url/1),
        "</urlset>"
      ]
      |> IO.iodata_to_binary()

    conn
    |> put_resp_content_type("application/xml")
    |> put_resp_header("cache-control", "public, max-age=3600")
    |> send_resp(200, body)
  end

  defp static_entries do
    # Each post appears once with its canonical (fr) path; the sitemap then
    # emits both locale variants via `localised_path`.
    posts =
      for post <- Content.published_posts(:fr),
          path = post_path(post, :fr),
          do: %{path: path}

    Enum.map(@static_paths, &%{path: &1}) ++ posts
  end

  defp post_path(%{slug: slug, kind: :guide}, :fr), do: "/guides/#{slug}"
  defp post_path(%{slug: slug, kind: :faq}, :fr), do: "/faq/#{slug}"
  defp post_path(%{slug: slug, kind: :page}, :fr), do: "/#{slug}"

  defp localised_path("/", "ar"), do: "/ar"
  defp localised_path("/" <> rest, "ar"), do: "/ar/#{rest}"
  defp localised_path(path, "fr"), do: path

  defp build_url(path, locale) do
    %{
      loc: SahlaWeb.Endpoint.url() <> localised_path(path, locale),
      alternates: alternates(path)
    }
  end

  defp alternates(path) do
    x_default = SahlaWeb.Endpoint.url() <> localised_path(path, "fr")

    [
      %{hreflang: "fr", href: SahlaWeb.Endpoint.url() <> localised_path(path, "fr")},
      %{hreflang: "ar", href: SahlaWeb.Endpoint.url() <> localised_path(path, "ar")},
      %{hreflang: "x-default", href: x_default}
    ]
  end

  defp render_url(%{loc: loc, alternates: alternates}) do
    alternates_xml =
      Enum.map_join(alternates, "\n    ", fn %{hreflang: hreflang, href: href} ->
        ~s(<xhtml:link rel="alternate" hreflang="#{escape(hreflang)}" href="#{escape(href)}" />)
      end)

    """
      <url>
        <loc>#{escape(loc)}</loc>
        #{alternates_xml}
      </url>
    """
  end

  defp escape(value) when is_binary(value) do
    value
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end
end
