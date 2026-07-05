defmodule Sahla.Rating.SeedsTest do
  # The ETS table cache and the seed script are global, so these tests run
  # sequentially and clear the cache on exit.
  use Sahla.DataCase, async: false

  alias Sahla.Rating.{Engine, Offer, Seeds, Table, TableCache, Tables}

  setup do
    on_exit(fn -> TableCache.clear() end)
    :ok
  end

  defp base_inputs(overrides \\ %{}) do
    today = ~D[2026-07-05]

    Map.merge(
      %{
        fiscal_power: 5,
        fuel: :essence,
        usage: :personnel,
        risk_zone: 2,
        vehicle_value_centimes: 20_000_000,
        options: ["vol", "incendie", "bris_glace", "defense_recours", "assistance"],
        franchise_pref: :standard,
        crm: nil,
        license_date: ~D[2011-01-01],
        at_fault_claims_36m: 0,
        today: today,
        is_public_servant: false,
        catalog: Seeds.build_catalog()
      },
      overrides
    )
  end

  defp in_mad_range?(offer, min_mad, max_mad) do
    mad = div(offer.annual_premium_centimes, 100)
    mad >= min_mad and mad <= max_mad
  end

  test "seeding produces exactly one published row for each table code" do
    :ok = Seeds.seed_placeholders()

    for code <- Table.codes() do
      assert Tables.resolve(code, Date.utc_today())

      assert Repo.aggregate(
               from(t in Table, where: t.code == ^code and t.status == :published),
               :count
             ) == 1
    end
  end

  test "re-running the seed is idempotent" do
    :ok = Seeds.seed_placeholders()

    first_counts =
      Map.new(Table.codes(), fn code ->
        {code,
         Repo.aggregate(
           from(t in Table, where: t.code == ^code and t.status == :published),
           :count
         )}
      end)

    :ok = Seeds.seed_placeholders()

    for code <- Table.codes() do
      assert Repo.aggregate(
               from(t in Table, where: t.code == ^code and t.status == :published),
               :count
             ) ==
               first_counts[code]
    end
  end

  test "engine returns 24 offers for a valid persona" do
    :ok = Seeds.seed_placeholders()
    offers = Engine.run(base_inputs(), Tables.load_all())

    assert length(offers) == 24

    for offer <- offers do
      assert offer.annual_premium_centimes > 0
      assert Offer.breakdown_total(offer) == offer.annual_premium_centimes
    end
  end

  test "median persona lands in the 3 500–5 500 MAD annual premium range" do
    :ok = Seeds.seed_placeholders()
    offers = Engine.run(base_inputs(), Tables.load_all())

    assert Enum.any?(offers, &in_mad_range?(&1, 3_500, 5_500))
    assert Enum.all?(offers, &in_mad_range?(&1, 3_000, 6_000))
  end

  test "old-car RC-only persona lands in the 1 600–2 500 MAD annual premium range" do
    :ok = Seeds.seed_placeholders()

    inputs =
      base_inputs(%{
        fiscal_power: 4,
        options: [],
        license_date: ~D[2008-01-01]
      })

    offers = Engine.run(inputs, Tables.load_all())

    assert Enum.any?(offers, &in_mad_range?(&1, 1_600, 2_500))
    assert Enum.all?(offers, &(&1.annual_premium_centimes > 0))
  end
end
