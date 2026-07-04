defmodule Sahla.Accounts.Policy do
  @moduledoc """
  The admin authorization matrix (§10) in one place, so the HTTP plug and the
  LiveView `on_mount` hook can never drift. Call sites ask about **capability
  atoms** (`:leads`, `:cms`, …) rather than raw role strings, so tweaking which
  role holds a capability is a one-line change here.

  Roles: `superadmin` (all capabilities), `ops`, `agent`, `editor`, `finance`.
  """

  # Capabilities only the superadmin holds.
  @superadmin_only [:manage_admins, :publish_rate_tables, :manage_legal_texts]

  # Capabilities per non-superadmin role.
  @role_capabilities %{
    ops: [:leads, :simulator, :erase_person],
    agent: [:leads_assigned],
    editor: [:cms],
    finance: [:finance_exports]
  }

  @all_capabilities Enum.uniq(
                      @superadmin_only ++
                        Enum.flat_map(@role_capabilities, fn {_role, caps} -> caps end)
                    )

  @doc "Every capability the system knows about."
  def all_capabilities, do: @all_capabilities

  @doc "The capabilities a role holds (superadmin holds them all)."
  def capabilities(:superadmin), do: @all_capabilities
  def capabilities(role), do: Map.get(@role_capabilities, role, [])

  @doc "Whether `role` is allowed `capability`."
  def can?(:superadmin, _capability), do: true
  def can?(role, capability), do: capability in capabilities(role)
end
