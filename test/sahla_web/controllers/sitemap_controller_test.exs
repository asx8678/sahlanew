defmodule SahlaWeb.SitemapControllerTest do
  use SahlaWeb.ConnCase, async: true

  alias Sahla.Accounts
  alias Sahla.Content

  defp post_fixture(attrs) do
    {:ok, admin} =
      Accounts.register_admin(%{
        email: "seo-#{System.unique_integer([:positive])}@sahla.ma",
        password: "correct horse battery staple",
        role: :editor
      })

    attrs =
      Map.merge(
        %{
          slug: "guide-#{System.unique_integer([:positive])}",
          kind: :guide,
          title_fr: "Guide FR",
          title_ar: "Guide AR",
          body_fr: "Contenu",
          body_ar: "محتوى",
          excerpt_fr: "Extrait",
          excerpt_ar: "ملخص",
          status_fr: :published,
          status_ar: :published
        },
        attrs
      )

    {:ok, post} = Content.create_post(attrs, actor: admin)
    post
  end

  describe "GET /sitemap.xml" do
    test "renders a valid sitemap urlset", %{conn: conn} do
      conn = get(conn, ~p"/sitemap.xml")
      body = response(conn, 200)

      assert response_content_type(conn, :xml)
      assert body =~ ~s(<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9")
      assert body =~ ~s(xmlns:xhtml="http://www.w3.org/1999/xhtml")
    end

    test "includes static public routes for both locales", %{conn: conn} do
      conn = get(conn, ~p"/sitemap.xml")
      body = response(conn, 200)

      assert body =~ "#{SahlaWeb.Endpoint.url()}/</loc>"
      assert body =~ "#{SahlaWeb.Endpoint.url()}/ar</loc>"
      assert body =~ "#{SahlaWeb.Endpoint.url()}/devis/new</loc>"
      assert body =~ "#{SahlaWeb.Endpoint.url()}/ar/devis/new</loc>"
    end

    test "includes published posts and excludes drafts", %{conn: conn} do
      published = post_fixture(%{slug: "published-guide", kind: :guide})

      _draft =
        post_fixture(%{slug: "draft-guide", kind: :guide, status_fr: :draft, status_ar: :draft})

      body =
        conn
        |> get(~p"/sitemap.xml")
        |> response(200)

      assert body =~ "#{SahlaWeb.Endpoint.url()}/guides/#{published.slug}</loc>"
      refute body =~ "/guides/draft-guide</loc>"
    end

    test "emits hreflang alternates and x-default for each url", %{conn: conn} do
      post_fixture(%{slug: "hreflang-guide", kind: :guide})

      body =
        conn
        |> get(~p"/sitemap.xml")
        |> response(200)

      assert body =~ ~s(hreflang="fr")
      assert body =~ ~s(hreflang="ar")
      assert body =~ ~s(hreflang="x-default")

      assert body =~
               ~s(<xhtml:link rel="alternate" hreflang="x-default" href="#{SahlaWeb.Endpoint.url()}/guides/hreflang-guide" />)
    end
  end

  describe "GET /robots.txt" do
    test "allows public routes, disallows admin and links sitemap", %{conn: conn} do
      body =
        conn
        |> get(~p"/robots.txt")
        |> response(200)

      assert body =~ "User-agent: *"
      assert body =~ "Allow: /"
      assert body =~ "Disallow: /admin"
      assert body =~ "Sitemap: #{SahlaWeb.Endpoint.url()}/sitemap.xml"
    end
  end
end
