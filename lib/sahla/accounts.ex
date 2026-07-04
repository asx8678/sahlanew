defmodule Sahla.Accounts do
  @moduledoc """
  Admin identity, authentication and sessions (§10, §12).

  Authentication is throttled per email+IP and constant-time on unknown emails.
  Sessions are validated by comparing a token's `session_version` against the
  admin's current one (see `get_admin_for_session/2`), so a role change or
  deactivation kills outstanding sessions on their next request.
  """
  import Ecto.Query

  alias Sahla.Accounts.Admin
  alias Sahla.Notifications.RateLimit
  alias Sahla.Repo
  alias Sahla.Settings

  @doc "Registers an admin from `attrs`."
  def register_admin(attrs) do
    %Admin{}
    |> Admin.registration_changeset(attrs)
    |> Repo.insert()
  end

  def get_admin!(id), do: Repo.get!(Admin, id)

  def get_admin_by_email(email) when is_binary(email), do: Repo.get_by(Admin, email: email)

  @doc """
  Returns the admin if `email`/`password` match, else `nil`. Always runs a hash
  comparison — a dummy one for an unknown email — so timing is constant.
  """
  def get_admin_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    admin = Repo.get_by(Admin, email: email)
    if Admin.valid_password?(admin, password), do: admin
  end

  @doc """
  Authenticates an admin with per-email+IP throttling.

  Returns `{:ok, admin}`, `{:error, :invalid_credentials}`, `{:error, :inactive}`
  or `{:error, {:rate_limited, retry_after_seconds}}`.
  """
  def authenticate_admin(email, password, ip) do
    case RateLimit.admin_login(ip, email) do
      {:deny, retry_after} ->
        {:error, {:rate_limited, retry_after}}

      {:allow} ->
        case get_admin_by_email_and_password(email, password) do
          %Admin{active: true} = admin -> {:ok, admin}
          %Admin{active: false} -> {:error, :inactive}
          nil -> {:error, :invalid_credentials}
        end
    end
  end

  @doc """
  Loads the admin for a session identifier, but only if still active and the
  `session_version` matches — otherwise `nil` (the session is dead).
  """
  def get_admin_for_session(admin_id, session_version) do
    Admin
    |> where(
      [a],
      a.id == ^admin_id and a.active == true and a.session_version == ^session_version
    )
    |> Repo.one()
  end

  @doc "Changes an admin's role, invalidating their existing sessions."
  def change_admin_role(%Admin{} = admin, new_role) do
    admin
    |> Admin.role_changeset(new_role)
    |> Repo.update()
  end

  @doc "Records a successful login timestamp."
  def track_login(%Admin{} = admin) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    admin
    |> Ecto.Changeset.change(last_login_at: now)
    |> Repo.update()
  end

  # --- TOTP two-factor (§10, §12) --------------------------------------------

  # Standard 30-second TOTP period; a ±1 step drift window absorbs clock skew.
  @totp_period 30

  @doc """
  Generates a fresh TOTP secret, stores it cloak-encrypted and resets enrollment
  (so a re-run forces re-confirmation). Returns `{:ok, admin, secret}` — the raw
  `secret` is the *only* time it leaves the boundary, for QR provisioning.
  """
  def setup_totp(%Admin{} = admin) do
    secret = NimbleTOTP.secret()

    admin
    |> Ecto.Changeset.change(
      totp_secret_enc: secret,
      totp_confirmed_at: nil,
      totp_last_used_at: nil
    )
    |> Repo.update()
    |> case do
      {:ok, admin} -> {:ok, admin, secret}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  Builds the `otpauth://` provisioning URI. The issuer/account label comes from
  `Settings.display_name/0` so the brand stays configuration-driven (Phase 0),
  never a hardcoded string.
  """
  def totp_provisioning_uri(%Admin{email: email}, secret) when is_binary(secret) do
    issuer = Settings.display_name()
    NimbleTOTP.otpauth_uri("#{issuer}:#{email}", secret, issuer: issuer)
  end

  @doc "Renders `uri` as an inline SVG QR code (XML prolog stripped for HTML embedding)."
  def totp_qr_svg(uri) when is_binary(uri) do
    uri
    |> EQRCode.encode()
    |> EQRCode.svg(width: 240)
    |> String.replace_prefix(~s(<?xml version="1.0" standalone="yes"?>), "")
  end

  @doc """
  Confirms enrollment: if `code` matches the stored secret, stamps
  `totp_confirmed_at` and seeds the replay guard so the enrollment code itself
  cannot be reused. Returns `{:ok, admin}` or `{:error, :invalid_code}`.
  """
  def activate_totp(%Admin{totp_secret_enc: secret} = admin, code) when is_binary(secret) do
    case accepted_at(admin, code) do
      nil ->
        {:error, :invalid_code}

      used_at ->
        admin
        |> Ecto.Changeset.change(
          totp_confirmed_at: DateTime.truncate(DateTime.utc_now(), :second),
          totp_last_used_at: used_at
        )
        |> Repo.update()
    end
  end

  def activate_totp(_admin, _code), do: {:error, :invalid_code}

  @doc "True once TOTP enrollment has been confirmed."
  def totp_enrolled?(%Admin{totp_confirmed_at: nil}), do: false
  def totp_enrolled?(%Admin{}), do: true

  @doc """
  Verifies a login `code` against the stored secret with a ±1 step drift window,
  rejecting any code from a period at or before the last accepted one (replay
  guard). Pure predicate — does not persist; `verify_totp/2` records acceptance.
  """
  def valid_totp?(%Admin{} = admin, code) when is_binary(code),
    do: accepted_at(admin, code) != nil

  def valid_totp?(_admin, _code), do: false

  @doc """
  Verifies a login `code` and, on success, advances the replay guard to the
  accepted code's period so it cannot be reused. Returns `{:ok, admin}` or
  `:error`.
  """
  def verify_totp(%Admin{} = admin, code) do
    case accepted_at(admin, code) do
      nil ->
        :error

      used_at ->
        admin
        |> Ecto.Changeset.change(totp_last_used_at: used_at)
        |> Repo.update()
    end
  end

  # Returns the (second-precision) `DateTime` of the period the code matched —
  # searching a ±1 step drift window and honouring the replay guard — or nil. The
  # matched period (not wall-clock now) is what gets recorded, so a code accepted
  # via drift blocks only itself, never a legitimately newer one.
  defp accepted_at(%Admin{totp_secret_enc: secret, totp_last_used_at: since}, code)
       when is_binary(secret) and is_binary(code) do
    now = System.os_time(:second)

    case Enum.find([now, now - @totp_period, now + @totp_period], fn time ->
           NimbleTOTP.valid?(secret, code, time: time, since: since, period: @totp_period)
         end) do
      nil -> nil
      unix -> DateTime.truncate(DateTime.from_unix!(unix), :second)
    end
  end

  defp accepted_at(_admin, _code), do: nil
end
