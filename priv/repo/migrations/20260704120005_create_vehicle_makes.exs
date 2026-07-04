defmodule Sahla.Repo.Migrations.CreateVehicleMakes do
  use Ecto.Migration

  def change do
    create table(:vehicle_makes) do
      add :name, :string, null: false
      add :popular, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:vehicle_makes, [:name])
  end
end
