defmodule Sahla.Repo.Migrations.CreateQuotes do
  use Ecto.Migration

  def change do
    create table(:quotes) do
      add :token, :citext, null: false
      add :status, :string, null: false, default: "draft"
      add :current_step, :integer, null: false, default: 1
      add :locale, :string, null: false, default: "fr"

      # Vehicle
      add :plate, :string
      add :is_new_ww, :boolean, null: false, default: false
      add :make_id, references(:vehicle_makes, on_delete: :nilify_all)
      add :model_id, references(:vehicle_models, on_delete: :nilify_all)
      add :version_id, references(:vehicle_versions, on_delete: :nilify_all)
      add :fiscal_power, :integer
      add :fuel, :string
      add :first_registration, :date
      add :vehicle_value_centimes, :integer
      add :usage, :string
      add :city_id, references(:cities, on_delete: :nilify_all)
      add :parking, :string

      # Driver
      add :birth_date, :date
      add :license_date, :date
      add :is_public_servant, :boolean, null: false, default: false
      add :current_insurer_id, references(:insurers, on_delete: :nilify_all)
      add :current_expiry, :date
      add :at_fault_claims_36m, :integer
      add :crm, :decimal, precision: 3, scale: 2
      add :releve_doc_path, :string

      # Coverage
      add :formula, :string
      add :options, {:array, :string}, null: false, default: []
      add :franchise_pref, :string
      add :effect_date, :date

      # Contact (nullable until step 4)
      add :first_name, :string
      add :last_name, :string
      add :phone_enc, :binary
      add :phone_hash, :binary
      add :email, :citext
      add :phone_verified_at, :utc_datetime

      # Context
      add :utm, :map, null: false, default: %{}
      add :ip, :inet
      add :user_agent, :string
      # FK to rating_runs added when that table exists (8vo.6).
      add :rating_run_id, :binary_id

      timestamps(type: :utc_datetime)
    end

    create unique_index(:quotes, [:token])
    create index(:quotes, [:phone_hash])

    create constraint(:quotes, :quotes_status_must_be_valid,
             check: "status IN ('draft','completed','expired')"
           )

    create constraint(:quotes, :quotes_usage_must_be_valid,
             check:
               "usage IS NULL OR usage IN ('personnel','trajet_domicile_travail','professionnel','taxi_vtc')"
           )

    create constraint(:quotes, :quotes_parking_must_be_valid,
             check: "parking IS NULL OR parking IN ('garage','rue','parking_surveille')"
           )

    create constraint(:quotes, :quotes_formula_must_be_valid,
             check: "formula IS NULL OR formula IN ('rc','tiers_etendu','tous_risques')"
           )

    create constraint(:quotes, :quotes_franchise_pref_must_be_valid,
             check: "franchise_pref IS NULL OR franchise_pref IN ('basse','standard','elevee')"
           )
  end
end
