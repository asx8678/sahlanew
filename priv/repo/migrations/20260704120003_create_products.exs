defmodule Sahla.Repo.Migrations.CreateProducts do
  use Ecto.Migration

  def change do
    create table(:products) do
      add :insurer_id, references(:insurers, on_delete: :restrict), null: false
      add :kind, :string, null: false
      add :formula, :string, null: false
      add :name_fr, :string, null: false
      add :name_ar, :string, null: false
      add :cg_document_path, :string
      add :installments_available, :boolean, null: false, default: false
      add :active, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create index(:products, [:insurer_id])

    create constraint(:products, :products_kind_must_be_valid,
             check: "kind IN ('auto','moto','voyage','habitation')"
           )

    create constraint(:products, :products_formula_must_be_valid,
             check: "formula IN ('rc','tiers_etendu','tous_risques')"
           )
  end
end
