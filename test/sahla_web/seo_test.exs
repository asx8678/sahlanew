defmodule SahlaWeb.SEOTest do
  use SahlaWeb.ConnCase, async: true

  alias SahlaWeb.SEO

  describe "root layout" do
    test "renders SEO tags inside <head>", %{conn: conn} do
      conn = get(conn, ~p"/")
      html = html_response(conn, 200)

      assert html =~ ~r/<head>.*<title>.*<\/title>.*<\/head>/ms
      assert html =~ ~r/<head>.*<meta[^>]+property="og:title"[^>]*>.*<\/head>/ms
      assert html =~ ~r/<head>.*<link[^>]+rel="canonical"[^>]*>.*<\/head>/ms
      assert html =~ ~r/<head>.*<link[^>]+rel="alternate"[^>]+hreflang="fr"[^>]*>.*<\/head>/ms
    end

    test "emits fr, ar and x-default hreflang alternates", %{conn: conn} do
      conn = get(conn, ~p"/")
      html = html_response(conn, 200)

      assert html =~ ~S(hreflang="fr")
      assert html =~ ~S(hreflang="ar")
      assert html =~ ~S(hreflang="x-default")
    end

    test "title falls back to Settings.display_name() when page_title is absent", %{conn: conn} do
      # `/` is now HomeLive, which always sets a page_title; `/design-tokens` is
      # a controller-rendered page that sets none, so it exercises the fallback.
      conn = get(conn, ~p"/design-tokens")
      html = html_response(conn, 200)
      brand = Sahla.Settings.display_name()

      assert html =~ ~r/<title>#{Regex.escape(brand)}<\/title>/
      refute html =~ "Sahla · Sahla"
    end

    test "does not render hardcoded brand string when display_name changes", %{conn: conn} do
      original = Application.get_env(:sahla, :brand_name)

      on_exit(fn ->
        Application.put_env(:sahla, :brand_name, original)
      end)

      Application.put_env(:sahla, :brand_name, "AssurTest")
      Sahla.Settings.seed_defaults()

      conn = get(conn, ~p"/")
      html = html_response(conn, 200)

      assert html =~ "AssurTest"
      refute html =~ ~S(<title>Sahla · Sahla</title>)
    end

    test "omits description meta when meta_description is not set", %{conn: conn} do
      # `/` is HomeLive, which sets a meta_description; `/design-tokens` sets
      # none, so it exercises the description-omitted path.
      conn = get(conn, ~p"/design-tokens")
      html = html_response(conn, 200)

      refute html =~ ~r/<head>.*<meta[^>]+name="description"[^>]*>.*<\/head>/ms
    end
  end

  describe "SEO component assigns" do
    test "uses provided page_title and meta_description" do
      assigns = %{
        page_title: "Devis",
        meta_description: "Comparez les assurances",
        locale: "fr",
        dir: "ltr",
        request_path: "/",
        inner_content: ""
      }

      rendered =
        Phoenix.LiveViewTest.rendered_to_string(SahlaWeb.SEO.seo(assigns))

      assert rendered =~ ~S(<title>Devis · )
      assert rendered =~ ~S(<meta name="description" content="Comparez les assurances")
    end
  end

  describe "SEO helpers" do
    test "organization_schema/1 returns valid JSON-LD map" do
      schema = SEO.organization_schema(%{"logo" => "https://example.com/logo.png"})

      assert schema["@context"] == "https://schema.org"
      assert schema["@type"] == "Organization"
      assert is_binary(schema["name"])
      assert is_binary(schema["url"])
      assert schema["logo"] == "https://example.com/logo.png"

      assert is_map(Jason.decode!(Jason.encode!(schema)))
    end

    test "breadcrumb_schema/1 builds a BreadcrumbList" do
      schema =
        SEO.breadcrumb_schema([
          {"Home", "/"},
          {"Guides", "/guides"}
        ])

      assert schema["@type"] == "BreadcrumbList"
      [first, second] = schema["itemListElement"]

      assert first["position"] == 1
      assert first["name"] == "Home"
      assert first["item"] == SahlaWeb.Endpoint.url() <> "/"

      assert second["position"] == 2
      assert second["name"] == "Guides"
      assert second["item"] == SahlaWeb.Endpoint.url() <> "/guides"

      assert is_map(Jason.decode!(Jason.encode!(schema)))
    end

    test "json_ld_script/1 renders valid JSON inside a script tag" do
      assigns = %{schema: SEO.organization_schema()}

      rendered =
        Phoenix.LiveViewTest.rendered_to_string(SEO.json_ld_script(assigns))

      assert rendered =~ ~S(<script type="application/ld+json">)
      assert rendered =~ "Organization"

      [json] =
        Regex.run(~r/<script[^>]*>\s*(.*?)\s*<\/script>/s, rendered, capture: :all_but_first)

      assert is_map(Jason.decode!(json))
    end
  end

  describe "canonical URL and locale alternates" do
    test "uses Endpoint.url() as the base URL" do
      assigns = %{
        page_title: "Test",
        canonical_path: "/guides/assurance-auto"
      }

      rendered =
        Phoenix.LiveViewTest.rendered_to_string(SEO.seo(assigns))

      assert rendered =~ "http://localhost:4000/guides/assurance-auto"

      assert rendered =~
               ~S(<link rel="canonical" href="http://localhost:4000/guides/assurance-auto">)

      assert rendered =~ ~S(hreflang="ar" href="http://localhost:4000/ar/guides/assurance-auto")

      assert rendered =~
               ~S(hreflang="x-default" href="http://localhost:4000/guides/assurance-auto")
    end
  end
end
