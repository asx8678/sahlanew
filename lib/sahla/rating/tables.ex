defmodule Sahla.Rating.Tables do
  @moduledoc """
  Resolution boundary for versioned rate tables (§9.2). Reads go through
  `Sahla.Rating.TableCache` (ETS), so `resolve/2` and `load_all/1` avoid the
  database on a warm cache; publishing refreshes the cache.
  """
  import Ecto.Query

  alias Sahla.Rating.{Table, TableCache}
  alias Sahla.Repo

  @topic "rating:tables"

  @doc """
  Publishes a draft `table` effective on `effective_from`: archives the prior
  published row of the same code and flips this one to `published`, atomically,
  then refreshes the cache.
  """
  def publish(%Table{} = table, %Date{} = effective_from) do
    result =
      Repo.transaction(fn ->
        now = DateTime.truncate(DateTime.utc_now(), :second)

        from(t in Table, where: t.code == ^table.code and t.status == :published)
        |> Repo.update_all(set: [status: :archived, updated_at: now])

        table
        |> Table.publish_changeset(%{status: :published, effective_from: effective_from})
        |> Repo.update!()
      end)

    case result do
      {:ok, published} ->
        TableCache.refresh()
        Phoenix.PubSub.broadcast(Sahla.PubSub, @topic, :refresh)
        {:ok, published}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Returns the published table for `code` with the greatest `effective_from` on or
  before `on_date`, or `nil`. Draft and archived rows are ignored.
  """
  def resolve(code, on_date \\ Date.utc_today()) do
    TableCache.snapshot()
    |> Map.get(code, [])
    |> Enum.find(&effective_by?(&1, on_date))
  end

  @doc """
  Returns `%{code => data}` for all seven codes as of `on_date` (nil where no
  table is effective), for the rating engine to consume in one shot.
  """
  def load_all(on_date \\ Date.utc_today()) do
    snapshot = TableCache.snapshot()

    Map.new(Table.codes(), fn code ->
      row =
        snapshot
        |> Map.get(code, [])
        |> Enum.find(&effective_by?(&1, on_date))

      {code, row && row.data}
    end)
  end

  @doc false
  # Used by TableCache to (re)load the cache. The only read that touches Repo.
  def published_by_code do
    Table
    |> where([t], t.status == :published)
    |> order_by([t], desc: t.effective_from, desc: t.version, desc: t.id)
    |> Repo.all()
    |> Enum.group_by(& &1.code)
  end

  defp effective_by?(%Table{effective_from: nil}, _on_date), do: false
  defp effective_by?(%Table{effective_from: eff}, on_date), do: Date.compare(eff, on_date) != :gt
end
