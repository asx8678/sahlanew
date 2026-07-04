defmodule Sahla.Vehicles.ImportTest do
  use Sahla.DataCase, async: true
  use Oban.Testing, repo: Sahla.Repo

  alias Sahla.Vehicles.{Import, Make, Model, Version}
  alias Sahla.Vehicles.Workers.VehicleImport

  @header "make,model,version,fiscal_power,fuel,seats,new_value_centimes,year_from,year_to,popular"

  defp csv(rows), do: Enum.join([@header | rows], "\n")

  describe "import_csv/1" do
    test "creates makes/models/versions and parses ints, fuel and the year range" do
      csv =
        csv([
          "Renault,Clio,1.5 dCi,5,diesel,5,18000000,2015,2020,true",
          "Renault,Megane,1.6,6,essence,5,25000000,,"
        ])

      summary = Import.import_csv(csv)

      assert summary.makes_created == 1
      assert summary.models_created == 2
      assert summary.versions_inserted == 2
      assert summary.failed == 0

      version = Repo.get_by!(Version, name: "1.5 dCi")
      assert version.fiscal_power == 5
      assert version.fuel == :diesel
      assert version.seats == 5
      assert version.new_value_centimes == 18_000_000
      # stored as int4range, surfaced as an inclusive Elixir range
      assert version.years == 2015..2020

      assert Repo.get_by!(Make, name: "Renault").popular == true
      assert Repo.get_by!(Version, name: "1.6").years == nil
    end

    test "re-running the same file is idempotent (updates, no duplicates)" do
      csv = csv(["Renault,Clio,1.5 dCi,5,diesel,5,18000000,2015,2020,false"])

      _first = Import.import_csv(csv)
      second = Import.import_csv(csv)

      assert second.makes_created == 0
      assert second.models_created == 0
      assert second.versions_inserted == 0
      assert second.versions_updated == 1

      assert Repo.aggregate(Make, :count) == 1
      assert Repo.aggregate(Model, :count) == 1
      assert Repo.aggregate(Version, :count) == 1
    end

    test "a mixed valid/invalid file commits the good rows and reports the bad ones" do
      csv =
        csv([
          "Renault,Clio,1.5 dCi,5,diesel,5,18000000,2015,2020,true",
          "Peugeot,208,1.2,4,kerosene,5,,,",
          ",Model,Version,4,essence,5,,,",
          "Fiat,500,Lounge,3,essence,4,abc,,",
          "Dacia,Duster,1.5,6,diesel,5,,,"
        ])

      summary = Import.import_csv(csv)

      # the two valid rows (first and last) commit around the three bad ones
      assert summary.versions_inserted == 2
      assert summary.failed == 3

      reasons = Enum.map(summary.errors, & &1.error)
      assert Enum.at(summary.errors, 0).row == 2
      assert Enum.any?(reasons, &(&1 =~ "unknown fuel: kerosene"))
      assert Enum.any?(reasons, &(&1 =~ "missing make"))
      assert Enum.any?(reasons, &(&1 =~ "invalid integer for new_value_centimes"))

      assert Repo.aggregate(Version, :count) == 2
    end

    test "a half-specified year span is a row-level error" do
      csv = csv(["Renault,Clio,1.5 dCi,5,diesel,5,,2020,"])

      summary = Import.import_csv(csv)

      assert summary.failed == 1
      assert [%{row: 1, error: error}] = summary.errors
      assert error =~ "year_from and year_to must both be set"
    end
  end

  describe "VehicleImport worker" do
    test "runs in the imports queue and returns the summary" do
      assert VehicleImport.new(%{"csv" => ""}).changes.queue == "imports"

      csv = csv(["Renault,Clio,1.5 dCi,5,diesel,5,18000000,2015,2020,true"])

      assert {:ok, summary} = perform_job(VehicleImport, %{"csv" => csv})
      assert summary.versions_inserted == 1
      assert Repo.aggregate(Version, :count) == 1
    end
  end
end
