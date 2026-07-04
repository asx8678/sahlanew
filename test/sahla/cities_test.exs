defmodule Sahla.CitiesTest do
  use Sahla.DataCase, async: true

  alias Sahla.Cities
  alias Sahla.Cities.City

  defp insert_city(attrs) do
    %City{}
    |> City.changeset(Map.merge(%{name_ar: "مدينة", region: "Casablanca-Settat"}, Map.new(attrs)))
    |> Repo.insert!()
  end

  describe "risk_zone validation" do
    test "accepts zones 1..3" do
      for zone <- 1..3 do
        assert {:ok, _} =
                 %City{}
                 |> City.changeset(%{
                   name_fr: "Ville-#{zone}",
                   name_ar: "م",
                   region: "R",
                   risk_zone: zone
                 })
                 |> Repo.insert()
      end
    end

    test "rejects an out-of-range zone at the changeset boundary" do
      changeset =
        City.changeset(%City{}, %{name_fr: "X", name_ar: "م", region: "R", risk_zone: 4})

      assert %{risk_zone: ["is invalid"]} = errors_on(changeset)
    end

    test "DB CHECK constraint backstops an out-of-range zone via raw SQL" do
      assert_raise Postgrex.Error, ~r/cities_risk_zone_must_be_valid/, fn ->
        Repo.query!(
          """
          INSERT INTO cities (id, name_fr, name_ar, region, risk_zone, inserted_at, updated_at)
          VALUES (gen_random_uuid(), 'Bad', 'م', 'R', 5, now(), now())
          """,
          []
        )
      end
    end
  end

  describe "name_fr uniqueness" do
    test "rejects a duplicate name_fr" do
      insert_city(%{name_fr: "Casablanca", risk_zone: 3})

      assert {:error, changeset} =
               %City{}
               |> City.changeset(%{
                 name_fr: "Casablanca",
                 name_ar: "م",
                 region: "R",
                 risk_zone: 2
               })
               |> Repo.insert()

      assert %{name_fr: ["has already been taken"]} = errors_on(changeset)
    end
  end

  describe "context boundary" do
    test "list_cities/0 orders by name_fr ascending" do
      insert_city(%{name_fr: "Tanger", risk_zone: 2})
      insert_city(%{name_fr: "Agadir", risk_zone: 1})
      insert_city(%{name_fr: "Marrakech", risk_zone: 2})

      assert Enum.map(Cities.list_cities(), & &1.name_fr) == ["Agadir", "Marrakech", "Tanger"]
    end

    test "get_risk_zone/1 returns the zone, or nil for an unknown city" do
      city = insert_city(%{name_fr: "Rabat", risk_zone: 1})

      assert Cities.get_risk_zone(city.id) == 1
      assert Cities.get_risk_zone(Ecto.UUID.generate()) == nil
    end
  end
end
