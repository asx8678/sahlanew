defmodule Sahla.Settings.Cache do
  @moduledoc """
  In-memory cache for `Sahla.Settings` (§10.9). Settings are read on hot paths
  (feature-flag gates, brand name, disclaimers), so reads are served from a
  public ETS table — a single lookup, no GenServer round-trip.

  The GenServer owns the table, warms it from the DB on boot, and subscribes to
  the `"settings"` PubSub topic so a write on any node refreshes every node's
  cache. Writes go through `Sahla.Settings.put/2`, which persists, updates the
  local ETS entry and broadcasts the invalidation.
  """
  use GenServer

  require Logger

  alias Sahla.Settings.Store

  @table :sahla_settings
  @topic "settings"

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc "Reads a cached value by key, or `default` when absent."
  def get(key, default \\ nil) do
    case :ets.lookup(@table, key) do
      [{^key, value}] -> value
      [] -> default
    end
  rescue
    ArgumentError -> default
  end

  @doc "Writes `key`/`value` to the local ETS entry and broadcasts the change."
  def put(key, value) do
    :ets.insert(@table, {key, value})
    Phoenix.PubSub.broadcast(Sahla.PubSub, @topic, {:settings_changed, key, value})
    :ok
  end

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
    warm()
    {:noreply, state}
  end

  @impl true
  def handle_call(:clear, _from, state) do
    :ets.delete_all_objects(@table)
    {:reply, :ok, state}
  end

  @impl true
  def handle_info({:settings_changed, key, value}, state) do
    :ets.insert(@table, {key, value})
    {:noreply, state}
  end

  # Tolerates a missing DB connection at boot (e.g. before the test sandbox is
  # checked out): the cache fills as settings are written/read.
  defp warm do
    for {key, value} <- Store.all(), do: :ets.insert(@table, {key, value})
  rescue
    error ->
      Logger.debug("Settings cache warm skipped: #{inspect(error)}")
      :ok
  end
end
