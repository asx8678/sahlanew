defmodule Sahla.Audit.Entry do
  @moduledoc """
  One immutable audit record (§10.10, §12): who (`admin_id`) did what (`action`)
  to which record (`entity`/`entity_id`), with non-PII `before`/`after`
  projections, the request `ip` and the event time `at`.

  Append-only — there is no update/delete changeset, and a DB trigger rejects
  UPDATE/DELETE at the row level. `before`/`after` are always run through
  `Sahla.Security.SafeRaw`, so a raw encrypted field or external payload can
  never leak into the trail.
  """
  use Sahla.Schema

  import Ecto.Changeset

  alias Sahla.Security.SafeRaw

  schema "audit_entries" do
    field :action, :string
    field :entity, :string
    field :entity_id, :string
    field :before, :map, default: %{}
    field :after, :map, default: %{}
    field :ip, Sahla.Types.IP
    field :at, :utc_datetime

    belongs_to :admin, Sahla.Accounts.Admin
  end

  @doc "Builds an insert changeset, projecting `before`/`after` to non-PII maps."
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:admin_id, :action, :entity, :entity_id, :before, :after, :ip, :at])
    |> validate_required([:action, :entity])
    |> put_at()
    |> scrub(:before)
    |> scrub(:after)
    |> assoc_constraint(:admin)
  end

  defp put_at(changeset) do
    if get_field(changeset, :at) do
      changeset
    else
      put_change(changeset, :at, DateTime.truncate(DateTime.utc_now(), :second))
    end
  end

  defp scrub(changeset, field) do
    case get_change(changeset, field) do
      nil -> changeset
      value -> put_change(changeset, field, SafeRaw.safe_raw(value))
    end
  end
end
