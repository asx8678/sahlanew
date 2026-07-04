defmodule Sahla.Money do
  @moduledoc """
  Helpers for the project's money representation: **integer centimes (MAD)**.

  All monetary amounts are stored as integers of centimes (1 MAD = 100 centimes)
  in `*_centimes` columns — never floats, so arithmetic is exact. These helpers
  convert to and from human-facing MAD amounts and produce a plain display
  string. Locale-specific formatting (Western digits under Arabic, grouping) is
  the job of `ex_cldr_numbers`; this module stays dependency-light.
  """

  @centimes_per_mad 100

  @doc """
  Converts integer `centimes` to a `Decimal` amount in MAD.

      iex> Sahla.Money.to_mad(198_000)
      Decimal.new("1980.00")
  """
  def to_mad(centimes) when is_integer(centimes) do
    centimes
    |> Decimal.new()
    |> Decimal.div(@centimes_per_mad)
    |> Decimal.round(2)
  end

  @doc """
  Converts a MAD `amount` to integer centimes, rounding to the nearest centime.

  Accepts a `Decimal`, an integer, a float, or a numeric string.

      iex> Sahla.Money.from_mad("1980.00")
      198_000
      iex> Sahla.Money.from_mad(1980)
      198_000
  """
  def from_mad(%Decimal{} = amount) do
    amount
    |> Decimal.mult(@centimes_per_mad)
    |> Decimal.round(0)
    |> Decimal.to_integer()
  end

  def from_mad(amount) when is_integer(amount), do: amount * @centimes_per_mad

  def from_mad(amount) when is_float(amount) do
    amount |> Decimal.from_float() |> from_mad()
  end

  def from_mad(amount) when is_binary(amount) do
    amount |> Decimal.new() |> from_mad()
  end

  @doc """
  Formats integer `centimes` as a plain `"1980.00 MAD"` string.

  This is a neutral, non-localized rendering for logs and defaults; use
  `ex_cldr_numbers` for locale-aware, grouped display in the UI.
  """
  def format(centimes) when is_integer(centimes) do
    "#{Decimal.to_string(to_mad(centimes), :normal)} MAD"
  end
end
