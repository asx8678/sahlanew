defmodule Sahla.Repo.Migrations.CreateRateTables do
  use Ecto.Migration

  @codes ~w(rc_base usage_factor city_factor crm option_pricing insurer_positioning taxes_fees)

  def change do
    create table(:rate_tables) do
      add :code, :string, null: false
      add :version, :integer, null: false
      add :status, :string, null: false, default: "draft"
      add :effective_from, :date
      add :data, :map, null: false, default: %{}
      add :checksum, :string, null: false
      add :notes, :text
      # FK to admins added when the admins table exists (r5o.3).
      add :published_by_id, :binary_id

      timestamps(type: :utc_datetime)
    end

    create unique_index(:rate_tables, [:code, :version])

    codes = Enum.map_join(@codes, ",", &"'#{&1}'")

    create constraint(:rate_tables, :rate_tables_code_must_be_valid, check: "code IN (#{codes})")

    create constraint(:rate_tables, :rate_tables_status_must_be_valid,
             check: "status IN ('draft','published','archived')"
           )
  end
end
