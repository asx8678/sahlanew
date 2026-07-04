defmodule SahlaWeb.Admin.SessionController do
  @moduledoc """
  Stage one of the mandatory two-stage admin login (§10, §12): password only.

  A correct password never issues a full session — it opens the half-auth 2FA
  stage (`AdminAuth.start_admin_2fa/2`) and routes the admin to TOTP setup (if
  unenrolled) or verification (if enrolled). Only `TotpController` completes the
  login.
  """
  use SahlaWeb, :controller

  alias Sahla.Accounts
  alias SahlaWeb.AdminAuth

  def new(conn, _params) do
    render(conn, :new, error: nil, email: "")
  end

  def create(conn, %{"admin" => %{"email" => email, "password" => password}}) do
    case Accounts.authenticate_admin(email, password, client_ip(conn)) do
      {:ok, admin} ->
        conn = AdminAuth.start_admin_2fa(conn, admin)

        if Accounts.totp_enrolled?(admin) do
          redirect(conn, to: ~p"/admin/totp")
        else
          redirect(conn, to: ~p"/admin/totp/setup")
        end

      {:error, reason} ->
        conn
        |> put_flash(:error, error_message(reason))
        |> render(:new, error: error_message(reason), email: email)
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, gettext("Signed out."))
    |> AdminAuth.log_out_admin()
    |> redirect(to: ~p"/admin/login")
  end

  defp client_ip(conn), do: conn.remote_ip |> :inet.ntoa() |> to_string()

  defp error_message({:rate_limited, retry_after}) do
    gettext("Too many attempts. Try again in %{seconds}s.", seconds: retry_after)
  end

  defp error_message(:inactive), do: gettext("This account is disabled.")
  defp error_message(_), do: gettext("Invalid email or password.")
end
