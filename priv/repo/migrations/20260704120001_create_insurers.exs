defmodule Sahla.Repo.Migrations.CreateInsurers do
  use Ecto.Migration

  def change do
    create table(:insurers) do
      add :slug, :string, null: false
      add :name_fr, :string, null: false
      add :name_ar, :string, null: false
      add :logo_path, :string
      add :acaps_ref, :string
      add :phone, :string
      add :rating, :decimal, precision: 2, scale: 1
      add :active, :boolean, null: false, default: false
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:insurers, [:slug])
  end
end
