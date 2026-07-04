defmodule Sahla.Format do
  @moduledoc """
  Locale-aware display formatting (§6.3) built on `Sahla.Cldr`.

  Moroccan convention keeps prices, plates and figures in **Western (Latin)
  digits even in Arabic**, so every helper forces `number_system: :latn`. Only
  separators, month names and date order localize — never the digit glyphs.
  Money is integer centimes MAD everywhere.
  """
  alias Sahla.Cldr.Date, as: CldrDate
  alias Sahla.Cldr.Number, as: CldrNumber

  @doc """
  Formats integer `centimes` as a MAD string with grouped, Western digits, e.g.
  `294_000` → `"2 940 MAD"` — identically digited in fr and ar.
  """
  def money(centimes, locale \\ "fr") when is_integer(centimes) do
    "#{number(div(centimes, 100), locale)} MAD"
  end

  @doc "Formats a number in `locale`, always with Western digits."
  def number(value, locale \\ "fr") do
    case CldrNumber.to_string(value, locale: locale, number_system: :latn) do
      {:ok, string} -> string
      {:error, _reason} -> to_string(value)
    end
  end

  @doc "Formats a date in `locale` (localized month names/order, Western digits)."
  def date(%Date{} = date, locale \\ "fr") do
    case CldrDate.to_string(date, locale: locale, number_system: :latn) do
      {:ok, string} -> string
      {:error, _reason} -> Date.to_string(date)
    end
  end
end
