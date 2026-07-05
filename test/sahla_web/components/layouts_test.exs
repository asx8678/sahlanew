defmodule SahlaWeb.LayoutsTest do
  use SahlaWeb.ConnCase, async: true

  test "root layout sets lang=fr and dir=ltr by default", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)
    assert html =~ ~S(<html lang="fr" dir="ltr">)
  end

  test "root layout sets lang=ar and dir=rtl on /ar", %{conn: conn} do
    conn = get(conn, ~p"/ar")
    html = html_response(conn, 200)
    assert html =~ ~S(<html lang="ar" dir="rtl">)
  end

  test "app layout renders topbar, footer and main content", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)

    assert html =~ "Sahla"
    assert html =~ ~S(<footer)
    assert html =~ ~S(<header)
    assert html =~ ~S(<main)
  end

  test "topbar has a navigation landmark", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)
    assert html =~ ~S(<nav)
  end

  test "flash renders after a redirect", %{conn: conn} do
    conn =
      conn
      |> get(~p"/")
      |> Phoenix.ConnTest.recycle()

    conn = Phoenix.ConnTest.dispatch(conn, SahlaWeb.Endpoint, :get, "/")
    html = html_response(conn, 200)
    refute html =~ "Bonjour"
  end

  test "plausible script is not rendered by default in test", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)
    refute html =~ "plausible.io"
    assert html =~ "<!-- analytics off -->"
  end

  test "plausible script renders in head when enabled and domain configured", %{conn: conn} do
    original_domain = Application.get_env(:sahla, :plausible_domain)
    original_enabled = Application.get_env(:sahla, :analytics_enabled)

    on_exit(fn ->
      Application.put_env(:sahla, :plausible_domain, original_domain)
      Application.put_env(:sahla, :analytics_enabled, original_enabled)
    end)

    Application.put_env(:sahla, :plausible_domain, "sahla.ma")
    Application.put_env(:sahla, :analytics_enabled, true)

    conn = get(conn, ~p"/")
    html = html_response(conn, 200)

    assert html =~ ~S(data-domain="sahla.ma")
    assert html =~ "plausible.io/js/script.manual.outbound-links.js"
    # The script must live inside <head>, before the app.js script.
    assert html =~ ~r/<head>.*plausible\.io.*<script defer phx-track-static/ms
  end
end
