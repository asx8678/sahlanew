defmodule Sahla.Rating.CRMTest do
  use ExUnit.Case, async: true

  alias Sahla.Rating.CRM

  @table %{
    "start" => 1.0,
    "floor" => 0.5,
    "ceiling" => 2.5,
    "clean_year_factor" => 0.9,
    "claim_factor" => 1.2
  }

  @today ~D[2026-01-01]

  defp coeff(inputs), do: CRM.coefficient(Map.put(inputs, :today, @today), @table)

  describe "known CRM" do
    test "is returned as :known, clamped into [floor, ceiling]" do
      assert {value, :known} = coeff(%{crm: Decimal.new("1.10")})
      assert Decimal.equal?(value, Decimal.new("1.10"))
    end

    test "clamps a value above the ceiling and below the floor" do
      assert {high, :known} = coeff(%{crm: Decimal.new("9.99")})
      assert Decimal.equal?(high, Decimal.new("2.50"))

      assert {low, :known} = coeff(%{crm: Decimal.new("0.10")})
      assert Decimal.equal?(low, Decimal.new("0.50"))
    end
  end

  describe "estimated CRM" do
    test "unknown crm derives from license_date + claims and flags :estimated" do
      assert {_value, :estimated} =
               coeff(%{license_date: ~D[2024-01-01], at_fault_claims_36m: 0})
    end

    test "~10 clean years bottoms out at the 0.50 floor" do
      # licensed since 2016 -> 10 years; 0.9^10 = 0.35 -> floored to 0.50
      assert {value, :estimated} =
               coeff(%{license_date: ~D[2016-01-01], at_fault_claims_36m: 0})

      assert Decimal.equal?(value, Decimal.new("0.50"))
    end

    test "two clean years reduce below the 1.0 start" do
      assert {value, :estimated} =
               coeff(%{license_date: ~D[2024-01-01], at_fault_claims_36m: 0})

      # 1.0 * 0.9^2 = 0.81
      assert Decimal.equal?(value, Decimal.new("0.81"))
    end

    test "at-fault claims raise the coefficient monotonically and never below clean history" do
      base = %{license_date: ~D[2020-01-01]}
      {clean, _} = coeff(Map.put(base, :at_fault_claims_36m, 0))
      {one, _} = coeff(Map.put(base, :at_fault_claims_36m, 1))
      {two, _} = coeff(Map.put(base, :at_fault_claims_36m, 2))

      assert Decimal.compare(one, clean) == :gt
      assert Decimal.compare(two, one) == :gt
      # never drops below the clean-history equivalent
      assert Decimal.compare(one, clean) != :lt
    end

    test "the ceiling caps a heavy claims history" do
      assert {value, :estimated} =
               coeff(%{license_date: ~D[2025-06-01], at_fault_claims_36m: 20})

      assert Decimal.equal?(value, Decimal.new("2.50"))
    end
  end

  describe "table-driven (nothing hard-coded)" do
    test "swapping the table changes the derived result" do
      gentle = %{@table | "clean_year_factor" => 0.95}
      inputs = %{license_date: ~D[2022-01-01], at_fault_claims_36m: 0, today: @today}

      {default, _} = CRM.coefficient(inputs, @table)
      {softer, _} = CRM.coefficient(inputs, gentle)

      # a milder reduction factor yields a higher coefficient for the same tenure
      assert Decimal.compare(softer, default) == :gt
    end
  end
end
