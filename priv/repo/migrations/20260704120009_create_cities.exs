defmodule Sahla.Repo.Migrations.CreateCities do
  use Ecto.Migration

  def change do
    create table(:cities) do
      add :name_fr, :string, null: false
      add :name_ar, :string, null: false
      add :region, :string, null: false
      add :risk_zone, :smallint, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:cities, [:name_fr])

    create constraint(:cities, :cities_risk_zone_must_be_valid,
             check: "risk_zone BETWEEN 1 AND 3"
           )
  end
end
