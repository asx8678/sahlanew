defmodule Sahla.Rating.GoldenTest do
  @moduledoc """
  Golden persona tests for the rating engine.

  Seeds the placeholder catalog and rate tables once, then runs every persona
  in `priv/rating_fixtures/` against the published tables. Every expected
  premium must be within the configured drift threshold.
  """

  use Sahla.DataCase, async: false

  alias Sahla.Rating.Fixtures
  alias Sahla.Rating.Tables

  # Deterministic seeding of catalog + tables before any persona runs.
  setup do
    {:ok, %{results: run_suite!()}}
  end

  test "all 40+ fixtures produce offers within the drift threshold", %{results: results} do
    failures =
      Enum.reject(results, &(&1.status == :pass))
      |> Enum.map(fn r ->
        {r.id, r.status, Enum.map(r.diffs, &format_diff/1)}
      end)

    assert failures == [], "some fixtures drifted: #{inspect(failures, pretty: true)}"
  end

  test "median Tous risques personas land between 3 500 and 5 500 MAD", %{results: results} do
    assert Enum.any?(results, fn result ->
             result.status == :pass and
               Enum.any?(result.offers, fn offer ->
                 offer.formula == "tous_risques" and
                   offer.annual_premium_centimes >= 350_000 and
                   offer.annual_premium_centimes <= 550_000
               end)
           end),
           "expected at least one Tous risques persona between 3 500 and 5 500 MAD"
  end

  test "old-car RC-only personas land between 1 600 and 2 500 MAD", %{results: results} do
    assert Enum.any?(results, fn result ->
             result.status == :pass and
               old_car?(result) and
               Enum.any?(result.offers, fn offer ->
                 offer.formula == "rc" and
                   offer.annual_premium_centimes >= 160_000 and
                   offer.annual_premium_centimes <= 250_000
               end)
           end),
           "expected at least one old-car RC persona between 1 600 and 2 500 MAD"
  end

  test "every offer contains a positive EVCAT breakdown line", %{results: results} do
    for result <- results,
        offer <- result.offers do
      assert offer.breakdown.evcat > 0,
             "#{result.id} #{offer.insurer_slug} #{offer.formula} missing EVCAT"
    end
  end

  test "estimated fixtures are flagged as estimated", %{results: results} do
    estimated_results = Enum.filter(results, &estimated_fixture?/1)

    assert Enum.any?(estimated_results),
           "expected at least one estimated persona fixture"

    for result <- estimated_results,
        offer <- result.offers do
      assert offer.estimated == true,
             "#{result.id} expected estimated? to be true"
    end
  end

  test "a deliberately drifted fixture fails with clear expected-vs-actual output" do
    [fixture | _] = Fixtures.load_fixtures()
    tables = Tables.load_all()
    catalog = Fixtures.build_catalog()

    # Mutate the expected premium by a large, deterministic amount.
    drifted =
      update_in(fixture["expected"], fn expected ->
        Enum.map(expected, fn e ->
          Map.update!(e, "annual_premium_centimes", &(&1 + 10_000))
        end)
      end)

    result = Fixtures.run_fixture(drifted, tables, catalog)

    assert result.status == :fail
    assert length(result.diffs) == length(fixture["expected"])

    for diff <- result.diffs do
      assert diff.delta > 0
      refute is_nil(diff.expected)
      refute is_nil(diff.actual)
    end
  end

  # -- helpers ----------------------------------------------------------------

  defp run_suite! do
    {results, summary} = Fixtures.run_suite(seed: true)

    if summary.no_band > 0 do
      no_band_ids = Enum.filter(results, &(&1.status == :no_band)) |> Enum.map(& &1.id)
      flunk("#{summary.no_band} personas have no matching RC band: #{inspect(no_band_ids)}")
    end

    if summary.missing > 0 do
      flunk("fixture catalog mismatch: #{summary.missing} personas missing offers")
    end

    results
  end

  defp format_diff(diff) do
    "#{diff.insurer_slug}/#{diff.formula}: expected #{diff.expected}, actual #{diff.actual}, delta #{diff.delta}"
  end

  defp old_car?(result) do
    # The raw inputs are not kept on the result, but the fixture id carries
    # enough context for the curated old-car personas (persona_001..012 and
    # the extra old-car personas persona_038..041). All of those use <= 9CV.
    String.match?(result.id, ~r/^persona_(00[1-9]|01[0-2]|038|039|040|041)$/)
  end

  defp estimated_fixture?(result) do
    result.id in ["persona_033", "persona_034"]
  end
end
