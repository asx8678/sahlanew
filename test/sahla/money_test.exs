defmodule Sahla.MoneyTest do
  use ExUnit.Case, async: true

  alias Sahla.Money

  describe "to_mad/1" do
    test "converts centimes to a 2-decimal MAD amount" do
      assert Decimal.equal?(Money.to_mad(198_000), Decimal.new("1980.00"))
      assert Decimal.equal?(Money.to_mad(5000), Decimal.new("50.00"))
      assert Decimal.equal?(Money.to_mad(1), Decimal.new("0.01"))
      assert Decimal.equal?(Money.to_mad(0), Decimal.new("0.00"))
    end
  end

  describe "from_mad/1" do
    test "converts integers, floats, strings and decimals to centimes" do
      assert Money.from_mad(1980) == 198_000
      assert Money.from_mad(19.8) == 1980
      assert Money.from_mad("1980.00") == 198_000
      assert Money.from_mad(Decimal.new("50.55")) == 5055
    end

    test "rounds to the nearest centime" do
      assert Money.from_mad("10.005") == 1001
      assert Money.from_mad("10.004") == 1000
    end
  end

  describe "round-trip" do
    test "from_mad and to_mad are inverse for centime-aligned amounts" do
      for centimes <- [0, 1, 99, 100, 5000, 198_000] do
        assert Money.from_mad(Money.to_mad(centimes)) == centimes
      end
    end
  end

  describe "format/1" do
    test "renders a plain MAD string" do
      assert Money.format(198_000) == "1980.00 MAD"
      assert Money.format(50) == "0.50 MAD"
    end
  end
end
