defmodule Sahla.Rating.Table.Schema do
  @moduledoc """
  Per-code shape validation for `rate_tables.data` (§9.1). Every rating number
  lives in versioned jsonb — zero business numbers in code — so each `code` has
  a required structure this module enforces before a table can be saved.

  `validate/2` takes the code and the (string-keyed, as stored in jsonb) data
  map and returns `:ok` or `{:error, message}` describing the first problem.
  """

  @formulas ~w(rc tiers_etendu tous_risques)
  @zones ~w(1 2 3)

  # insurer_positioning coefficients: one per formula, plus an optional
  # public-sector ("fonctionnaire") discount multiplier.
  @positioning_keys @formulas ++ ["fonctionnaire"]

  @doc "Validates `data` against the schema for `code`."
  @spec validate(atom(), map()) :: :ok | {:error, String.t()}
  def validate(:rc_base, %{"bands" => bands}) when is_list(bands) and bands != [] do
    reduce(bands, fn band, i ->
      with :ok <- require_int(band, "cv_min", "rc_base band #{i}"),
           :ok <- require_int(band, "cv_max", "rc_base band #{i}"),
           :ok <- require_string(band, "fuel", "rc_base band #{i}") do
        require_non_neg_int(band, "annual_centimes", "rc_base band #{i}")
      end
    end)
  end

  def validate(:rc_base, _), do: {:error, ~s(rc_base requires a non-empty "bands" array)}

  def validate(:usage_factor, %{"factors" => factors}),
    do: numeric_map("usage_factor.factors", factors)

  def validate(:usage_factor, _), do: {:error, ~s(usage_factor requires a "factors" object)}

  def validate(:city_factor, %{"factors" => factors}) when is_map(factors) do
    with :ok <- numeric_map("city_factor.factors", factors) do
      case @zones -- Map.keys(factors) do
        [] ->
          :ok

        missing ->
          {:error, "city_factor.factors is missing risk zones: #{Enum.join(missing, ", ")}"}
      end
    end
  end

  def validate(:city_factor, _),
    do: {:error, ~s(city_factor requires a "factors" object keyed by risk zone)}

  def validate(:crm, data) when is_map(data) do
    with :ok <- require_number(data, "start", "crm"),
         :ok <- require_number(data, "floor", "crm"),
         :ok <- require_number(data, "ceiling", "crm"),
         :ok <- require_number(data, "clean_year_factor", "crm") do
      require_number(data, "claim_factor", "crm")
    end
  end

  def validate(:crm, _),
    do: {:error, "crm requires numbers: start, floor, ceiling, clean_year_factor, claim_factor"}

  def validate(:option_pricing, %{"options" => options}) when is_map(options) do
    reduce(Map.to_list(options), fn {code, spec}, _i ->
      if is_map(spec), do: :ok, else: {:error, "option_pricing.options.#{code} must be an object"}
    end)
  end

  def validate(:option_pricing, _), do: {:error, ~s(option_pricing requires an "options" object)}

  def validate(:insurer_positioning, data) when is_map(data) and map_size(data) > 0 do
    reduce(Map.to_list(data), fn {insurer, coeffs}, _i ->
      label = "insurer_positioning.#{insurer}"

      cond do
        not is_map(coeffs) ->
          {:error, "#{label} must be an object of formula coefficients"}

        (bad = Map.keys(coeffs) -- @positioning_keys) != [] ->
          {:error, "#{label} has unknown keys: #{Enum.join(bad, ", ")}"}

        true ->
          validate_positioning_coeffs(label, coeffs)
      end
    end)
  end

  def validate(:insurer_positioning, _),
    do:
      {:error,
       "insurer_positioning requires a non-empty object of insurer => formula coefficients"}

  def validate(:taxes_fees, data) when is_map(data) do
    with :ok <- require_number(data, "tax_rate", "taxes_fees"),
         :ok <- in_unit_interval(data["tax_rate"], "taxes_fees.tax_rate"),
         :ok <- require_non_neg_int(data, "fixed_fees_centimes", "taxes_fees") do
      # Law 110-14: EVCAT is a mandatory, always-on line.
      require_evcat(data)
    end
  end

  def validate(:taxes_fees, _), do: {:error, "taxes_fees requires an object"}

  # -- helpers ---------------------------------------------------------------

  defp validate_positioning_coeffs(label, coeffs) do
    with :ok <- numeric_map(label, coeffs) do
      validate_fonctionnaire(label, coeffs)
    end
  end

  # A fonctionnaire discount, when present, must sit in (0, 1] — it can only
  # lower the premium, never raise it (§3.1).
  defp validate_fonctionnaire(label, %{"fonctionnaire" => factor}) do
    if is_number(factor) and factor > 0 and factor <= 1.0 do
      :ok
    else
      {:error,
       "#{label}.fonctionnaire must be a number in (0, 1] (a discount never raises the premium)"}
    end
  end

  defp validate_fonctionnaire(_label, _coeffs), do: :ok

  defp require_evcat(%{"evcat" => evcat}) when is_map(evcat) do
    with :ok <- require_number(evcat, "rate", "taxes_fees.evcat") do
      require_non_neg_int(evcat, "min_centimes", "taxes_fees.evcat")
    end
  end

  defp require_evcat(_),
    do:
      {:error,
       ~s|taxes_fees must include an "evcat" object with "rate" and "min_centimes" (Law 110-14)|}

  defp reduce(items, fun) do
    items
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {item, i}, :ok ->
      case fun.(item, i) do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp numeric_map(label, map) when is_map(map) and map_size(map) > 0 do
    reduce(Map.to_list(map), fn {key, value}, _i ->
      if is_number(value), do: :ok, else: {:error, "#{label}.#{key} must be a number"}
    end)
  end

  defp numeric_map(label, _), do: {:error, "#{label} must be a non-empty object of numbers"}

  defp require_int(map, key, label) do
    if is_integer(Map.get(map, key)),
      do: :ok,
      else: {:error, "#{label} is missing an integer \"#{key}\""}
  end

  defp require_non_neg_int(map, key, label) do
    case Map.get(map, key) do
      v when is_integer(v) and v >= 0 -> :ok
      _ -> {:error, "#{label} is missing a non-negative integer \"#{key}\""}
    end
  end

  defp require_number(map, key, label) do
    if is_number(Map.get(map, key)),
      do: :ok,
      else: {:error, "#{label} is missing a number \"#{key}\""}
  end

  defp require_string(map, key, label) do
    case Map.get(map, key) do
      v when is_binary(v) and v != "" -> :ok
      _ -> {:error, "#{label} is missing a string \"#{key}\""}
    end
  end

  defp in_unit_interval(v, _label) when is_number(v) and v >= 0 and v <= 1, do: :ok
  defp in_unit_interval(_, label), do: {:error, "#{label} must be between 0 and 1"}
end
