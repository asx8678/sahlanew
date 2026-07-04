defmodule Sahla.Repo.Migrations.CreateOtpCodes do
  use Ecto.Migration

  def change do
    create table(:otp_codes) do
      # Keyed HMAC of the phone (never raw); the code is stored only as a hash.
      add :phone_hash, :binary, null: false
      add :code_hash, :string, null: false
      add :attempts, :integer, null: false, default: 0
      add :expires_at, :utc_datetime, null: false
      add :used_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    # Latest-active lookup by phone: newest-first with an id tiebreaker (Lessons).
    create index(:otp_codes, ["phone_hash", "inserted_at DESC", "id DESC"],
             name: :otp_codes_phone_recency_index
           )

    create constraint(:otp_codes, :otp_codes_attempts_non_negative, check: "attempts >= 0")
  end
end
