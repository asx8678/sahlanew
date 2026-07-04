defmodule Sahla.FormatTest do
  use ExUnit.Case, async: true

  alias Sahla.Format

  # Eastern-Arabic digits ٠١٢٣٤٥٦٧٨٩ (U+0660–U+0669) must never appear.
  @eastern ~r/[\x{0660}-\x{0669}]/u

  defp digits(string), do: String.replace(string, ~r/\D/u, "")

  describe "money/2" do
    test "formats centimes as grouped MAD in French" do
      formatted = Format.money(294_000, "fr")
      assert String.ends_with?(formatted, "MAD")
      assert digits(formatted) == "2940"
    end

    test "uses Western digits in Arabic (no Eastern-Arabic numerals)" do
      formatted = Format.money(294_000, "ar")
      assert String.ends_with?(formatted, "MAD")
      refute formatted =~ @eastern
      # same digits as French — only separators/direction may differ
      assert digits(formatted) == "2940"
    end
  end

  describe "number/2" do
    test "emits Western digits under locale=ar" do
      formatted = Format.number(1_234_567, "ar")
      refute formatted =~ @eastern
      assert digits(formatted) == "1234567"
    end
  end

  describe "date/2" do
    @date ~D[2026-07-04]

    test "formats with Western digits in French" do
      formatted = Format.date(@date, "fr")
      assert formatted =~ "2026"
      refute formatted =~ @eastern
    end

    test "formats with Western digits in Arabic, localizing month names" do
      fr = Format.date(@date, "fr")
      ar = Format.date(@date, "ar")

      assert ar =~ "2026"
      refute ar =~ @eastern
      # the localized rendering differs between locales (month name/order)
      refute ar == fr
    end
  end
end
