defmodule Sahla.Audit do
  @moduledoc """
  Append-only audit trail (§10.10, §12) for CNDP/ACAPS defensibility: every admin
  mutation and consent leaves an immutable record.

  `log/1` writes one entry; `log_multi/2` composes the write into an `Ecto.Multi`
  so the entry commits atomically with the mutation it describes. There is no
  update or delete path — a DB trigger enforces immutability. `before`/`after`
  are stored as non-PII projections (`Sahla.Security.SafeRaw`). Retention is five
  years, later enforced by an Oban maintenance job.
  """
  import Ecto.Query, only: [from: 2]

  alias Sahla.Audit.Entry
  alias Sahla.Repo

  @doc "Persists a single audit entry. Returns `{:ok, entry}` or `{:error, changeset}`."
  def log(attrs) do
    %Entry{}
    |> Entry.changeset(Map.new(attrs))
    |> Repo.insert()
  end

  @doc """
  Adds the audit insert to `multi`, so the entry commits in the same transaction
  as the mutation. Each call uses a unique step name, so several mutations can be
  audited within one multi.
  """
  def log_multi(multi, attrs) do
    changeset = Entry.changeset(%Entry{}, Map.new(attrs))
    Ecto.Multi.insert(multi, {:audit_entry, System.unique_integer([:positive])}, changeset)
  end

  @doc "Most recent audit entries, newest-first with a `desc: :id` tiebreaker."
  def recent(limit \\ 100) do
    Repo.all(from e in Entry, order_by: [desc: e.at, desc: e.id], limit: ^limit)
  end

  @doc "Audit entries for a specific entity, newest-first."
  def for_entity(entity, entity_id) do
    Repo.all(
      from e in Entry,
        where: e.entity == ^entity and e.entity_id == ^entity_id,
        order_by: [desc: e.at, desc: e.id]
    )
  end
end
