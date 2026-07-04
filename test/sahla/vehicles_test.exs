defmodule Sahla.VehiclesTest do
  use Sahla.DataCase, async: true

  alias Sahla.Vehicles
  alias Sahla.Vehicles.{Make, Model, Version}

  defp insert_make(attrs \\ %{}) do
    %Make{}
    |> Make.changeset(
      Map.merge(%{name: "Make-#{System.unique_integer([:positive])}"}, Map.new(attrs))
    )
    |> Repo.insert!()
  end

  defp insert_model(make, attrs \\ %{}) do
    %Model{}
    |> Model.changeset(
      Map.merge(
        %{make_id: make.id, name: "Model-#{System.unique_integer([:positive])}"},
        Map.new(attrs)
      )
    )
    |> Repo.insert!()
  end

  defp insert_version(model, attrs) do
    %Version{}
    |> Version.changeset(
      Map.merge(
        %{model_id: model.id, name: "V-#{System.unique_integer([:positive])}"},
        Map.new(attrs)
      )
    )
    |> Repo.insert!()
  end

  describe "fuel enum" do
    test "rejects an invalid fuel at the changeset boundary" do
      model = insert_model(insert_make())

      changeset =
        Version.changeset(%Version{}, %{model_id: model.id, name: "GT", fuel: :kerosene})

      assert %{fuel: ["is invalid"]} = errors_on(changeset)
    end

    test "accepts each valid fuel" do
      model = insert_model(insert_make())

      for fuel <- Version.fuels() do
        assert {:ok, _} =
                 %Version{}
                 |> Version.changeset(%{model_id: model.id, name: "V-#{fuel}", fuel: fuel})
                 |> Repo.insert()
      end
    end
  end

  describe "years int4range" do
    test "round-trips an inclusive Elixir range" do
      model = insert_model(insert_make())
      version = insert_version(model, %{name: "2015-2020", years: 2015..2020})

      assert Repo.get!(Version, version.id).years == 2015..2020
    end

    test "containment query returns only versions whose span covers the year" do
      model = insert_model(insert_make())
      early = insert_version(model, %{name: "early", years: 2010..2014})
      spanning = insert_version(model, %{name: "spanning", years: 2013..2018})

      ids_2014 = Enum.map(Vehicles.versions_for_model_in_year(model.id, 2014), & &1.id)
      assert early.id in ids_2014
      assert spanning.id in ids_2014

      ids_2017 = Enum.map(Vehicles.versions_for_model_in_year(model.id, 2017), & &1.id)
      assert ids_2017 == [spanning.id]
    end
  end

  describe "FK chain and cascade" do
    test "deleting a make cascades to its models and versions" do
      make = insert_make()
      model = insert_model(make)
      version = insert_version(model, %{name: "GT"})

      Repo.delete!(make)

      refute Repo.get(Model, model.id)
      refute Repo.get(Version, version.id)
    end

    test "model requires an existing make" do
      assert {:error, changeset} =
               %Model{}
               |> Model.changeset(%{make_id: Ecto.UUID.generate(), name: "Ghost"})
               |> Repo.insert()

      assert %{make: ["does not exist"]} = errors_on(changeset)
    end
  end

  describe "context queries" do
    test "list_makes/0 orders popular first, then alphabetical" do
      insert_make(%{name: "Zeta", popular: false})
      insert_make(%{name: "Alpha", popular: false})
      insert_make(%{name: "Yamaha", popular: true})

      # Sandbox isolation means these three are the only makes in this test.
      assert Enum.map(Vehicles.list_makes(), & &1.name) == ["Yamaha", "Alpha", "Zeta"]
    end

    test "fiscal_power_for_version/1 fetches just the fiscal power" do
      model = insert_model(insert_make())
      version = insert_version(model, %{name: "GT", fiscal_power: 8})

      assert Vehicles.fiscal_power_for_version(version.id) == 8
      assert Vehicles.fiscal_power_for_version(Ecto.UUID.generate()) == nil
    end
  end
end
