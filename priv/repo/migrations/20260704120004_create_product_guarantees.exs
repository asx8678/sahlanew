defmodule Sahla.Repo.Migrations.CreateProductGuarantees do
  use Ecto.Migration

  def change do
    create table(:product_guarantees) do
      add :product_id, references(:products, on_delete: :delete_all), null: false
      # guarantee_code references guarantees.code (a string column), so this FK
      # overrides the repo-default binary_id foreign-key type.
      add :guarantee_code,
          references(:guarantees, column: :code, type: :string, on_delete: :restrict),
          null: false

      add :included, :boolean, null: false, default: true
      add :ceiling_centimes, :integer
      add :franchise_centimes, :integer
      add :notes_fr, :text
      add :notes_ar, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index(:product_guarantees, [:product_id, :guarantee_code])
    create index(:product_guarantees, [:guarantee_code])
  end
end
