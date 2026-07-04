defmodule Sahla.AuditTest do
  use Sahla.DataCase, async: true

  alias Sahla.Accounts
  alias Sahla.Audit

  @password "correct-horse-battery-staple-42"

  defp admin_fixture do
    {:ok, admin} =
      Accounts.register_admin(%{
        email: "admin-#{System.unique_integer([:positive])}@sahla.ma",
        password: @password,
        role: :ops
      })

    admin
  end

  describe "log/1" do
    test "persists all fields" do
      admin = admin_fixture()

      {:ok, entry} =
        Audit.log(%{
          admin_id: admin.id,
          action: "update",
          entity: "lead",
          entity_id: "abc",
          ip: "196.200.1.1",
          before: %{"a" => 1},
          after: %{"a" => 2}
        })

      assert entry.admin_id == admin.id
      assert entry.action == "update"
      assert entry.entity == "lead"
      assert entry.entity_id == "abc"
      assert entry.ip == "196.200.1.1"
      assert entry.before == %{"a" => 1}
      assert entry.after == %{"a" => 2}
      assert entry.at
    end

    test "requires an action and entity" do
      assert {:error, changeset} = Audit.log(%{action: "x"})
      assert %{entity: ["can't be blank"]} = errors_on(changeset)
    end

    test "projects before/after through SafeRaw (no PII stored)" do
      {:ok, entry} =
        Audit.log(%{
          action: "update",
          entity: "lead",
          before: %{"status" => "nouveau", "phone" => "212612345678"},
          after: %{"status" => "contacte"}
        })

      assert entry.before == %{"status" => "nouveau"}
      refute Map.has_key?(entry.before, "phone")
    end
  end

  describe "log_multi/2" do
    test "commits the entry atomically with the mutation" do
      multi =
        Ecto.Multi.new()
        |> Ecto.Multi.run(:work, fn _repo, _ -> {:ok, :done} end)
        |> Audit.log_multi(%{action: "update", entity: "setting", entity_id: "x"})

      assert {:ok, _results} = Repo.transaction(multi)
      assert Enum.any?(Audit.recent(), &(&1.entity == "setting"))
    end

    test "rolls back the entry when a later multi step fails" do
      multi =
        Ecto.Multi.new()
        |> Audit.log_multi(%{action: "update", entity: "lead"})
        |> Ecto.Multi.run(:boom, fn _repo, _ -> {:error, :nope} end)

      assert {:error, :boom, :nope, _} = Repo.transaction(multi)
      assert Audit.recent() == []
    end
  end

  describe "recent/1 ordering" do
    defp log_at(at) do
      {:ok, entry} = Audit.log(%{action: "x", entity: "lead", at: at})
      entry
    end

    test "newest-first by at with a desc :id tiebreaker" do
      a = log_at(~U[2026-07-04 09:00:00Z])
      b = log_at(~U[2026-07-04 10:00:00Z])
      c = log_at(~U[2026-07-04 10:00:00Z])

      ids = Audit.recent() |> Enum.map(& &1.id)
      newest_two = [b.id, c.id] |> Enum.sort() |> Enum.reverse()
      assert ids == newest_two ++ [a.id]
    end
  end

  describe "append-only immutability (DB trigger)" do
    test "UPDATE is rejected" do
      {:ok, entry} = Audit.log(%{action: "x", entity: "lead"})

      assert_raise Postgrex.Error, ~r/append-only/, fn ->
        Repo.query!("UPDATE audit_entries SET action = 'tampered' WHERE id = $1", [
          Ecto.UUID.dump!(entry.id)
        ])
      end
    end

    test "DELETE is rejected" do
      {:ok, entry} = Audit.log(%{action: "x", entity: "lead"})

      assert_raise Postgrex.Error, ~r/append-only/, fn ->
        Repo.query!("DELETE FROM audit_entries WHERE id = $1", [Ecto.UUID.dump!(entry.id)])
      end
    end
  end
end
