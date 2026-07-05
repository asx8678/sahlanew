defmodule SahlaWeb.DevisLiveTest do
  use SahlaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Sahla.Quoting

  test "GET /devis/new creates a fresh quote and redirects", %{conn: conn} do
    conn = get(conn, ~p"/devis/new")
    assert %{status: 302} = conn
    assert String.starts_with?(redirected_to(conn), "/devis/")
  end

  test "mount loads an existing quote and shows the current step", %{conn: conn} do
    {:ok, quote} = Quoting.create_quote(%{locale: "fr"})

    {:ok, _lv, html} = live(conn, ~p"/devis/#{quote.token}")

    assert html =~ "Your vehicle"
    assert html =~ ~s(aria-label="Quote progress")
  end

  test "an unknown token creates a new quote and redirects", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/devis/" <> _}}} = live(conn, ~p"/devis/unknown-token")
  end

  test "autosave persists a field", %{conn: conn} do
    {:ok, quote} = Quoting.create_quote(%{locale: "fr"})

    {:ok, lv, _html} = live(conn, ~p"/devis/#{quote.token}")

    html = lv |> element("form") |> render_change(%{step: %{plate: "12345-A-67"}})
    assert html =~ "12345-A-67"

    reloaded = Quoting.get_quote_by_token(quote.token)
    assert reloaded.plate == "12345-A-67"
  end

  test "continue advances the step and resumes at that step", %{conn: conn} do
    {:ok, quote} = Quoting.create_quote(%{locale: "fr"})

    {:ok, lv, _html} = live(conn, ~p"/devis/#{quote.token}")

    lv |> element("button[phx-click='continue']") |> render_click()

    assert Quoting.get_quote_by_token(quote.token).current_step == 2

    {:ok, _lv, html} = live(conn, ~p"/devis/#{quote.token}")
    assert html =~ "Driver profile"
  end

  test "back returns to the previous step", %{conn: conn} do
    {:ok, quote} = Quoting.create_quote(%{locale: "fr", current_step: 2})

    {:ok, lv, html} = live(conn, ~p"/devis/#{quote.token}")
    assert html =~ "Driver profile"
    refute html =~ "disabled"

    lv |> element("button[phx-click='back']") |> render_click()

    assert Quoting.get_quote_by_token(quote.token).current_step == 1
  end

  test "route is mirrored under /ar", %{conn: conn} do
    {:ok, quote} = Quoting.create_quote(%{locale: "ar"})

    {:ok, _lv, html} = live(conn, ~p"/ar/devis/#{quote.token}")
    assert html =~ ~S(<html lang="ar" dir="rtl">)
    assert html =~ "Your vehicle"
  end

  test "an expired quote renders the expired screen", %{conn: conn} do
    {:ok, quote} = Quoting.create_quote(%{locale: "fr"})
    {:ok, _quote} = Quoting.expire_quote(quote)

    {:ok, _lv, html} = live(conn, ~p"/devis/#{quote.token}")
    assert html =~ "This quote link has expired"
  end

  test "mounting a resumed quote pushes a funnel_start plausible event", %{conn: conn} do
    {:ok, quote} = Quoting.create_quote(%{locale: "fr"})

    {:ok, lv, _html} = live(conn, ~p"/devis/#{quote.token}")

    assert_push_event(lv, "plausible-event", %{name: "funnel_start", props: %{source: "resume"}})
  end
end
