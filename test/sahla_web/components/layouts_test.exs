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

    assert html =~ Sahla.Settings.display_name()
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

  describe "admin layout" do
    setup %{conn: conn} do
      {:ok, admin} =
        Sahla.Accounts.register_admin(%{
          email: "layout-admin-#{System.unique_integer([:positive])}@sahla.ma",
          password: "correct horse battery staple",
          role: :ops
        })

      conn =
        conn
        |> Plug.Test.init_test_session(%{})
        |> SahlaWeb.AdminAuth.log_in_admin(admin)
        |> SahlaWeb.AdminAuth.fetch_current_admin([])

      %{conn: conn, admin: admin}
    end

    test "authenticated /admin renders the admin shell", %{conn: conn, admin: admin} do
      conn = get(conn, ~p"/admin")
      html = html_response(conn, 200)

      assert html =~ ~S(<aside)
      assert html =~ "Dashboard"
      assert html =~ "Leads"
      assert html =~ "Quotes"
      assert html =~ "Rating studio"
      assert html =~ "Directory"
      assert html =~ "Content"
      assert html =~ "Notifications"
      assert html =~ "Settings"
      assert html =~ "Audit"

      assert html =~ admin.email
      assert html =~ to_string(admin.role)
      assert html =~ ~S(<form method="post" action="/admin/logout")
      assert html =~ ~S(<button type="submit")
      assert html =~ ~S(<nav aria-label="Breadcrumb">)
    end

    test "admin login page does not use the admin chrome layout", %{conn: conn} do
      conn = get(conn, ~p"/admin/login")
      html = html_response(conn, 200)

      refute html =~ ~S(<aside)
      refute html =~ "Sign out"
      assert html =~ "Admin sign in"
    end

    test "admin layout renders flash messages", %{conn: conn} do
      conn =
        conn
        |> Phoenix.Controller.fetch_flash(%{})
        |> Phoenix.Controller.put_flash(:info, "Welcome back")

      conn = get(conn, ~p"/admin")
      html = html_response(conn, 200)

      assert html =~ "Welcome back"
      assert html =~ ~S(<div id="flash-group")
    end
  end
end
