defmodule Sahla.Repo.Migrations.CreateVehicleModels do
  use Ecto.Migration

  import Sahla.Migration

  def change do
    create table(:vehicle_models) do
      add :make_id, references(:vehicle_makes, on_delete: :delete_all), null: false
      add :name, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:vehicle_models, [:make_id])
    create unique_index(:vehicle_models, [:make_id, :name])
    create trigram_index(:vehicle_models, :name)
  end
end
