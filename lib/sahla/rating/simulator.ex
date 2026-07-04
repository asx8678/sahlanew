defmodule Sahla.Rating.Simulator.Diff do
  @moduledoc false
  # One insurer×formula premium comparison. `old`/`new` are integer centimes;
  # either may be nil when a draft makes an offer appear or disappear. `pct` is
  # the fractional change (`delta / old`), nil when there is no old baseline.
  @enforce_keys [:insurer, :formula, :old_centimes, :new_centimes, :delta_centimes, :pct]
  defstruct [:insurer, :formula, :old_centimes, :new_centimes, :delta_centimes, :pct]

  @type t :: %__MODULE__{}
end

defmodule Sahla.Rating.Simulator do
  @moduledoc """
  Draft-vs-published premium preview (§9.2). Pure, **read-only** governance tool:
  it overlays one or more *draft* rate tables on top of the current published set
  and reports how each insurer×formula premium moves — **without publishing
  anything**. The admin-studio LiveView renders the returned structs.

  The overlay merges `draft_tables` (a `%{code => data}` map for the code(s) under
  test) onto `Tables.load_all/1`, so codes not in the draft keep their published
  rows. Both the published and overlaid table sets are run through the same pure
  `Sahla.Rating.Engine`, and the offers paired by `{insurer_slug, formula}`.

  Pass `baseline: %{code => data}` in `opts` to inject the published set directly
  (tests, or reusing a snapshot); otherwise it is resolved via `Tables.load_all`
  as of `opts[:on_date]` (today by default). No branch writes to the database.
  """
  alias Sahla.Rating.{Engine, Tables}
  alias Sahla.Rating.Simulator.Diff

  @doc """
  Compares premiums for one `inputs` profile: returns a list of
  `%Simulator.Diff{}` (old, new, delta, pct) per insurer×formula, sorted for a
  stable render.
  """
  @spec run_profile(map(), map(), keyword()) :: [Diff.t()]
  def run_profile(inputs, draft_tables, opts \\ []) do
    baseline = baseline(opts)
    overlaid = overlay(baseline, draft_tables)
    diff_offers(Engine.run(inputs, baseline), Engine.run(inputs, overlaid))
  end

  @doc """
  Runs `run_profile/3` over a list of `personas` (each a full `inputs` map — the
  golden set is a natural source), resolving the baseline once. Returns
  `%{aggregate: map, personas: [%{inputs:, diffs:}]}`.
  """
  @spec run_batch([map()], map(), keyword()) :: %{aggregate: map(), personas: [map()]}
  def run_batch(personas, draft_tables, opts \\ []) do
    baseline = baseline(opts)
    overlaid = overlay(baseline, draft_tables)

    per_persona =
      Enum.map(personas, fn inputs ->
        diffs = diff_offers(Engine.run(inputs, baseline), Engine.run(inputs, overlaid))
        %{inputs: inputs, diffs: diffs}
      end)

    %{aggregate: aggregate(per_persona), personas: per_persona}
  end

  # --- internals -------------------------------------------------------------

  defp baseline(opts) do
    Keyword.get(opts, :baseline) || Tables.load_all(Keyword.get(opts, :on_date, Date.utc_today()))
  end

  # Draft codes override the published ones; every other code stays published.
  defp overlay(baseline, draft_tables), do: Map.merge(baseline, Map.new(draft_tables))

  defp diff_offers(old_offers, new_offers) do
    old = index(old_offers)
    new = index(new_offers)

    (Map.keys(old) ++ Map.keys(new))
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map(fn {slug, formula} = key ->
      old_centimes = premium(old[key])
      new_centimes = premium(new[key])

      %Diff{
        insurer: slug,
        formula: formula,
        old_centimes: old_centimes,
        new_centimes: new_centimes,
        delta_centimes: delta(old_centimes, new_centimes),
        pct: pct(old_centimes, new_centimes)
      }
    end)
  end

  defp index(offers), do: Map.new(offers, &{{&1.insurer.slug, &1.formula}, &1})

  defp premium(nil), do: nil
  defp premium(offer), do: offer.annual_premium_centimes

  defp delta(nil, _new), do: nil
  defp delta(_old, nil), do: nil
  defp delta(old, new), do: new - old

  defp pct(nil, _new), do: nil
  defp pct(_old, nil), do: nil
  defp pct(0, _new), do: nil
  defp pct(old, new), do: (new - old) / old

  defp aggregate(per_persona) do
    diffs = Enum.flat_map(per_persona, & &1.diffs)
    paired = Enum.filter(diffs, &(&1.old_centimes && &1.new_centimes))
    total_old = paired |> Enum.map(& &1.old_centimes) |> Enum.sum()
    total_new = paired |> Enum.map(& &1.new_centimes) |> Enum.sum()

    %{
      personas: length(per_persona),
      lines: length(diffs),
      total_old_centimes: total_old,
      total_new_centimes: total_new,
      total_delta_centimes: total_new - total_old,
      avg_pct: avg_pct(paired)
    }
  end

  defp avg_pct(paired) do
    pcts = paired |> Enum.map(& &1.pct) |> Enum.reject(&is_nil/1)

    case pcts do
      [] -> nil
      _ -> Enum.sum(pcts) / length(pcts)
    end
  end
end
