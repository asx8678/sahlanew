defmodule SahlaWeb.GuidesLiveTest do
  use SahlaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Sahla.Accounts
  alias Sahla.Content

  defp admin_fixture do
    {:ok, admin} =
      Accounts.register_admin(%{
        email: "guide-admin-#{System.unique_integer([:positive])}@sahla.ma",
        password: "correct horse battery staple",
        role: :editor
      })

    admin
  end

  defp guide_fixture(attrs) do
    attrs =
      Map.merge(
        %{
          slug: "guide-#{System.unique_integer([:positive])}",
          kind: :guide,
          title_fr: "Guide FR",
          title_ar: "دليل AR",
          body_fr: "## Section une\n\nContenu du guide.",
          body_ar: "## القسم الأول\n\nمحتوى الدليل.",
          excerpt_fr: "Extrait du guide",
          excerpt_ar: "ملخص الدليل",
          status_fr: :published,
          status_ar: :published
        },
        attrs
      )

    {:ok, post} = Content.create_post(attrs, actor: admin_fixture())
    post
  end

  describe "GET /guides" do
    test "lists a published guide", %{conn: conn} do
      _guide = guide_fixture(%{title_fr: "Guide visible"})

      {:ok, _lv, html} = live(conn, ~p"/guides")

      assert html =~ "Guide visible"
      assert html =~ "guides-list"
      assert html =~ "phx-update=\"stream\""
    end

    test "empty-state sits outside the stream container", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/guides")

      refute html =~ "guides-list"
      refute html =~ "phx-update=\"stream\""
      assert html =~ "No guides published yet"
    end
  end

  describe "GET /guides/:slug" do
    test "renders the guide body and title", %{conn: conn} do
      _guide = guide_fixture(%{title_fr: "Mon guide", slug: "mon-guide"})

      {:ok, _lv, html} = live(conn, ~p"/guides/mon-guide")

      assert html =~ "Mon guide"
      assert html =~ "Section une"
      assert html =~ "Contenu du guide"
    end

    test "unpublished or missing slug redirects and does not leak title", %{conn: conn} do
      guide_fixture(%{title_fr: "Titre secret", slug: "secret", status_fr: :draft})

      assert {:error, {:redirect, %{to: "/guides"}}} = live(conn, ~p"/guides/secret")
    end

    test "/ar/guides/:slug renders rtl and Arabic title", %{conn: conn} do
      guide_fixture(%{slug: "ar-guide"})

      {:ok, _lv, html} = live(conn, ~p"/ar/guides/ar-guide")

      assert html =~ ~S(<html lang="ar" dir="rtl">)
      assert html =~ "دليل AR"
    end

    test "renders breadcrumb JSON-LD in the head", %{conn: conn} do
      guide_fixture(%{title_fr: "Guide breadcrumb", slug: "breadcrumb-guide"})

      {:ok, _lv, html} = live(conn, ~p"/guides/breadcrumb-guide")

      assert html =~ ~s("@type\":\"BreadcrumbList\")
      assert html =~ ~s("name\":\"Guides\")
      assert html =~ ~s("name\":\"Guide breadcrumb\")
    end
  end
end
