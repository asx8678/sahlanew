defmodule Sahla.Rating.SimulatorTest do
  # async: false — the read-only test seeds the global TableCache ETS.
  use Sahla.DataCase, async: false

  alias Sahla.Rating.{Simulator, Table, TableCache}

  # Published baseline table set (same shape the engine consumes).
  @baseline %{
    rc_base: %{
      "bands" => [
        %{"cv_min" => 1, "cv_max" => 10, "fuel" => "essence", "annual_centimes" => 200_000}
      ]
    },
    usage_factor: %{"factors" => %{"personnel" => 1.0}},
    city_factor: %{"factors" => %{"2" => 1.0}},
    crm: %{
      "start" => 1.0,
      "floor" => 0.5,
      "ceiling" => 2.5,
      "clean_year_factor" => 0.9,
      "claim_factor" => 1.2
    },
    option_pricing: %{"options" => %{"vol" => %{"annual_centimes" => 12_000}}},
    insurer_positioning: %{
      "wafa" => %{"tous_risques" => 1.0},
      "axa" => %{"tous_risques" => 1.0}
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

  defp inputs(overrides \\ %{}) do
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
        at_fault_claims_36m: 0,
        today: ~D[2026-01-01],
        catalog: @catalog
      },
      overrides
    )
  end

  describe "run_profile/3" do
    test "an empty draft yields zero deltas (new == old for every line)" do
      diffs = Simulator.run_profile(inputs(), %{}, baseline: @baseline)

      assert length(diffs) == 2

      for d <- diffs do
        assert d.old_centimes == d.new_centimes
        assert d.delta_centimes == 0
        assert d.pct == 0.0
      end
    end

    test "a draft returns old/new/delta/pct per insurer×formula" do
      # double the usage factor -> premiums rise for both insurers
      draft = %{usage_factor: %{"factors" => %{"personnel" => 2.0}}}
      diffs = Simulator.run_profile(inputs(), draft, baseline: @baseline)

      for d <- diffs do
        assert d.new_centimes > d.old_centimes
        assert d.delta_centimes == d.new_centimes - d.old_centimes
        assert d.pct > 0.0
      end
    end

    test "a draft overlay affects only its own code; other insurers keep published rows" do
      # change only wafa's positioning; axa's premium must be untouched
      draft = %{
        insurer_positioning: %{
          "wafa" => %{"tous_risques" => 0.5},
          "axa" => %{"tous_risques" => 1.0}
        }
      }

      diffs = Simulator.run_profile(inputs(), draft, baseline: @baseline)
      by_insurer = Map.new(diffs, &{&1.insurer, &1})

      assert by_insurer["wafa"].delta_centimes < 0
      assert by_insurer["axa"].delta_centimes == 0
    end
  end

  describe "run_batch/3" do
    test "returns an aggregate plus per-persona diffs" do
      personas = [inputs(), inputs(%{usage: :personnel, fiscal_power: 6})]
      draft = %{usage_factor: %{"factors" => %{"personnel" => 1.5}}}

      result = Simulator.run_batch(personas, draft, baseline: @baseline)

      assert result.aggregate.personas == 2
      # 2 personas × 2 insurers
      assert result.aggregate.lines == 4

      assert result.aggregate.total_delta_centimes ==
               result.aggregate.total_new_centimes - result.aggregate.total_old_centimes

      assert length(result.personas) == 2
      assert Enum.all?(result.personas, &(length(&1.diffs) == 2))
    end
  end

  # A content-valid published set (satisfies Table.changeset validation, unlike
  # the minimal @baseline used for the pure diff tests).
  @published %{
    rc_base: %{
      "bands" => [
        %{"cv_min" => 1, "cv_max" => 6, "fuel" => "essence", "annual_centimes" => 198_000}
      ]
    },
    usage_factor: %{"factors" => %{"personnel" => 1.0, "professionnel" => 1.2}},
    city_factor: %{"factors" => %{"1" => 0.9, "2" => 1.0, "3" => 1.15}},
    crm: %{
      "start" => 1.0,
      "floor" => 0.5,
      "ceiling" => 2.5,
      "clean_year_factor" => 0.9,
      "claim_factor" => 1.2
    },
    option_pricing: %{"options" => %{"vol" => %{"annual_centimes" => 5000}}},
    insurer_positioning: %{"wafa" => %{"rc" => 1.06, "tous_risques" => 0.97}},
    taxes_fees: %{
      "tax_rate" => 0.14,
      "fixed_fees_centimes" => 5000,
      "evcat" => %{"rate" => 0.05, "min_centimes" => 3000}
    }
  }

  describe "read-only guarantee" do
    setup do
      on_exit(fn -> TableCache.clear() end)

      for {code, data} <- @published do
        %Table{}
        |> Table.publish_changeset(%{
          code: code,
          version: 1,
          data: data,
          status: :published,
          effective_from: ~D[2026-01-01]
        })
        |> Repo.insert!()
      end

      TableCache.refresh()
      :ok
    end

    test "run_profile resolves the published baseline and writes nothing" do
      count_before = Repo.aggregate(Table, :count)

      draft = %{usage_factor: %{"factors" => %{"personnel" => 2.0}}}

      diffs =
        Simulator.run_profile(inputs(%{today: ~D[2026-06-01]}), draft, on_date: ~D[2026-06-01])

      # the offers were computed from the real published set...
      assert length(diffs) == 2
      assert Enum.any?(diffs, &(&1.delta_centimes > 0))

      # ...and nothing was written or published/archived.
      assert Repo.aggregate(Table, :count) == count_before
      assert Repo.all(from t in Table, where: t.status != :published) == []
    end
  end
end
