defmodule Sahla.Vehicles.Catalog do
  @moduledoc """
  Trigram-ranked autocomplete over the make → model → version catalog (§3.3, §5.2),
  the funnel's replacement for a plate/VIN registry.

  All matching is **case- and accent-insensitive**: queries filter with an
  index-backed `ILIKE '%…%'` on `sahla_unaccent(name)` (using the functional GIN
  indexes from `AddVehicleSearchIndexes`) and rank by trigram `similarity`, so
  `"megane"` matches `"Mégane"`. These are pure query functions — the funnel
  LiveView calls them and never touches `Repo` directly.

  Ties break by curated relevance then name: for makes similarity → `popular`
  → name; for models/versions similarity → name → `id` (the second-precision
  tiebreaker from `Sahla.Schema`).
  """
  import Ecto.Query

  alias Sahla.Repo
  alias Sahla.Vehicles.{Make, Model, Version}

  @default_limit 10

  @doc "Makes matching `query`, best trigram match first, popular ones winning ties."
  def search_makes(query, opts \\ []) do
    if blank?(query) do
      []
    else
      Make
      |> trgm_where(query)
      |> order_by([m],
        desc:
          fragment("similarity(sahla_unaccent(?), sahla_unaccent(?))", m.name, ^trimmed(query)),
        desc: m.popular,
        asc: m.name
      )
      |> limit(^limit(opts))
      |> Repo.all()
    end
  end

  @doc "Models under `make_id` matching `query`, best trigram match first."
  def search_models(make_id, query, opts \\ []) do
    if blank?(query) do
      []
    else
      Model
      |> where([m], m.make_id == ^make_id)
      |> trgm_where(query)
      |> order_by([m],
        desc:
          fragment("similarity(sahla_unaccent(?), sahla_unaccent(?))", m.name, ^trimmed(query)),
        asc: m.name,
        desc: m.id
      )
      |> limit(^limit(opts))
      |> Repo.all()
    end
  end

  @doc """
  Versions under `model_id` matching `query`, best trigram match first.

  Results are full `Version` structs, so `fiscal_power`, `fuel` and `seats` are
  available to prefill the funnel.
  """
  def search_versions(model_id, query, opts \\ []) do
    if blank?(query) do
      []
    else
      Version
      |> where([v], v.model_id == ^model_id)
      |> trgm_where(query)
      |> order_by([v],
        desc:
          fragment("similarity(sahla_unaccent(?), sahla_unaccent(?))", v.name, ^trimmed(query)),
        asc: v.name,
        desc: v.id
      )
      |> limit(^limit(opts))
      |> Repo.all()
    end
  end

  # Index-backed, accent/case-insensitive substring filter on `name`.
  defp trgm_where(queryable, query) do
    where(
      queryable,
      [x],
      fragment("sahla_unaccent(?) ILIKE sahla_unaccent(?)", x.name, ^like_pattern(query))
    )
  end

  defp blank?(query), do: is_nil(query) or trimmed(query) == ""

  defp trimmed(query), do: String.trim(query)

  defp limit(opts), do: Keyword.get(opts, :limit, @default_limit)

  # Wrap the (LIKE-escaped) query in %…% for a substring match.
  defp like_pattern(query) do
    escaped =
      query
      |> trimmed()
      |> String.replace("\\", "\\\\")
      |> String.replace("%", "\\%")
      |> String.replace("_", "\\_")

    "%" <> escaped <> "%"
  end
end
