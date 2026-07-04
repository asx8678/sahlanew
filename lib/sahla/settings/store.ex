defmodule Sahla.Settings.Store do
  @moduledoc """
  Persistence for `Sahla.Settings`: the DB read/upsert behind the cache. Handles
  the jsonb value envelope so callers deal in bare values.
  """
  import Ecto.Query, only: [from: 2]

  alias Sahla.Repo
  alias Sahla.Settings.Setting

  @doc "All settings as `{key, value}` pairs, values unwrapped."
  def all do
    Repo.all(from(s in Setting, select: {s.key, s.value}))
    |> Enum.map(fn {key, value} -> {key, unwrap(value)} end)
  end

  @doc "Inserts or updates a setting by key. Returns `{:ok, setting}` or `{:error, changeset}`."
  def upsert(key, value) do
    %Setting{}
    |> Setting.changeset(%{key: key, value: wrap(value)})
    |> Repo.insert(on_conflict: {:replace, [:value, :updated_at]}, conflict_target: :key)
  end

  defp wrap(value), do: %{"value" => value}

  defp unwrap(%{"value" => value}), do: value
  defp unwrap(other), do: other
end
