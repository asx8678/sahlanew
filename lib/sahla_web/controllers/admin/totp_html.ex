defmodule SahlaWeb.Admin.TotpHTML do
  @moduledoc "TOTP enrollment (QR provisioning) and verification forms."
  use SahlaWeb, :html

  def setup(assigns) do
    ~H"""
    <main class="admin-auth">
      <section class="admin-auth__card">
        <h1>{gettext("Set up two-factor authentication")}</h1>
        <p>
          {gettext(
            "Scan this QR code with your authenticator app, then enter the 6-digit code to finish."
          )}
        </p>

        <div class="admin-auth__qr">{raw(@qr_svg)}</div>

        <p class="admin-auth__secret">
          {gettext("Can't scan? Enter this key manually:")}
          <code>{@secret_base32}</code>
        </p>

        <p :if={@error} class="admin-auth__error" role="alert">{@error}</p>

        <form method="post" action={~p"/admin/totp/setup"}>
          <input type="hidden" name="_csrf_token" value={get_csrf_token()} />

          <label for="code">{gettext("Verification code")}</label>
          <input
            id="code"
            type="text"
            name="totp[code]"
            inputmode="numeric"
            autocomplete="one-time-code"
            pattern="[0-9]*"
            maxlength="6"
            required
            autofocus
          />

          <button type="submit">{gettext("Confirm and enable")}</button>
        </form>
      </section>
    </main>
    """
  end

  def verify(assigns) do
    ~H"""
    <main class="admin-auth">
      <section class="admin-auth__card">
        <h1>{gettext("Two-factor authentication")}</h1>
        <p>{gettext("Enter the 6-digit code from your authenticator app.")}</p>

        <p :if={@error} class="admin-auth__error" role="alert">{@error}</p>

        <form method="post" action={~p"/admin/totp"}>
          <input type="hidden" name="_csrf_token" value={get_csrf_token()} />

          <label for="code">{gettext("Verification code")}</label>
          <input
            id="code"
            type="text"
            name="totp[code]"
            inputmode="numeric"
            autocomplete="one-time-code"
            pattern="[0-9]*"
            maxlength="6"
            required
            autofocus
          />

          <button type="submit">{gettext("Verify")}</button>
        </form>
      </section>
    </main>
    """
  end
end
