defmodule SahlaWeb.AdminAuthTest do
  use SahlaWeb.ConnCase, async: true

  alias Sahla.Accounts
  alias SahlaWeb.AdminAuth

  @password "correct horse battery"

  setup %{conn: conn} do
    {:ok, admin} =
      Accounts.register_admin(%{
        email: "auth-#{System.unique_integer([:positive])}@sahla.ma",
        password: @password,
        role: :ops
      })

    conn =
      conn
      |> Map.replace!(:secret_key_base, SahlaWeb.Endpoint.config(:secret_key_base))
      |> init_test_session(%{})

    %{conn: conn, admin: admin}
  end

  test "log_in_admin stores a token and fetch_current_admin loads the admin", %{
    conn: conn,
    admin: admin
  } do
    conn = AdminAuth.log_in_admin(conn, admin)
    assert get_session(conn, :admin_token)

    conn = AdminAuth.fetch_current_admin(conn, [])
    assert conn.assigns.current_admin.id == admin.id
  end

  test "fetch_current_admin assigns nil without a token", %{conn: conn} do
    conn = AdminAuth.fetch_current_admin(conn, [])
    assert conn.assigns.current_admin == nil
  end

  test "a token becomes invalid after the admin's role changes", %{conn: conn, admin: admin} do
    conn = AdminAuth.log_in_admin(conn, admin)

    # role change bumps session_version, so the already-issued token is stale
    {:ok, _} = Accounts.change_admin_role(admin, :superadmin)

    conn = AdminAuth.fetch_current_admin(conn, [])
    assert conn.assigns.current_admin == nil
  end

  test "log_out_admin drops the session token", %{conn: conn, admin: admin} do
    conn = conn |> AdminAuth.log_in_admin(admin) |> AdminAuth.log_out_admin()
    refute get_session(conn, :admin_token)
  end

  test "require_authenticated_admin halts and redirects when not logged in", %{conn: conn} do
    conn =
      conn
      |> fetch_flash()
      |> AdminAuth.fetch_current_admin([])
      |> AdminAuth.require_authenticated_admin([])

    assert conn.halted
    assert redirected_to(conn) == "/admin/login"
  end
end
