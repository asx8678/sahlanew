defmodule Sahla.Vehicles do
  @moduledoc """
  Query boundary for the make → model → version catalog that drives vehicle
  identification and fiscal-power prefill (§3.3, §5.2 step 1).
  """
  import Ecto.Query

  alias Sahla.Repo
  alias Sahla.Vehicles.{Make, Model, UnmatchedVehicle, Version}

  @doc "Makes with popular ones first, then alphabetical."
  def list_makes do
    Make
    |> order_by([m], desc: m.popular, asc: m.name)
    |> Repo.all()
  end

  def list_models_for_make(make_id) do
    Model
    |> where([m], m.make_id == ^make_id)
    |> order_by([m], asc: m.name)
    |> Repo.all()
  end

  def list_versions_for_model(model_id) do
    Version
    |> where([v], v.model_id == ^model_id)
    |> order_by([v], asc: v.name, desc: v.id)
    |> Repo.all()
  end

  @doc """
  Versions of a model whose production `years` span contains `year`
  (int4range containment).
  """
  def versions_for_model_in_year(model_id, year) when is_integer(year) do
    Version
    |> where([v], v.model_id == ^model_id)
    |> where([v], fragment("? @> ?::int4", v.years, ^year))
    |> order_by([v], asc: v.name, desc: v.id)
    |> Repo.all()
  end

  def get_version!(id), do: Repo.get!(Version, id)

  @doc "Fetches just the `fiscal_power` for a version, or `nil` if absent/unknown."
  def fiscal_power_for_version(version_id) do
    Version
    |> where([v], v.id == ^version_id)
    |> select([v], v.fiscal_power)
    |> Repo.one()
  end

  # -- unmatched vehicles (§10.5) --------------------------------------------

  @doc """
  Records a free-text vehicle absent from the catalog. Dedupes on the normalized
  make/model/version; a repeat sighting increments `occurrences` rather than
  inserting a duplicate. Only vehicle descriptors are stored — never PII.
  """
  def record_unmatched(attrs) do
    attrs = Map.new(attrs)
    key = dedup_key(attrs)

    %UnmatchedVehicle{}
    |> UnmatchedVehicle.changeset(Map.put(attrs, :dedup_key, key))
    |> Repo.insert(
      on_conflict: [inc: [occurrences: 1], set: [updated_at: now()]],
      conflict_target: :dedup_key,
      returning: true
    )
  end

  @doc "Unmatched vehicles in `status` (default `:pending`), most-requested first."
  def list_unmatched(status \\ :pending) do
    UnmatchedVehicle
    |> where([u], u.status == ^status)
    |> order_by([u], desc: u.occurrences, desc: u.id)
    |> Repo.all()
  end

  @doc "Resolves an unmatched entry by mapping it to a catalog version."
  def resolve_unmatched(%UnmatchedVehicle{} = entry, version_id) do
    entry
    |> UnmatchedVehicle.status_changeset(%{status: :resolved, resolved_version_id: version_id})
    |> Repo.update()
  end

  @doc "Marks an unmatched entry as ignored (noise, not worth cataloguing)."
  def ignore_unmatched(%UnmatchedVehicle{} = entry) do
    entry
    |> UnmatchedVehicle.status_changeset(%{status: :ignored})
    |> Repo.update()
  end

  defp dedup_key(attrs) do
    [attrs[:raw_make], attrs[:raw_model], attrs[:raw_version]]
    |> Enum.map_join("|", &normalize_text/1)
  end

  defp normalize_text(nil), do: ""

  defp normalize_text(text) do
    text |> to_string() |> String.trim() |> String.downcase() |> String.replace(~r/\s+/, " ")
  end

  defp now, do: DateTime.truncate(DateTime.utc_now(), :second)
end
