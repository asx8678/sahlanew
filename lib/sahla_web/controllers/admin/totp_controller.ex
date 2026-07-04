defmodule SahlaWeb.Admin.TotpController do
  @moduledoc """
  Stage two of admin login (§10, §12): the mandatory TOTP second factor.

  Every action requires a *pending* admin (password already verified via
  `SessionController`); without one the request is bounced to the login page, so
  the flow can never be entered cold. `setup`/`confirm` handle first-time
  enrollment (QR provisioning); `verify`/`submit` handle returning logins. Only a
  correct code calls `AdminAuth.log_in_admin/2` to mint the full session.
  """
  use SahlaWeb, :controller

  alias Sahla.Accounts
  alias SahlaWeb.AdminAuth

  plug :require_pending_admin

  def setup(conn, _params) do
    admin = conn.assigns.pending_admin

    if Accounts.totp_enrolled?(admin) do
      redirect(conn, to: ~p"/admin/totp")
    else
      {:ok, admin, secret} = Accounts.setup_totp(admin)
      render_setup(conn, admin, secret, nil)
    end
  end

  def confirm(conn, %{"totp" => %{"code" => code}}) do
    admin = conn.assigns.pending_admin

    case Accounts.activate_totp(admin, code) do
      {:ok, admin} ->
        complete_login(conn, admin)

      {:error, :invalid_code} ->
        # Re-render with the already-stored secret so the QR stays consistent.
        render_setup(conn, admin, admin.totp_secret_enc, gettext("Incorrect code. Try again."))
    end
  end

  def verify(conn, _params) do
    render(conn, :verify, error: nil)
  end

  def submit(conn, %{"totp" => %{"code" => code}}) do
    admin = conn.assigns.pending_admin

    case Accounts.verify_totp(admin, code) do
      {:ok, admin} -> complete_login(conn, admin)
      :error -> render(conn, :verify, error: gettext("Incorrect code. Try again."))
    end
  end

  defp complete_login(conn, admin) do
    conn
    |> AdminAuth.log_in_admin(admin)
    |> redirect(to: ~p"/admin")
  end

  defp render_setup(conn, admin, secret, error) do
    uri = Accounts.totp_provisioning_uri(admin, secret)

    render(conn, :setup,
      qr_svg: Accounts.totp_qr_svg(uri),
      secret_base32: Base.encode32(secret, padding: false),
      error: error
    )
  end

  defp require_pending_admin(conn, _opts) do
    case AdminAuth.get_pending_admin(conn) do
      nil ->
        conn
        |> put_flash(:error, gettext("Please sign in first."))
        |> redirect(to: ~p"/admin/login")
        |> halt()

      admin ->
        assign(conn, :pending_admin, admin)
    end
  end
end
