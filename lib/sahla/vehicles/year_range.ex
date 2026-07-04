defmodule Sahla.Vehicles.YearRange do
  @moduledoc """
  Ecto type mapping a model-year span to a Postgres `int4range`.

  At the application boundary a span is an **inclusive** Elixir range —
  `2015..2020` means model years 2015 through 2020 — while the database stores
  the canonical half-open `int4range` `[2015,2021)`. This type converts between
  the two, so schemas and queries deal in ordinary Elixir ranges.
  """
  use Ecto.Type

  def type, do: :int4range

  def cast(%Range{first: first, last: last, step: 1}) when is_integer(first) and is_integer(last),
    do: {:ok, first..last}

  def cast(%Postgrex.Range{} = range), do: {:ok, from_pg(range)}
  def cast(nil), do: {:ok, nil}
  def cast(_), do: :error

  def load(%Postgrex.Range{} = range), do: {:ok, from_pg(range)}
  def load(nil), do: {:ok, nil}

  def dump(%Range{first: first, last: last, step: 1})
      when is_integer(first) and is_integer(last) do
    {:ok,
     %Postgrex.Range{
       lower: first,
       upper: last + 1,
       lower_inclusive: true,
       upper_inclusive: false
     }}
  end

  def dump(nil), do: {:ok, nil}
  def dump(_), do: :error

  # Postgres canonicalizes int4range to the half-open `[lower, upper)` form;
  # convert back to an inclusive Elixir range.
  defp from_pg(%Postgrex.Range{lower: lower, upper: upper, upper_inclusive: upper_inclusive})
       when is_integer(lower) and is_integer(upper) do
    last = if upper_inclusive, do: upper, else: upper - 1
    lower..last
  end
end
