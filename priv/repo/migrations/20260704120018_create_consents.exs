defmodule Sahla.Repo.Migrations.CreateConsents do
  use Ecto.Migration

  def change do
    create table(:consents) do
      add :quote_id, references(:quotes, on_delete: :delete_all), null: false
      add :kind, :string, null: false
      add :text_version, :string, null: false
      add :granted, :boolean, null: false, default: false
      add :ip, :inet
      add :granted_at, :utc_datetime, null: false
      # Non-PII extras only (passed through SafeRaw before storage).
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    # One current consent per (quote, kind); re-capture upserts.
    create unique_index(:consents, [:quote_id, :kind])

    create constraint(:consents, :consents_kind_must_be_valid,
             check: "kind IN ('cgu','transmission','marketing')"
           )
  end
end
