defmodule Sahla.Rating.Engine do
  @moduledoc """
  The pure rating core (§9.1): computes indicative premiums for every active
  insurer × eligible product from the rate tables. No DB, no side effects —
  tables and the insurer/product catalog are injected, so it is fully
  property- and golden-testable.

      run(inputs, tables) :: [Offer.t()]

  For each catalog entry:

      base_rc     = rc_base band for (fiscal_power, fuel)
      premium_rc  = base_rc × usage_factor × city_factor × crm
      options_sum = Σ option_price(option, vehicle_value, franchise_pref)
      evcat       = evcat_rule(premium_rc)            # Law 110-14, always on
      pos         = insurer_positioning × fonctionnaire?   # fonctionnaire only when is_public_servant
      subtotal    = (premium_rc + options_sum + evcat) × pos
      total       = subtotal × (1 + tax_rate) + fixed_fees, rounded to the dirham

  The fonctionnaire (public-sector) discount is a per-insurer multiplier in
  `insurer_positioning[slug]["fonctionnaire"]`, applied only when
  `is_public_servant` is true. It lives entirely in the tables (§9.1) and is
  constrained to `(0, 1]`, so it can only lower a premium, never raise it.

  Money is integer centimes; the final total is rounded to a whole dirham (100
  centimes) and the residue booked to a `rounding` breakdown line so the lines
  always sum to the total.
  """
  alias Sahla.Rating.{CRM, Offer}

  @doc "Computes the list of offers. Returns `[]` when the vehicle has no matching rc_base band."
  @spec run(map(), map()) :: [Offer.t()]
  def run(inputs, tables) do
    case band_base_rc(inputs, tables[:rc_base]) do
      nil ->
        []

      base_rc ->
        {crm_coeff, crm_status} = CRM.coefficient(inputs, tables[:crm] || %{})
        crm = Decimal.to_float(crm_coeff)

        usage = factor(tables[:usage_factor], to_string(inputs[:usage]))
        city = factor(tables[:city_factor], to_string(inputs[:risk_zone]))
        premium_rc = round(base_rc * usage * city * crm)

        options = price_options(inputs, tables[:option_pricing])
        evcat = evcat(premium_rc, tables[:taxes_fees])
        base = %{rc: premium_rc, options: options, evcat: evcat}
        public_servant? = inputs[:is_public_servant] == true

        Enum.map(inputs[:catalog] || [], fn entry ->
          build_offer(entry, tables, base, crm_status, public_servant?)
        end)
    end
  end

  defp build_offer(entry, tables, base, crm_status, public_servant?) do
    formula = entry.product.formula
    positioning = positioning(tables[:insurer_positioning], entry.insurer.slug, formula)

    fonctionnaire =
      fonctionnaire_factor(public_servant?, tables[:insurer_positioning], entry.insurer.slug)

    effective = positioning * fonctionnaire

    positioned_rc = round(base.rc * effective)

    positioned_options =
      Enum.map(base.options, fn o ->
        %{o | annual_centimes: round(o.annual_centimes * effective)}
      end)

    positioned_evcat = round(base.evcat * effective)
    options_sum = positioned_options |> Enum.map(& &1.annual_centimes) |> Enum.sum()

    subtotal = positioned_rc + options_sum + positioned_evcat
    taxes = round(subtotal * number(tables[:taxes_fees], "tax_rate", 0.0))
    fees = number(tables[:taxes_fees], "fixed_fees_centimes", 0)

    raw_total = subtotal + taxes + fees
    annual = round_to_dirham(raw_total)
    rounding = annual - raw_total

    %Offer{
      insurer: entry.insurer,
      product: entry.product,
      formula: formula,
      annual_premium_centimes: annual,
      monthly_equiv_centimes: round(annual / 12),
      estimated?: crm_status == :estimated,
      breakdown: %{
        rc: positioned_rc,
        options: positioned_options,
        evcat: positioned_evcat,
        taxes: taxes,
        fees: fees,
        rounding: rounding,
        total: annual
      }
    }
  end

  # -- table lookups ---------------------------------------------------------

  defp band_base_rc(_inputs, nil), do: nil

  defp band_base_rc(inputs, %{"bands" => bands}) when is_list(bands) do
    fuel = to_string(inputs[:fuel])
    cv = inputs[:fiscal_power]

    band =
      Enum.find(bands, fn b ->
        is_integer(cv) and cv >= b["cv_min"] and cv <= b["cv_max"] and
          fuel_match?(b["fuel"], fuel)
      end)

    band && band["annual_centimes"]
  end

  defp band_base_rc(_inputs, _data), do: nil

  defp fuel_match?("*", _fuel), do: true
  defp fuel_match?(band_fuel, fuel), do: band_fuel == fuel

  defp price_options(inputs, option_table) do
    for code <- inputs[:options] || [] do
      %{code: code, annual_centimes: option_price(option_table, code, inputs)}
    end
  end

  defp option_price(%{"options" => options}, code, inputs) when is_map(options) do
    case Map.get(options, code) do
      spec when is_map(spec) -> price_from_spec(spec, inputs)
      _ -> 0
    end
  end

  defp option_price(_table, _code, _inputs), do: 0

  defp price_from_spec(spec, inputs) do
    base =
      cond do
        is_number(spec["annual_centimes"]) -> spec["annual_centimes"]
        is_number(spec["rate"]) -> round((inputs[:vehicle_value_centimes] || 0) * spec["rate"])
        true -> 0
      end

    multiplier =
      case spec["franchise"] do
        %{} = franchise -> Map.get(franchise, to_string(inputs[:franchise_pref]), 1.0)
        _ -> 1.0
      end

    max(round(base * multiplier), 0)
  end

  defp evcat(premium_rc, %{"evcat" => %{"rate" => rate, "min_centimes" => min_centimes}}) do
    max(round(premium_rc * rate), min_centimes)
  end

  defp evcat(_premium_rc, _table), do: 0

  defp factor(%{"factors" => factors}, key) when is_map(factors),
    do: as_number(Map.get(factors, key), 1.0)

  defp factor(_table, _key), do: 1.0

  defp positioning(%{} = table, slug, formula) do
    table |> Map.get(slug, %{}) |> Map.get(to_string(formula), 1.0) |> as_number(1.0)
  end

  defp positioning(_table, _slug, _formula), do: 1.0

  # Per-insurer public-sector discount, applied only for a fonctionnaire. The
  # value is validated to (0, 1], so it can only lower the premium.
  defp fonctionnaire_factor(false, _table, _slug), do: 1.0

  defp fonctionnaire_factor(true, %{} = table, slug) do
    table |> Map.get(slug, %{}) |> Map.get("fonctionnaire", 1.0) |> as_number(1.0)
  end

  defp fonctionnaire_factor(true, _table, _slug), do: 1.0

  defp number(table, key, default) when is_map(table), do: as_number(Map.get(table, key), default)
  defp number(_table, _key, default), do: default

  defp as_number(value, _default) when is_number(value), do: value
  defp as_number(_value, default), do: default

  defp round_to_dirham(centimes), do: round(centimes / 100) * 100
end
