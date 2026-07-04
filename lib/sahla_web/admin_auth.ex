defmodule SahlaWeb.AdminAuth do
  @moduledoc """
  Session plumbing for admins: signed session tokens plus the plugs the admin
  pipeline and scopes use.

  The token is a `Phoenix.Token`-signed `{admin_id, session_version}`. On every
  request `fetch_current_admin/2` verifies it and loads the admin via
  `Accounts.get_admin_for_session/2`, which rejects the session if the admin's
  `session_version` has since moved (role change) or the account was
  deactivated.
  """
  import Plug.Conn
  import Phoenix.Controller

  alias Sahla.Accounts

  @salt "admin session"
  # 14 days.
  @max_age 60 * 60 * 24 * 14

  @doc "Logs an admin in: records the login, stores a fresh signed token, renews the session."
  def log_in_admin(conn, admin) do
    {:ok, admin} = Accounts.track_login(admin)
    token = sign_token(admin)

    conn
    |> renew_session()
    |> put_session(:admin_token, token)
    |> put_session(:live_socket_id, "admin_sessions:#{admin.id}")
  end

  @doc """
  Starts the half-authenticated 2FA stage after a correct password: renews the
  session and stores only the *pending* admin id/version — no `:admin_token` is
  issued, so protected admin routes stay unreachable until TOTP is verified.
  """
  def start_admin_2fa(conn, admin) do
    conn
    |> renew_session()
    |> put_session(:admin_pending_id, admin.id)
    |> put_session(:admin_pending_version, admin.session_version)
  end

  @doc "Loads the pending (password-verified, pre-2FA) admin, or `nil`."
  def get_pending_admin(conn) do
    with id when is_binary(id) <- get_session(conn, :admin_pending_id),
         version when is_integer(version) <- get_session(conn, :admin_pending_version) do
      Accounts.get_admin_for_session(id, version)
    else
      _ -> nil
    end
  end

  @doc "Logs the current admin out by dropping the session."
  def log_out_admin(conn) do
    renew_session(conn)
  end

  @doc "Assigns `:current_admin` from the session token (or `nil`)."
  def fetch_current_admin(conn, _opts) do
    assign(conn, :current_admin, admin_from_session(conn))
  end

  @doc "Halts with a redirect to the login page unless an admin is authenticated."
  def require_authenticated_admin(conn, _opts) do
    if conn.assigns[:current_admin] do
      conn
    else
      conn
      |> put_flash(:error, "You must log in to access this page.")
      |> redirect(to: "/admin/login")
      |> halt()
    end
  end

  @doc "Signs a session token binding the admin id to its current session version."
  def sign_token(admin) do
    Phoenix.Token.sign(SahlaWeb.Endpoint, @salt, {admin.id, admin.session_version})
  end

  defp admin_from_session(conn) do
    with token when is_binary(token) <- get_session(conn, :admin_token),
         {:ok, {id, version}} <-
           Phoenix.Token.verify(SahlaWeb.Endpoint, @salt, token, max_age: @max_age) do
      Accounts.get_admin_for_session(id, version)
    else
      _ -> nil
    end
  end

  defp renew_session(conn) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
  end
end
