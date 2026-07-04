defmodule Sahla.Rating.TableCache do
  @moduledoc """
  In-process ETS cache of published rate tables for fast, deterministic rating
  resolution (§9.2). Owns a single ETS entry holding `%{code => [rows]}` (all
  published rows, sorted newest-effective first), so reads are a single atomic
  lookup — a resolve never sees a half-updated table set.

  Warmed on boot and refreshed on publish, both via `refresh/0` and a
  `"rating:tables"` PubSub broadcast (so other nodes refresh too).
  """
  use GenServer

  require Logger

  alias Sahla.Rating.Tables

  @table :rating_tables_cache
  @key :published
  @topic "rating:tables"

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc "Returns the `%{code => [rows]}` snapshot, warming the cache if cold."
  def snapshot do
    case :ets.lookup(@table, @key) do
      [{@key, map}] -> map
      [] -> GenServer.call(__MODULE__, :refresh)
    end
  end

  @doc "Synchronously reloads the cache from the database and returns the snapshot."
  def refresh, do: GenServer.call(__MODULE__, :refresh)

  @doc "Empties the cache (test support)."
  def clear, do: GenServer.call(__MODULE__, :clear)

  @impl true
  def init(:ok) do
    :ets.new(@table, [:named_table, :public, read_concurrency: true])
    Phoenix.PubSub.subscribe(Sahla.PubSub, @topic)
    {:ok, %{}, {:continue, :warm}}
  end

  @impl true
  def handle_continue(:warm, state) do
    load()
    {:noreply, state}
  end

  @impl true
  def handle_call(:refresh, _from, state), do: {:reply, load(), state}

  def handle_call(:clear, _from, state) do
    :ets.delete(@table, @key)
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:refresh, state) do
    load()
    {:noreply, state}
  end

  defp load do
    map = published_by_code()
    :ets.insert(@table, {@key, map})
    map
  end

  # Tolerates a missing DB connection (e.g. boot before the test sandbox is
  # checked out): an empty cache is refreshed on first real access.
  defp published_by_code do
    Tables.published_by_code()
  rescue
    error ->
      Logger.debug("TableCache warm skipped: #{inspect(error)}")
      %{}
  end
end
