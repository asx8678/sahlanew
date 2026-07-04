defmodule Sahla.Repo.Migrations.CreateNotificationsLog do
  use Ecto.Migration

  def change do
    create table(:notifications_log) do
      add :channel, :string, null: false
      add :to_hash, :binary
      add :template, :string, null: false
      add :payload, :map, null: false, default: %{}
      add :provider_id, :string
      add :status, :string, null: false, default: "queued"
      add :cost_centimes, :integer
      add :sent_at, :utc_datetime
      add :idempotency_key, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:notifications_log, [:idempotency_key])
    create index(:notifications_log, [:to_hash])
    create index(:notifications_log, [:status])

    # Newest-first ordering with a second-precision tiebreaker (Lessons).
    create index(:notifications_log, ["sent_at DESC", "id DESC"],
             name: :notifications_log_recency_index
           )

    create constraint(:notifications_log, :notifications_log_channel_must_be_valid,
             check: "channel IN ('sms','email','whatsapp')"
           )

    create constraint(:notifications_log, :notifications_log_status_must_be_valid,
             check: "status IN ('queued','sent','delivered','failed')"
           )
  end
end
