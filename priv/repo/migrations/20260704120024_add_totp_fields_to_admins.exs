defmodule Sahla.Repo.Migrations.AddTotpFieldsToAdmins do
  use Ecto.Migration

  # `totp_confirmed_at` gates enrollment (nil = not yet enrolled → forced through
  # setup); `totp_last_used_at` is the replay guard (nimble_totp `:since`).
  def change do
    alter table(:admins) do
      add :totp_confirmed_at, :utc_datetime
      add :totp_last_used_at, :utc_datetime
    end
  end
end
