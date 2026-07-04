defmodule Sahla.Rating.TablesTest do
  # async: false — the ETS cache and its GenServer are process-global, and the
  # GenServer queries Repo (needs the shared sandbox connection).
  use Sahla.DataCase, async: false

  alias Sahla.Rating.{Table, TableCache, Tables}

  @data %{
    rc_base: %{
      "bands" => [
        %{"cv_min" => 1, "cv_max" => 6, "fuel" => "essence", "annual_centimes" => 198_000}
      ]
    },
    usage_factor: %{"factors" => %{"personnel" => 1.0, "professionnel" => 1.2}},
    city_factor: %{"factors" => %{"1" => 0.9, "2" => 1.0, "3" => 1.15}},
    crm: %{
      "start" => 1.0,
      "floor" => 0.5,
      "ceiling" => 2.5,
      "clean_year_factor" => 0.9,
      "claim_factor" => 1.2
    },
    option_pricing: %{"options" => %{"vol" => %{"annual_centimes" => 5000}}},
    insurer_positioning: %{"wafa" => %{"rc" => 1.06, "tous_risques" => 0.97}},
    taxes_fees: %{
      "tax_rate" => 0.14,
      "fixed_fees_centimes" => 5000,
      "evcat" => %{"rate" => 0.05, "min_centimes" => 3000}
    }
  }

  setup do
    on_exit(fn -> TableCache.clear() end)
    :ok
  end

  defp insert(code, version, status, effective_from) do
    %Table{}
    |> Table.publish_changeset(%{
      code: code,
      version: version,
      data: @data[code],
      status: status,
      effective_from: effective_from
    })
    |> Repo.insert!()
  end

  defp insert_draft(code, version) do
    %Table{}
    |> Table.changeset(%{code: code, version: version, data: @data[code]})
    |> Repo.insert!()
  end

  defp repo_query_count(fun) do
    ref = make_ref()
    parent = self()

    handler = fn _event, _measure, _meta, _config ->
      send(parent, {ref, :query})
    end

    :telemetry.attach({__MODULE__, ref}, [:sahla, :repo, :query], handler, nil)
    fun.()
    :telemetry.detach({__MODULE__, ref})

    count_messages(ref, 0)
  end

  defp count_messages(ref, acc) do
    receive do
      {^ref, :query} -> count_messages(ref, acc + 1)
    after
      0 -> acc
    end
  end

  describe "resolve/2" do
    test "returns the published row with greatest effective_from <= date, ignoring draft/archived" do
      insert(:rc_base, 1, :published, ~D[2026-01-01])
      insert(:rc_base, 2, :published, ~D[2026-06-01])
      insert(:rc_base, 3, :draft, ~D[2026-09-01])
      insert(:rc_base, 4, :archived, ~D[2025-01-01])
      TableCache.refresh()

      assert Tables.resolve(:rc_base, ~D[2026-07-01]).version == 2
      assert Tables.resolve(:rc_base, ~D[2026-03-01]).version == 1
      assert Tables.resolve(:rc_base, ~D[2025-12-31]) == nil
    end
  end

  describe "publish/2" do
    test "archives the prior published row of the same code and refreshes the cache" do
      {:ok, v1} = Tables.publish(insert_draft(:usage_factor, 1), ~D[2026-01-01])
      assert v1.status == :published

      {:ok, v2} = Tables.publish(insert_draft(:usage_factor, 2), ~D[2026-06-01])
      assert v2.status == :published

      assert Repo.get!(Table, v1.id).status == :archived
      # cache reflects the publish without a manual refresh
      assert Tables.resolve(:usage_factor, ~D[2026-07-01]).version == 2
    end
  end

  describe "cache behaviour" do
    test "a warm cache serves resolve without touching Repo; a cold cache loads once" do
      insert(:rc_base, 1, :published, ~D[2026-01-01])

      # cold: key absent -> loads from Repo
      TableCache.clear()
      assert repo_query_count(fn -> Tables.load_all(~D[2026-06-01]) end) > 0

      # warm: subsequent reads hit ETS only
      assert repo_query_count(fn -> Tables.resolve(:rc_base, ~D[2026-06-01]) end) == 0
      assert repo_query_count(fn -> Tables.load_all(~D[2026-06-01]) end) == 0
    end
  end

  describe "load_all/1" do
    test "returns a map covering all seven codes" do
      for code <- Table.codes(), do: insert(code, 1, :published, ~D[2026-01-01])
      TableCache.refresh()

      all = Tables.load_all(~D[2026-06-01])

      assert map_size(all) == 7
      assert Enum.sort(Map.keys(all)) == Enum.sort(Table.codes())
      assert all[:rc_base]["bands"]
      assert all[:taxes_fees]["evcat"]["rate"] == 0.05
    end
  end

  describe "consistency under concurrent publish" do
    test "load_all always returns the full seven-code set, never a partial one" do
      for code <- Table.codes(), do: insert(code, 1, :published, ~D[2026-01-01])
      TableCache.refresh()

      publisher = Task.async(fn -> Tables.publish(insert_draft(:rc_base, 2), ~D[2026-06-01]) end)

      readers =
        for _ <- 1..50 do
          Task.async(fn -> map_size(Tables.load_all(~D[2026-06-01])) end)
        end

      Task.await(publisher)
      assert Enum.all?(Task.await_many(readers), &(&1 == 7))
    end
  end
end
