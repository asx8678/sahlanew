defmodule Sahla.MigrationTest do
  use ExUnit.Case, async: true

  import Sahla.Migration

  describe "trigram_index/3" do
    test "builds a GIN index with the gin_trgm_ops operator class" do
      index = trigram_index(:vehicle_models, :name)

      assert %Ecto.Migration.Index{} = index
      assert index.table == "vehicle_models"
      assert index.using == :gin
      assert index.columns == ["name gin_trgm_ops"]
    end

    test "derives a default index name from table and column" do
      # A string identifier (not an interpolated atom) — same SQL name.
      assert trigram_index(:vehicle_versions, :name).name == "vehicle_versions_name_trgm_idx"
    end

    test "accepts an explicit :name override" do
      assert trigram_index(:cities, :name_fr, name: :cities_name_fr_search).name ==
               :cities_name_fr_search
    end
  end
end
