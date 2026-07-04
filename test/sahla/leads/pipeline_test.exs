defmodule Sahla.Leads.PipelineTest do
  # async: false — settings cap, PubSub and audit are shared/global.
  use Sahla.DataCase, async: false

  alias Sahla.Accounts
  alias Sahla.Audit
  alias Sahla.Leads
  alias Sahla.Leads.Pipeline
  alias Sahla.Quoting
  alias Sahla.Settings
  alias Sahla.Settings.Cache

  @password "correct-horse-battery-staple-42"

  setup do
    Cache.clear()
    :ok
  end

  defp agent(opts \\ []) do
    {:ok, admin} =
      Accounts.register_admin(%{
        email: "agent-#{System.unique_integer([:positive])}@sahla.ma",
        password: @password,
        role: :agent
      })

    if Keyword.get(opts, :active, true) do
      admin
    else
      Repo.update!(Ecto.Changeset.change(admin, active: false))
    end
  end

  defp new_lead do
    {:ok, lead} = Leads.create_from_quote(quote_fixture())
    lead
  end

  defp quote_fixture do
    {:ok, quote} = Quoting.create_quote()
    quote
  end

  describe "pick/2 (pure)" do
    test "chooses the least-loaded agent under cap, ties by smallest id" do
      loads = [
        %{admin_id: "b", open_count: 2},
        %{admin_id: "a", open_count: 1},
        %{admin_id: "c", open_count: 1}
      ]

      assert Pipeline.pick(loads, 5) == "a"
    end

    test "returns nil when every agent is at cap" do
      loads = [%{admin_id: "a", open_count: 5}, %{admin_id: "b", open_count: 5}]
      assert Pipeline.pick(loads, 5) == nil
    end

    test "returns nil when there are no agents" do
      assert Pipeline.pick([], 5) == nil
    end
  end

  describe "auto-assignment via create_from_quote" do
    test "distributes new leads round-robin across active agents" do
      a1 = agent()
      a2 = agent()

      assigned = for _ <- 1..4, do: new_lead().assigned_admin_id
      counts = Enum.frequencies(assigned)

      assert counts[a1.id] == 2
      assert counts[a2.id] == 2
    end

    test "leaves leads in the pool when every agent is at the settings cap" do
      {:ok, _} = Settings.put("agent_open_lead_cap", 1)
      a1 = agent()

      assert new_lead().assigned_admin_id == a1.id
      assert new_lead().assigned_admin_id == nil
    end

    test "the cap is read from settings (3 assigned, then pool)" do
      {:ok, _} = Settings.put("agent_open_lead_cap", 3)
      a = agent()

      assigned = for _ <- 1..4, do: new_lead().assigned_admin_id
      assert Enum.count(assigned, &(&1 == a.id)) == 3
      assert Enum.count(assigned, &is_nil/1) == 1
    end

    test "inactive agents never receive leads" do
      _inactive = agent(active: false)
      assert new_lead().assigned_admin_id == nil
    end
  end

  describe "reassign/3" do
    test "changes the assignee, writes an audit entry and broadcasts :updated" do
      _a1 = agent()
      a2 = agent()
      actor = agent()
      lead = new_lead()

      Leads.subscribe()

      assert {:ok, updated} =
               Pipeline.reassign(lead, a2.id, actor_id: actor.id, ip: "196.200.1.1")

      assert updated.assigned_admin_id == a2.id
      assert_receive {:lead, :updated, _id}

      entries = Audit.for_entity("lead", lead.id)
      assert Enum.any?(entries, &(&1.action == "reassign" and &1.admin_id == actor.id))
    end
  end
end
