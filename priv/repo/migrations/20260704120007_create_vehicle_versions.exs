defmodule Sahla.Repo.Migrations.CreateVehicleVersions do
  use Ecto.Migration

  import Sahla.Migration

  def change do
    create table(:vehicle_versions) do
      add :model_id, references(:vehicle_models, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :fiscal_power, :integer
      add :fuel, :string
      add :seats, :integer
      add :new_value_centimes, :integer
      add :years, :int4range

      timestamps(type: :utc_datetime)
    end

    create index(:vehicle_versions, [:model_id])
    create unique_index(:vehicle_versions, [:model_id, :name])
    create trigram_index(:vehicle_versions, :name)

    create constraint(:vehicle_versions, :vehicle_versions_fuel_must_be_valid,
             check: "fuel IN ('essence','diesel','hybride','electrique')"
           )
  end
end
