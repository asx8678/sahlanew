defmodule Sahla.SeedsTest do
  # async: false — evaluates the seed script, which touches many global tables.
  use Sahla.DataCase, async: false

  import ExUnit.CaptureIO

  alias Sahla.Cities.City
  alias Sahla.Directory.{Guarantee, Insurer, Product, ProductGuarantee}
  alias Sahla.Vehicles.{Catalog, Make, Version}

  @seed Path.expand("../../priv/repo/seeds/seeds.exs", __DIR__)

  defp run_seed, do: capture_io(fn -> Code.eval_file(@seed) end)

  defp counts do
    %{
      insurers: Repo.aggregate(Insurer, :count),
      guarantees: Repo.aggregate(Guarantee, :count),
      products: Repo.aggregate(Product, :count),
      product_guarantees: Repo.aggregate(ProductGuarantee, :count),
      makes: Repo.aggregate(Make, :count),
      versions: Repo.aggregate(Version, :count),
      cities: Repo.aggregate(City, :count)
    }
  end

  test "seeds populate the catalog and are idempotent" do
    run_seed()
    first = counts()

    # 8 insurers, all 10 guarantee codes, 8×3 products, and a full matrix.
    assert first.insurers == 8
    assert first.guarantees == 10
    assert first.products == 24
    assert first.product_guarantees == 160
    # ~200 versions and ~20 cities per the plan.
    assert first.versions > 150
    assert first.cities == 20

    # Re-running creates no duplicates.
    run_seed()
    assert counts() == first
  end

  test "seeds leave a dataset the autocomplete API returns hits for, with valid risk zones" do
    run_seed()

    assert [%{name: "Renault"} | _] = Catalog.search_makes("rena")
    assert Enum.all?(Repo.all(City), &(&1.risk_zone in 1..3))
    # every product-guarantee ceiling/franchise is an integer-centimes value or nil
    assert Enum.all?(Repo.all(ProductGuarantee), fn pg ->
             is_nil(pg.ceiling_centimes) or is_integer(pg.ceiling_centimes)
           end)
  end
end
