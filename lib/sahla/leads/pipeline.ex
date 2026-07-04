defmodule Sahla.Leads.Pipeline do
  @moduledoc """
  Round-robin auto-assignment of new leads across active agents (§10.2, §14),
  keeping first-touch fast and fair. Each agent has a configurable open-lead cap
  (from settings); leads that would exceed every agent's cap stay in the
  unassigned pool rather than overflowing anyone.

  The selection (`pick/2`) is a pure function over an agent-load snapshot, so it
  is deterministic and property-testable. `reassign/3` is a manual override,
  audited via `Sahla.Audit` and broadcast so the kanban updates live.
  """
  import Ecto.Query, only: [from: 2]

  alias Sahla.Accounts.Admin
  alias Sahla.Audit
  alias Sahla.Leads
  alias Sahla.Leads.Lead
  alias Sahla.Repo
  alias Sahla.Settings

  @cap_key "agent_open_lead_cap"
  @default_cap 20
  # A lead is "open" until it reaches a terminal status.
  @terminal_statuses [:gagne, :perdu]

  @doc """
  Auto-assigns `lead` to the least-loaded active agent still under the open-lead
  cap. Returns `{:ok, lead}` — unchanged (left in the pool) when every agent is
  at cap or there are no active agents.
  """
  def auto_assign(%Lead{} = lead) do
    case pick(agent_loads(), cap()) do
      nil -> {:ok, lead}
      admin_id -> assign(lead, admin_id)
    end
  end

  @doc """
  Pure selection: the `admin_id` of the least-loaded agent below `cap`, ties
  broken by smallest id for determinism; `nil` when none qualify. `loads` is a
  list of `%{admin_id:, open_count:}`.
  """
  def pick(loads, cap) do
    loads
    |> Enum.filter(fn %{open_count: count} -> count < cap end)
    |> Enum.min_by(fn %{open_count: count, admin_id: id} -> {count, id} end, fn -> nil end)
    |> case do
      nil -> nil
      %{admin_id: admin_id} -> admin_id
    end
  end

  @doc "Assigns `lead` to `admin_id` and broadcasts `:updated`."
  def assign(%Lead{} = lead, admin_id) do
    with {:ok, updated} <-
           lead |> Lead.assignment_changeset(%{assigned_admin_id: admin_id}) |> Repo.update() do
      Leads.broadcast_update(updated)
      {:ok, updated}
    end
  end

  @doc """
  Manually reassigns `lead` to `new_admin_id`, writing an audit entry in the same
  transaction and broadcasting `:updated`. `opts`: `:actor_id` (the admin doing
  it), `:ip`.
  """
  def reassign(%Lead{} = lead, new_admin_id, opts \\ []) do
    multi =
      Ecto.Multi.new()
      |> Ecto.Multi.update(
        :lead,
        Lead.assignment_changeset(lead, %{assigned_admin_id: new_admin_id})
      )
      |> Audit.log_multi(%{
        admin_id: Keyword.get(opts, :actor_id),
        action: "reassign",
        entity: "lead",
        entity_id: lead.id,
        before: %{"assigned_admin_id" => lead.assigned_admin_id},
        after: %{"assigned_admin_id" => new_admin_id},
        ip: Keyword.get(opts, :ip)
      })

    case Repo.transaction(multi) do
      {:ok, %{lead: updated}} ->
        Leads.broadcast_update(updated)
        {:ok, updated}

      {:error, :lead, changeset, _changes} ->
        {:error, changeset}
    end
  end

  @doc "The current open-lead snapshot for every active agent, including idle ones."
  def agent_loads do
    counts = open_counts()

    active_agent_ids()
    |> Enum.map(fn id -> %{admin_id: id, open_count: Map.get(counts, id, 0)} end)
  end

  defp active_agent_ids do
    Repo.all(from a in Admin, where: a.role == :agent and a.active == true, select: a.id)
  end

  defp open_counts do
    from(l in Lead,
      where: l.status not in @terminal_statuses and not is_nil(l.assigned_admin_id),
      group_by: l.assigned_admin_id,
      select: {l.assigned_admin_id, count(l.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp cap, do: Settings.get(@cap_key, @default_cap)
end
