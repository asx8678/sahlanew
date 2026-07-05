defmodule Sahla.Rating.Fixtures do
  @moduledoc """
  Golden persona fixture suite for the rating engine.

  Loads persona JSON files from `priv/rating_fixtures/` and runs each one
  against the real seeded catalog and published rate tables. Each fixture
  declares its inputs and expected insurer×formula premiums; the runner
  hydrates the catalog from the database, calls `Sahla.Rating.Engine.run/2`,
  and reports any differences beyond the configured drift threshold.
  """

  alias Sahla.Directory
  alias Sahla.Rating.{Engine, Seeds, Tables}

  @priv_dir :code.priv_dir(:sahla)
  @fixtures_dir Path.join(@priv_dir, "rating_fixtures")
  @default_threshold 100

  @typedoc """
  One fixture expectation.

      %{insurer_slug: string, formula: string, annual_premium_centimes: integer}
  """
  @type expected :: %{
          insurer_slug: String.t(),
          formula: String.t(),
          annual_premium_centimes: integer()
        }

  @typedoc """
  Raw fixture loaded from JSON.
  """
  @type fixture :: %{
          id: String.t(),
          description: String.t(),
          inputs: map(),
          expected: [expected()],
          threshold_centimes: integer() | nil
        }

  @typedoc """
  One mismatch between expected and actual offers.
  """
  @type diff :: %{
          insurer_slug: String.t(),
          formula: String.t(),
          expected: integer() | nil,
          actual: integer() | nil,
          delta: integer()
        }

  @typedoc """
  Result of running a single fixture.
  """
  @type result :: %{
          id: String.t(),
          status: :pass | :fail | :missing | :no_band,
          diffs: [diff()],
          offers: [map()]
        }

  @doc """
  Loads every `.json` file under `priv/rating_fixtures/` and returns them as
  a list of fixture maps, sorted by id.
  """
  @spec load_fixtures() :: [fixture()]
  def load_fixtures do
    @fixtures_dir
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".json"))
    |> Enum.sort()
    |> Enum.map(fn file ->
      file
      |> then(&Path.join(@fixtures_dir, &1))
      |> File.read!()
      |> Jason.decode!()
      |> normalize_fixture()
    end)
    |> Enum.sort_by(& &1["id"])
  end

  @doc """
  Runs one fixture.

  * `tables` is the published rate table map (`Sahla.Rating.Tables.load_all/0`).
  * `catalog` is the hydrated list of `%{insurer: ..., product: ...}` structs.
  """
  @spec run_fixture(fixture(), map(), [map()]) :: result()
  def run_fixture(fixture, tables, catalog) do
    id = fixture["id"]
    inputs = hydrate_inputs(fixture["inputs"], catalog)
    expected = index_expected(fixture["expected"])

    case Engine.run(inputs, tables) do
      [] -> %{id: id, status: :no_band, diffs: [], offers: []}
      offers -> compare_offers(id, offers, expected, threshold_for(fixture))
    end
  end

  defp compare_offers(id, offers, expected, threshold) do
    actual = index_offers(offers)

    diffs =
      Enum.map(expected, fn {key, exp} ->
        act = actual[key]
        delta = if is_nil(act), do: :infinity, else: abs(exp - act)

        %{
          insurer_slug: elem(key, 0),
          formula: elem(key, 1),
          expected: exp,
          actual: act,
          delta: delta
        }
      end)
      |> Enum.filter(fn d -> is_nil(d.actual) or d.delta == :infinity or d.delta > threshold end)

    status =
      cond do
        Enum.any?(diffs, &is_nil(&1.actual)) -> :missing
        diffs != [] -> :fail
        true -> :pass
      end

    %{id: id, status: status, diffs: diffs, offers: Enum.map(offers, &offer_to_map/1)}
  end

  @doc """
  Runs the entire fixture suite, returning `{results, summary}`.

  Seeds the placeholder catalog and tables once if `seed?` is true (the
  default), loads published tables, and reports a pass/fail summary.
  """
  @spec run_suite(keyword()) :: {[result()], map()}
  def run_suite(opts \\ []) do
    seed? = Keyword.get(opts, :seed, true)

    if seed? do
      Directory.ensure_seed_catalog!()
      Seeds.seed_placeholders()
    end

    tables = Tables.load_all()
    catalog = build_catalog()
    fixtures = load_fixtures()

    results = Enum.map(fixtures, &run_fixture(&1, tables, catalog))

    summary = %{
      total: length(results),
      pass: Enum.count(results, &(&1.status == :pass)),
      fail: Enum.count(results, &(&1.status == :fail)),
      missing: Enum.count(results, &(&1.status == :missing)),
      no_band: Enum.count(results, &(&1.status == :no_band))
    }

    {results, summary}
  end

  @doc """
  Hydrates a list of insurer slugs and product formulas into the full catalog
  structs the engine expects.

  If any requested insurer slug does not exist, raises `ArgumentError` with a
  clear message.
  """
  @spec build_catalog([String.t()]) :: [map()]
  def build_catalog(slugs \\ nil) do
    insurers =
      if slugs do
        Enum.map(slugs, &fetch_insurer!/1)
      else
        Directory.list_active_insurers()
      end

    Enum.flat_map(insurers, &products_for_insurer/1)
  end

  defp fetch_insurer!(slug) do
    case Directory.get_insurer_by_slug(slug) do
      nil -> raise ArgumentError, "unknown insurer slug: #{inspect(slug)}"
      insurer -> insurer
    end
  end

  defp products_for_insurer(insurer) do
    insurer.id
    |> Directory.list_products_for_insurer()
    |> Enum.map(fn product ->
      %{
        insurer: %{slug: insurer.slug, name_fr: insurer.name_fr, name_ar: insurer.name_ar},
        product: %{formula: product.formula}
      }
    end)
  end

  @doc """
  Converts fixture inputs into the map consumed by `Engine.run/2`. Specifically:

  * atomizes string keys,
  * converts CRM/claims/date fields when present,
  * injects the hydrated `:catalog`,
  * sets `:today` to today if missing.
  """
  @spec hydrate_inputs(map(), [map()]) :: map()
  @known_input_keys ~w(fiscal_power fuel usage risk_zone vehicle_value_centimes franchise_pref options is_public_servant today license_date at_fault_claims_36m crm)

  def hydrate_inputs(inputs, catalog) do
    inputs
    |> Enum.map(fn {k, v} -> {to_atom(k), v} end)
    |> Enum.into(%{})
    |> maybe_put_decimal(:crm)
    |> maybe_put_date(:today)
    |> maybe_put_date(:license_date)
    |> Map.put(:catalog, catalog)
  end

  defp to_atom(key) when key in @known_input_keys, do: String.to_existing_atom(key)
  defp to_atom(_key), do: nil

  @doc """
  Re-regenerates the `expected` premium list for every fixture in
  `priv/rating_fixtures/` from the current engine and tables, then writes the
  files back. Use only manually when the engine or placeholder grids change.
  """
  def regenerate_expected_values do
    Directory.ensure_seed_catalog!()
    Seeds.seed_placeholders()
    tables = Tables.load_all()
    catalog = build_catalog()

    for fixture <- load_fixtures() do
      result = run_fixture(fixture, tables, catalog)

      expected =
        Enum.map(result.offers, fn offer ->
          %{
            "insurer_slug" => offer.insurer_slug,
            "formula" => offer.formula,
            "annual_premium_centimes" => offer.annual_premium_centimes
          }
        end)

      updated = Map.put(fixture, "expected", expected)
      path = Path.join(@fixtures_dir, "#{fixture["id"]}.json")
      File.write!(path, Jason.encode!(updated) <> "\n")
    end

    :ok
  end

  @doc """
  Returns the drift threshold for a fixture, falling back to application
  config and then the default of 100 centimes (1 MAD).
  """
  @spec threshold_for(fixture()) :: integer()
  def threshold_for(fixture) do
    fixture["threshold_centimes"] ||
      Application.get_env(:sahla, :rating_drift_threshold_centimes, @default_threshold)
  end

  # -- internals --------------------------------------------------------------

  defp normalize_fixture(map) do
    Map.update!(map, "expected", fn expected ->
      Enum.map(expected, fn e ->
        %{
          "insurer_slug" => e["insurer_slug"],
          "formula" => e["formula"],
          "annual_premium_centimes" => e["annual_premium_centimes"]
        }
      end)
    end)
  end

  defp maybe_put_decimal(map, key) do
    case Map.get(map, key) do
      nil -> map
      value when is_number(value) -> Map.put(map, key, Decimal.new(value))
      _ -> map
    end
  end

  defp maybe_put_date(map, key) do
    case Map.get(map, key) do
      nil ->
        map

      %Date{} ->
        map

      value when is_binary(value) ->
        case Date.from_iso8601(value) do
          {:ok, date} -> Map.put(map, key, date)
          _ -> map
        end

      _ ->
        map
    end
  end

  defp index_expected(expected) do
    Enum.into(expected, %{}, fn e ->
      {{e["insurer_slug"], e["formula"]}, e["annual_premium_centimes"]}
    end)
  end

  defp index_offers(offers) do
    Enum.into(offers, %{}, fn offer ->
      {{to_string(offer.insurer.slug), to_string(offer.formula)}, offer.annual_premium_centimes}
    end)
  end

  defp offer_to_map(offer) do
    %{
      insurer_slug: to_string(offer.insurer.slug),
      formula: to_string(offer.formula),
      annual_premium_centimes: offer.annual_premium_centimes,
      estimated: offer.estimated?,
      breakdown: offer.breakdown
    }
  end
end
