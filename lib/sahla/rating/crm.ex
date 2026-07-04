defmodule Sahla.Rating.CRM do
  @moduledoc """
  Derives the CRM (bonus-malus) coefficient (§3.1, §9.1). Pure and deterministic
  — inject `:today` in the inputs.

  Every parameter comes from the `crm` rate table, never hard-coded:

      %{"start" => 1.0, "floor" => 0.5, "ceiling" => 2.5,
        "clean_year_factor" => 0.9, "claim_factor" => 1.2}

  When the driver knows their CRM it is clamped into `[floor, ceiling]` and
  returned as `:known`. Otherwise it is derived from licence seniority and
  at-fault claims and returned as `:estimated`, which lets the engine mark the
  offer "à confirmer avec votre relevé d'information".
  """

  @typedoc "Rating inputs consumed by the CRM derivation."
  @type inputs :: %{
          optional(:crm) => Decimal.t() | number() | nil,
          optional(:license_date) => Date.t() | nil,
          optional(:at_fault_claims_36m) => non_neg_integer() | nil,
          required(:today) => Date.t()
        }

  @doc "Returns `{coefficient, :known | :estimated}` rounded to 2 decimals."
  @spec coefficient(inputs(), map()) :: {Decimal.t(), :known | :estimated}
  def coefficient(inputs, crm_table) do
    floor = to_decimal(crm_table["floor"])
    ceiling = to_decimal(crm_table["ceiling"])

    case known_value(inputs) do
      nil -> {derive(inputs, crm_table, floor, ceiling), :estimated}
      value -> {clamp(value, floor, ceiling), :known}
    end
  end

  defp known_value(inputs) do
    case Map.get(inputs, :crm) do
      nil -> nil
      %Decimal{} = crm -> crm
      crm when is_integer(crm) -> Decimal.new(crm)
      crm when is_float(crm) -> Decimal.from_float(crm)
    end
  end

  defp derive(inputs, crm_table, floor, ceiling) do
    start = to_decimal(crm_table["start"])
    clean_factor = to_decimal(crm_table["clean_year_factor"])
    claim_factor = to_decimal(crm_table["claim_factor"])

    years = licensed_years(inputs)
    claims = max(Map.get(inputs, :at_fault_claims_36m) || 0, 0)

    # Reduce per licensed year (floored), then load per at-fault claim (capped).
    reduced = Decimal.max(Decimal.mult(start, pow(clean_factor, years)), floor)

    reduced
    |> Decimal.mult(pow(claim_factor, claims))
    |> Decimal.min(ceiling)
    |> Decimal.round(2)
  end

  defp clamp(value, floor, ceiling) do
    value
    |> Decimal.max(floor)
    |> Decimal.min(ceiling)
    |> Decimal.round(2)
  end

  defp licensed_years(inputs) do
    with %Date{} = license_date <- Map.get(inputs, :license_date),
         %Date{} = today <- Map.get(inputs, :today) do
      max(div(Date.diff(today, license_date), 365), 0)
    else
      _ -> 0
    end
  end

  defp pow(_base, 0), do: Decimal.new(1)

  defp pow(base, exp) when exp > 0,
    do: Enum.reduce(1..exp, Decimal.new(1), fn _, acc -> Decimal.mult(acc, base) end)

  defp to_decimal(%Decimal{} = value), do: value
  defp to_decimal(value) when is_integer(value), do: Decimal.new(value)
  defp to_decimal(value) when is_float(value), do: Decimal.from_float(value)
end
