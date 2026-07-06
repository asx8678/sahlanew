defmodule SahlaWeb.HomeLiveTest do
  @moduledoc false
  use SahlaWeb.ConnCase, async: true

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Sahla.Content
  alias Sahla.Directory

  setup %{conn: conn} do
    Directory.ensure_seed_catalog!()

    admin =
      Sahla.Repo.insert!(%Sahla.Accounts.Admin{
        email: "cms@example.com",
        role: :superadmin,
        password_hash: "disabled"
      })

    {:ok, guide} =
      Content.create_post(
        %{
          slug: "assurance-auto-maroc",
          kind: :guide,
          title_fr: "L'assurance auto au Maroc",
          title_ar: "تأمين السيارات في المغرب",
          excerpt_fr: "Ce guide explique les garanties obligatoires.",
          excerpt_ar: "يشرح هذا الدليل الضمانات الإلزامية.",
          body_fr: "# Assurance auto\n\nLe RC est obligatoire.",
          body_ar: "# تأمين السيارات\n\nالRC إلزامي.",
          status_fr: :published,
          status_ar: :published
        },
        actor: admin
      )

    %{conn: conn, guide: guide}
  end

  test "renders hero, insurer strip, how-it-works, guides, FAQ and legal footer", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/")

    assert html =~ "Find the right car insurance"
    assert html =~ "Compare now"
    assert html =~ "Partner insurers"
    assert html =~ "How it works"
    assert html =~ "Useful guides"
    assert html =~ "Frequently asked questions"
    # Shared legal footer (Layouts.footer/1) is reused on the homepage.
    assert html =~ "<footer"
    assert html =~ "Legal notices"
    assert html =~ "Privacy policy"
  end

  test "plate submit creates a quote and redirects to /devis/:token", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/")

    result =
      lv
      |> form("#hero-form", plate: "12345-A-67")
      |> render_submit()

    assert {:error, {:redirect, %{to: "/devis/" <> _}}} = result

    quote =
      Sahla.Quoting.Quote
      |> order_by(desc: :id)
      |> limit(1)
      |> Sahla.Repo.one()

    assert quote.plate == "12345-A-67"
  end

  test "WW toggle creates a new-vehicle quote without plate", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/")

    lv |> element("button[phx-click='toggle_ww']") |> render_click()

    result =
      lv
      |> form("#hero-form")
      |> render_submit()

    assert {:error, {:redirect, %{to: "/devis/" <> _}}} = result

    quote =
      Sahla.Quoting.Quote
      |> order_by(desc: :id)
      |> limit(1)
      |> Sahla.Repo.one()

    assert quote.is_new_ww == true
    assert is_nil(quote.plate)
  end

  test "invalid plate shows error", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/")

    result =
      lv
      |> form("#hero-form", plate: "not-a-plate")
      |> render_submit()

    refute match?({:error, {:redirect, _}}, result)
    assert result =~ "Enter a valid Moroccan plate"
  end

  test "Arabic scope renders dir=rtl", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/ar")
    assert html =~ "dir=\"rtl\""
  end

  test "renders latest published guide teaser", %{conn: conn, guide: guide} do
    {:ok, _lv, html} = live(conn, ~p"/")

    # HEEx escapes the apostrophe in the title (L'assurance -> L&#39;assurance).
    assert html =~ "L&#39;assurance auto au Maroc"
    assert html =~ guide.excerpt_fr
  end
end
