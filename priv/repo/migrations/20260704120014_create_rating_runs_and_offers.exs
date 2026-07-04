defmodule Sahla.Repo.Migrations.CreateRatingRunsAndOffers do
  use Ecto.Migration

  def change do
    create table(:rating_runs) do
      add :quote_id, references(:quotes, on_delete: :delete_all), null: false
      add :engine_version, :string, null: false
      add :table_versions, :map, null: false, default: %{}
      add :inputs, :map, null: false, default: %{}
      add :duration_us, :integer

      timestamps(type: :utc_datetime)
    end

    create index(:rating_runs, [:quote_id])

    create table(:offers) do
      add :rating_run_id, references(:rating_runs, on_delete: :delete_all), null: false
      add :quote_id, references(:quotes, on_delete: :delete_all), null: false
      add :insurer_id, references(:insurers, on_delete: :nilify_all)
      add :product_id, references(:products, on_delete: :nilify_all)
      add :formula, :string, null: false
      add :annual_premium_centimes, :integer, null: false
      add :monthly_equiv_centimes, :integer
      add :breakdown, :map, null: false, default: %{}
      add :badges, {:array, :string}, null: false, default: []
      add :rank, :integer
      add :selected_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:offers, [:quote_id])
    create index(:offers, [:rating_run_id])

    create constraint(:offers, :offers_formula_must_be_valid,
             check: "formula IN ('rc','tiers_etendu','tous_risques')"
           )

    # Wire the FKs deferred when quotes/leads were created (rating_runs/offers
    # did not exist yet).
    alter table(:quotes) do
      modify :rating_run_id, references(:rating_runs, on_delete: :nilify_all)
    end

    alter table(:leads) do
      modify :offer_id, references(:offers, on_delete: :nilify_all)
    end
  end
end
