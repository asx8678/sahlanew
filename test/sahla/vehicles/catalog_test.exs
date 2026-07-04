defmodule Sahla.Vehicles.CatalogTest do
  use Sahla.DataCase, async: true

  alias Sahla.Vehicles.Catalog
  alias Sahla.Vehicles.{Make, Model, Version}

  defp make(name, opts \\ []) do
    %Make{}
    |> Make.changeset(%{name: name, popular: Keyword.get(opts, :popular, false)})
    |> Repo.insert!()
  end

  defp model(make, name) do
    %Model{}
    |> Model.changeset(%{make_id: make.id, name: name})
    |> Repo.insert!()
  end

  defp version(model, name, attrs) do
    %Version{}
    |> Version.changeset(Map.merge(%{model_id: model.id, name: name}, attrs))
    |> Repo.insert!()
  end

  describe "search_makes/2" do
    test "matches case- and accent-insensitively" do
      make("Citroën")

      assert [%Make{name: "Citroën"}] = Catalog.search_makes("citroen")
      assert [%Make{name: "Citroën"}] = Catalog.search_makes("CITROËN")
    end

    test "ranks closer matches first, then popular, then name for ties" do
      # "Abc"/"Abd"/"Abe" all share the same trigram similarity to "ab",
      # so ordering falls through to popular desc then name asc.
      make("Abe", popular: false)
      make("Abd", popular: true)
      make("Abc", popular: false)

      assert Enum.map(Catalog.search_makes("ab"), & &1.name) == ["Abd", "Abc", "Abe"]
    end

    test "a closer match outranks a partial one" do
      make("Clio")
      make("Clio Estate")

      assert [%Make{name: "Clio"} | _] = Catalog.search_makes("clio")
    end

    test "empty or blank query returns []" do
      make("Renault")

      assert Catalog.search_makes("") == []
      assert Catalog.search_makes("   ") == []
      assert Catalog.search_makes(nil) == []
    end

    test "no match returns []" do
      make("Renault")
      assert Catalog.search_makes("zzzq") == []
    end

    test "respects the result cap" do
      for i <- 1..15, do: make("Toyota #{i}")
      assert length(Catalog.search_makes("toyota")) == 10
      assert length(Catalog.search_makes("toyota", limit: 3)) == 3
    end
  end

  describe "search_models/3" do
    test "matches accent-insensitively and is scoped to the make" do
      renault = make("Renault")
      peugeot = make("Peugeot")
      model(renault, "Mégane")
      model(peugeot, "Mégane-lookalike")

      results = Catalog.search_models(renault.id, "megane")
      assert Enum.map(results, & &1.name) == ["Mégane"]
    end
  end

  describe "search_versions/3" do
    test "is scoped to the model and carries prefill fields" do
      m = model(make("Renault"), "Mégane")
      other = model(make("Peugeot"), "308")
      version(m, "RS Trophy", %{fiscal_power: 10, fuel: :essence, seats: 5})
      version(other, "RS Clone", %{fiscal_power: 7, fuel: :diesel, seats: 5})

      assert [%Version{name: "RS Trophy", fiscal_power: 10, fuel: :essence, seats: 5}] =
               Catalog.search_versions(m.id, "rs")
    end
  end

  describe "index usage" do
    test "model search uses the unaccent trigram GIN index when seq scans are off" do
      renault = make("Renault")
      for i <- 1..40, do: model(renault, "Model #{i}")

      Repo.query!("SET LOCAL enable_seqscan = off")

      %{rows: rows} =
        Repo.query!(
          "EXPLAIN SELECT * FROM vehicle_models WHERE sahla_unaccent(name) ILIKE sahla_unaccent($1)",
          ["%model%"]
        )

      plan = rows |> List.flatten() |> Enum.join("\n")
      assert plan =~ "vehicle_models_name_unaccent_trgm_idx"
    end
  end
end
