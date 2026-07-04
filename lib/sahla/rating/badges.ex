defmodule Sahla.Rating.Badges do
  @moduledoc """
  Ranks and badges a list of `Sahla.Rating.Offer` (§5.3, §9.1) — the trust
  device on the results page. Pure: all inputs come via `opts`.

  Assigns `rank` (1..n ascending by price, stable tiebreak) and up to three
  badges per offer:

    * `:cheapest` — the single lowest total
    * `:best_value` — max `coverage_score / price`, where `coverage_score` is a
      weighted sum of included guarantees (weights from `opts[:coverage_weights]`,
      never hard-coded)
    * `:expert_pick` — only when a matching pin exists in `opts[:expert_pins]`
      (sourced from admin settings)

  Each badge carries a `justification` — an English gettext dev-key the results
  UI translates.
  """
  @justifications %{
    cheapest: "Cheapest price",
    best_value: "Best value for money",
    expert_pick: "Our expert pick"
  }

  @doc "Returns the offers ranked (ascending price) with `rank` and `badges` set."
  def assign(offers, opts \\ []) do
    offers
    |> rank()
    |> tag_cheapest()
    |> tag_best_value(Keyword.get(opts, :coverage_weights, %{}))
    |> tag_expert_pick(Keyword.get(opts, :expert_pins, []))
  end

  # Stable order: price, then insurer slug, then formula — deterministic on ties.
  defp rank(offers) do
    offers
    |> Enum.sort_by(
      &{&1.annual_premium_centimes, to_string(&1.insurer.slug), to_string(&1.formula)}
    )
    |> Enum.with_index(1)
    |> Enum.map(fn {offer, rank} -> %{offer | rank: rank} end)
  end

  defp tag_cheapest([]), do: []

  defp tag_cheapest([cheapest | rest]) do
    # Already price-sorted, so the head (rank 1) is the single cheapest.
    [add_badge(cheapest, :cheapest) | rest]
  end

  defp tag_best_value(offers, weights) do
    case best_value_rank(offers, weights) do
      nil -> offers
      rank -> Enum.map(offers, &maybe_badge(&1, &1.rank == rank, :best_value))
    end
  end

  defp best_value_rank(offers, weights) do
    offers
    |> Enum.map(fn o -> {o.rank, coverage_score(o, weights) / o.annual_premium_centimes} end)
    |> Enum.filter(fn {_rank, ratio} -> ratio > 0 end)
    |> case do
      [] -> nil
      scored -> scored |> Enum.max_by(&elem(&1, 1)) |> elem(0)
    end
  end

  defp tag_expert_pick(offers, pins) do
    Enum.map(
      offers,
      &maybe_badge(&1, Enum.any?(pins, fn pin -> pin_matches?(pin, &1) end), :expert_pick)
    )
  end

  defp maybe_badge(offer, true, kind), do: add_badge(offer, kind)
  defp maybe_badge(offer, false, _kind), do: offer

  defp pin_matches?(pin, offer) do
    slug_ok =
      is_nil(pin[:insurer_slug]) or to_string(pin[:insurer_slug]) == to_string(offer.insurer.slug)

    formula_ok = is_nil(pin[:formula]) or to_string(pin[:formula]) == to_string(offer.formula)
    slug_ok and formula_ok
  end

  defp coverage_score(offer, weights) do
    offer.product
    |> Map.get(:guarantees, [])
    |> Enum.reduce(0, fn code, acc -> acc + Map.get(weights, code, 0) end)
  end

  defp add_badge(offer, kind) do
    badge = %{kind: kind, justification: @justifications[kind]}
    %{offer | badges: offer.badges ++ [badge]}
  end
end
