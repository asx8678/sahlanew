defmodule Sahla.Repo.Migrations.CreateAdmins do
  use Ecto.Migration

  def change do
    create table(:admins) do
      add :email, :citext, null: false
      add :password_hash, :string, null: false
      add :role, :string, null: false
      add :active, :boolean, null: false, default: true
      add :last_login_at, :utc_datetime
      add :totp_secret_enc, :binary
      add :session_version, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:admins, [:email])

    create constraint(:admins, :admins_role_must_be_valid,
             check: "role IN ('superadmin','ops','agent','editor','finance')"
           )
  end
end
