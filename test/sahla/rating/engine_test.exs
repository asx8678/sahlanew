defmodule Sahla.Rating.EngineTest do
  # No DataCase — the engine is pure and must run without Repo/sandbox.
  use ExUnit.Case, async: true

  alias Sahla.Rating.{Engine, Offer}

  @tables %{
    rc_base: %{
      "bands" => [
        %{"cv_min" => 1, "cv_max" => 6, "fuel" => "essence", "annual_centimes" => 200_000},
        %{"cv_min" => 7, "cv_max" => 10, "fuel" => "essence", "annual_centimes" => 300_000},
        %{"cv_min" => 1, "cv_max" => 10, "fuel" => "diesel", "annual_centimes" => 250_000}
      ]
    },
    usage_factor: %{"factors" => %{"personnel" => 1.0, "professionnel" => 1.2}},
    city_factor: %{"factors" => %{"1" => 0.9, "2" => 1.0, "3" => 1.2}},
    crm: %{
      "start" => 1.0,
      "floor" => 0.5,
      "ceiling" => 2.5,
      "clean_year_factor" => 0.9,
      "claim_factor" => 1.2
    },
    option_pricing: %{
      "options" => %{
        "vol" => %{"annual_centimes" => 12_000},
        "bris_glace" => %{"rate" => 0.002}
      }
    },
    insurer_positioning: %{
      "wafa" => %{"rc" => 1.05, "tous_risques" => 0.98, "fonctionnaire" => 0.90},
      "axa" => %{"tous_risques" => 1.10}
    },
    taxes_fees: %{
      "tax_rate" => 0.14,
      "fixed_fees_centimes" => 5000,
      "evcat" => %{"rate" => 0.05, "min_centimes" => 3000}
    }
  }

  @catalog [
    %{insurer: %{slug: "wafa", name_fr: "Wafa"}, product: %{formula: :tous_risques}},
    %{insurer: %{slug: "axa", name_fr: "AXA"}, product: %{formula: :tous_risques}}
  ]

  defp base_inputs(overrides \\ %{}) do
    Map.merge(
      %{
        fiscal_power: 6,
        fuel: :essence,
        usage: :personnel,
        risk_zone: 2,
        vehicle_value_centimes: 20_000_000,
        options: ["vol"],
        franchise_pref: :standard,
        crm: Decimal.new("1.00"),
        license_date: ~D[2024-01-01],
        at_fault_claims_36m: 0,
        today: ~D[2026-01-01],
        catalog: @catalog
      },
      overrides
    )
  end

  test "returns one offer per catalog entry, rounded to a whole dirham" do
    offers = Engine.run(base_inputs(), @tables)

    assert length(offers) == 2

    for offer <- offers do
      assert rem(offer.annual_premium_centimes, 100) == 0
      assert offer.annual_premium_centimes > 0
    end
  end

  test "breakdown lines sum exactly to the total for every offer" do
    for offer <- Engine.run(base_inputs(), @tables) do
      assert Offer.breakdown_total(offer) == offer.annual_premium_centimes
      assert offer.breakdown.total == offer.annual_premium_centimes
    end
  end

  test "an EVCAT line is always present and positive, even with no options" do
    for offer <- Engine.run(base_inputs(%{options: []}), @tables) do
      assert offer.breakdown.evcat > 0
    end
  end

  test "the substantive premium lines are never negative" do
    for offer <- Engine.run(base_inputs(), @tables) do
      assert offer.breakdown.rc >= 0
      assert offer.breakdown.evcat >= 0
      assert offer.breakdown.taxes >= 0
      assert offer.breakdown.fees >= 0
      assert Enum.all?(offer.breakdown.options, &(&1.annual_centimes >= 0))
    end
  end

  test "a known CRM produces a non-estimated offer; an unknown one is flagged estimated" do
    [known | _] = Engine.run(base_inputs(%{crm: Decimal.new("1.00")}), @tables)
    refute known.estimated?

    [estimated | _] = Engine.run(base_inputs(%{crm: nil}), @tables)
    assert estimated.estimated?
  end

  test "insurer positioning differentiates otherwise-identical offers" do
    [wafa, axa] = Engine.run(base_inputs(), @tables)
    # wafa tous_risques positioning 0.98 < axa 1.10, so wafa is cheaper
    assert wafa.annual_premium_centimes < axa.annual_premium_centimes
  end

  test "a missing band yields no offers instead of crashing" do
    # fiscal_power 99 matches no band
    assert Engine.run(base_inputs(%{fiscal_power: 99}), @tables) == []
  end

  test "an unpriced/unknown selected option contributes zero, not a crash" do
    offers = Engine.run(base_inputs(%{options: ["nonexistent_option"]}), @tables)
    assert length(offers) == 2

    for offer <- offers do
      assert [%{code: "nonexistent_option", annual_centimes: 0}] = offer.breakdown.options
    end
  end

  test "monotonicity: more at-fault claims never produce a cheaper premium" do
    clean = Engine.run(base_inputs(%{crm: nil, at_fault_claims_36m: 0}), @tables)
    claims = Engine.run(base_inputs(%{crm: nil, at_fault_claims_36m: 2}), @tables)

    Enum.zip(clean, claims)
    |> Enum.each(fn {c, k} ->
      assert k.annual_premium_centimes >= c.annual_premium_centimes
    end)
  end

  describe "fonctionnaire (public-sector) discount" do
    test "a fonctionnaire is cheaper at insurers carrying a fonctionnaire factor" do
      civilian = Engine.run(base_inputs(%{is_public_servant: false}), @tables)
      servant = Engine.run(base_inputs(%{is_public_servant: true}), @tables)

      wafa_civ = Enum.find(civilian, &(&1.insurer.slug == "wafa"))
      wafa_srv = Enum.find(servant, &(&1.insurer.slug == "wafa"))
      assert wafa_srv.annual_premium_centimes < wafa_civ.annual_premium_centimes

      # the reduced offer's breakdown still sums exactly to its total
      assert Offer.breakdown_total(wafa_srv) == wafa_srv.annual_premium_centimes
    end

    test "insurers with no fonctionnaire factor are unaffected by the flag" do
      civilian = Engine.run(base_inputs(%{is_public_servant: false}), @tables)
      servant = Engine.run(base_inputs(%{is_public_servant: true}), @tables)

      axa_civ = Enum.find(civilian, &(&1.insurer.slug == "axa"))
      axa_srv = Enum.find(servant, &(&1.insurer.slug == "axa"))
      assert axa_srv.annual_premium_centimes == axa_civ.annual_premium_centimes
    end

    test "the flag is ignored when false (identical to omitting it)" do
      omitted = Engine.run(base_inputs(), @tables)
      explicit_false = Engine.run(base_inputs(%{is_public_servant: false}), @tables)

      assert Enum.map(omitted, & &1.annual_premium_centimes) ==
               Enum.map(explicit_false, & &1.annual_premium_centimes)
    end

    test "property: the fonctionnaire flag never raises a premium across profiles" do
      for cv <- [4, 8], zone <- [1, 2, 3], usage <- [:personnel, :professionnel] do
        inputs = base_inputs(%{fiscal_power: cv, risk_zone: zone, usage: usage})
        civilian = Engine.run(Map.put(inputs, :is_public_servant, false), @tables)
        servant = Engine.run(Map.put(inputs, :is_public_servant, true), @tables)

        for {c, s} <- Enum.zip(civilian, servant) do
          assert s.annual_premium_centimes <= c.annual_premium_centimes
        end
      end
    end
  end
end
