defmodule Sahla.Repo.Migrations.CreateUnmatchedVehicles do
  use Ecto.Migration

  def change do
    create table(:unmatched_vehicles) do
      add :raw_make, :string
      add :raw_model, :string
      add :raw_version, :string
      # Normalized "make|model|version" for dedupe/upsert.
      add :dedup_key, :string, null: false
      add :fiscal_power, :integer
      add :fuel, :string
      add :occurrences, :integer, null: false, default: 1
      add :status, :string, null: false, default: "pending"
      add :resolved_version_id, references(:vehicle_versions, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:unmatched_vehicles, [:dedup_key])
    create index(:unmatched_vehicles, [:status])

    create constraint(:unmatched_vehicles, :unmatched_vehicles_status_must_be_valid,
             check: "status IN ('pending','resolved','ignored')"
           )
  end
end
