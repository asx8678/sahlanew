defmodule Sahla.Repo.Migrations.CreateGuarantees do
  use Ecto.Migration

  @codes ~w(rc vol incendie bris_glace pta defense_recours assistance individuelle evenements_climatiques evcat)

  def change do
    create table(:guarantees) do
      add :code, :string, null: false
      add :name_fr, :string, null: false
      add :name_ar, :string, null: false
      add :description_fr, :text
      add :description_ar, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index(:guarantees, [:code])

    codes = Enum.map_join(@codes, ",", &"'#{&1}'")

    create constraint(:guarantees, :guarantees_code_must_be_valid, check: "code IN (#{codes})")
  end
end
