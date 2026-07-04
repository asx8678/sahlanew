defmodule Sahla.Repo.Migrations.CreateSettings do
  use Ecto.Migration

  def change do
    create table(:settings) do
      add :key, :string, null: false
      # jsonb envelope `{"value": <any json>}` so scalars/arrays/objects all fit.
      add :value, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:settings, [:key])
  end
end
