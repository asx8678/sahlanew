defmodule Sahla.Accounts.Admin do
  @moduledoc """
  A back-office admin (§10, §12). Passwords are Argon2-hashed; `role` gates
  authorization; `session_version` is bumped on role change so existing sessions
  die on their next request. `totp_secret_enc` is cloak-encrypted (populated by
  the 2FA task).

  `role` and `active` are privileged fields — only the admin-management
  changesets touch them, never a user-facing path (Lessons).
  """
  use Sahla.Schema

  import Ecto.Changeset

  @roles [:superadmin, :ops, :agent, :editor, :finance]

  schema "admins" do
    field :email, :string
    field :password_hash, :string, redact: true
    field :password, :string, virtual: true, redact: true
    field :role, Ecto.Enum, values: @roles
    field :active, :boolean, default: true
    field :last_login_at, :utc_datetime
    field :totp_secret_enc, Sahla.Encrypted.Binary, redact: true
    # nil until enrollment is confirmed; drives the "forced setup" gate.
    field :totp_confirmed_at, :utc_datetime
    # Timestamp of the last accepted code — nimble_totp's `:since` replay guard.
    field :totp_last_used_at, :utc_datetime
    field :session_version, :integer, default: 0

    timestamps()
  end

  @doc "Valid admin roles."
  def roles, do: @roles

  @doc "Creates an admin, hashing the password with Argon2."
  def registration_changeset(admin, attrs) do
    admin
    |> cast(attrs, [:email, :password, :role])
    |> validate_required([:email, :password, :role])
    |> validate_email()
    |> validate_password()
    |> put_password_hash()
    |> check_constraint(:role, name: :admins_role_must_be_valid)
    |> unique_constraint(:email)
  end

  @doc "Changes an admin's password (re-hashed with Argon2)."
  def password_changeset(admin, attrs) do
    admin
    |> cast(attrs, [:password])
    |> validate_required([:password])
    |> validate_password()
    |> put_password_hash()
  end

  @doc """
  Changes an admin's `role` and bumps `session_version`, which invalidates every
  session token issued under the previous version.
  """
  def role_changeset(%__MODULE__{} = admin, new_role) do
    admin
    |> change(role: new_role, session_version: admin.session_version + 1)
    |> validate_inclusion(:role, @roles)
    |> check_constraint(:role, name: :admins_role_must_be_valid)
  end

  @doc """
  Verifies `password` against the admin's hash in constant time. Runs a dummy
  hash for a nil admin (unknown email) so timing does not leak account existence.
  """
  def valid_password?(admin, password)

  def valid_password?(%__MODULE__{password_hash: hash}, password)
      when is_binary(hash) and is_binary(password) and byte_size(password) > 0 do
    Argon2.verify_pass(password, hash)
  end

  def valid_password?(_admin, _password) do
    Argon2.no_user_verify()
    false
  end

  defp validate_email(changeset) do
    changeset
    |> update_change(:email, &String.downcase(String.trim(&1)))
    |> validate_format(:email, ~r/^[^@\s]+@[^@\s]+$/, message: "must be a valid email")
    |> validate_length(:email, max: 160)
  end

  defp validate_password(changeset) do
    validate_length(changeset, :password, min: 12, max: 72)
  end

  defp put_password_hash(changeset) do
    case get_change(changeset, :password) do
      nil ->
        changeset

      password ->
        changeset
        |> put_change(:password_hash, Argon2.hash_pwd_salt(password))
        |> delete_change(:password)
    end
  end
end
