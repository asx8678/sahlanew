defmodule Sahla.Vehicles.UnmatchedTest do
  use Sahla.DataCase, async: true

  alias Sahla.Vehicles
  alias Sahla.Vehicles.UnmatchedVehicle

  describe "record_unmatched/1" do
    test "records a new free-text vehicle with occurrences 1" do
      assert {:ok, entry} =
               Vehicles.record_unmatched(%{
                 raw_make: "BYD",
                 raw_model: "Dolphin",
                 raw_version: "Comfort"
               })

      assert entry.occurrences == 1
      assert entry.status == :pending
      assert entry.dedup_key == "byd|dolphin|comfort"
    end

    test "upserts by normalized key, incrementing occurrences on a repeat" do
      {:ok, first} = Vehicles.record_unmatched(%{raw_make: "BYD", raw_model: "Dolphin"})

      # different casing / spacing normalizes to the same key
      {:ok, second} =
        Vehicles.record_unmatched(%{raw_make: "  byd ", raw_model: "DOLPHIN", raw_version: nil})

      assert second.id == first.id
      assert second.occurrences == 2
      assert Repo.aggregate(UnmatchedVehicle, :count) == 1
    end
  end

  describe "list_unmatched/1" do
    test "returns pending entries by occurrences desc, then desc :id" do
      {:ok, _} = Vehicles.record_unmatched(%{raw_make: "B", raw_model: "2"})
      {:ok, _} = Vehicles.record_unmatched(%{raw_make: "B", raw_model: "2"})
      {:ok, thrice} = Vehicles.record_unmatched(%{raw_make: "B", raw_model: "2"})

      # two single-occurrence entries to exercise the id tiebreaker
      {:ok, c} = Vehicles.record_unmatched(%{raw_make: "C", raw_model: "3"})
      {:ok, d} = Vehicles.record_unmatched(%{raw_make: "D", raw_model: "4"})

      ids = Vehicles.list_unmatched() |> Enum.map(& &1.id)

      # most-requested first, then the two singles by desc id
      assert hd(ids) == thrice.id
      assert tl(ids) == [c.id, d.id] |> Enum.sort() |> Enum.reverse()
    end

    test "excludes resolved and ignored entries" do
      {:ok, a} = Vehicles.record_unmatched(%{raw_make: "A", raw_model: "1"})
      {:ok, b} = Vehicles.record_unmatched(%{raw_make: "B", raw_model: "2"})

      {:ok, _} = Vehicles.ignore_unmatched(a)
      assert Vehicles.list_unmatched() |> Enum.map(& &1.id) == [b.id]
    end
  end

  describe "status transitions" do
    test "ignore_unmatched sets status to ignored" do
      {:ok, entry} = Vehicles.record_unmatched(%{raw_make: "A", raw_model: "1"})
      assert {:ok, ignored} = Vehicles.ignore_unmatched(entry)
      assert ignored.status == :ignored
    end

    test "resolve_unmatched with a nil version still records the resolution" do
      {:ok, entry} = Vehicles.record_unmatched(%{raw_make: "A", raw_model: "1"})
      assert {:ok, resolved} = Vehicles.resolve_unmatched(entry, nil)
      assert resolved.status == :resolved
      assert resolved.resolved_version_id == nil
    end
  end
end
