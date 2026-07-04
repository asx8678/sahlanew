defmodule Sahla.Rating.Table do
  @moduledoc """
  A versioned rating table (§9.1/§9.2): all rating numbers live here as jsonb so
  ops recalibrate without deploys. Each `code` has a required `data` shape
  (`Sahla.Rating.Table.Schema`), a monotonic `version`, and a lifecycle
  `status` (draft → published → archived).

  Governance rules enforced by the changesets:

    * `data` is validated against the per-code schema on every write.
    * `checksum` is recomputed deterministically (SHA256 of canonicalized JSON)
      so identical data always yields the same digest.
    * Published/archived rows are immutable — content edits are rejected.
    * `status` and `published_by_id` are **admin-only**: the public `changeset/2`
      never casts them; only `publish_changeset/2` does (Lessons).
  """
  use Sahla.Schema

  import Ecto.Changeset

  alias Sahla.Rating.Table.Schema

  @codes ~w(rc_base usage_factor city_factor crm option_pricing insurer_positioning taxes_fees)a
  @statuses ~w(draft published archived)a
  @content_fields [:code, :version, :effective_from, :data, :notes]

  schema "rate_tables" do
    field :code, Ecto.Enum, values: @codes
    field :version, :integer
    field :status, Ecto.Enum, values: @statuses, default: :draft
    field :effective_from, :date
    field :data, :map, default: %{}
    field :checksum, :string
    field :notes, :string
    # FK to admins is added when Accounts.Admin lands (r5o.3); kept as a plain
    # binary_id for now so this schema doesn't depend on that table.
    field :published_by_id, :binary_id

    timestamps()
  end

  @doc "Valid table codes."
  def codes, do: @codes

  @doc """
  Content changeset. Validates the per-code `data` shape, recomputes the
  checksum, and rejects edits to a non-draft (published/archived) row. Never
  casts `status` or `published_by_id`.
  """
  def changeset(table, attrs) do
    table
    |> cast(attrs, @content_fields)
    |> validate_required([:code, :version, :data])
    |> validate_number(:version, greater_than: 0)
    |> guard_immutable(table)
    |> validate_data()
    |> put_checksum()
    |> unique_constraint([:code, :version])
    |> check_constraint(:code, name: :rate_tables_code_must_be_valid)
  end

  @doc """
  Privileged changeset for the publish flow: everything in `changeset/2` plus
  the admin-only `status` and `published_by_id`.
  """
  def publish_changeset(table, attrs) do
    table
    |> changeset(attrs)
    |> cast(attrs, [:status, :published_by_id])
    |> check_constraint(:status, name: :rate_tables_status_must_be_valid)
  end

  @doc """
  Deterministic checksum of `data`: SHA256 over canonicalized JSON (recursively
  key-sorted), so equal data always hashes identically regardless of key order.
  """
  @spec checksum(map()) :: String.t()
  def checksum(data) do
    :sha256 |> :crypto.hash(canonical(data)) |> Base.encode16(case: :lower)
  end

  defp guard_immutable(changeset, %__MODULE__{status: status})
       when status in [:published, :archived] do
    if map_size(changeset.changes) > 0 do
      add_error(changeset, :base, "a #{status} table is immutable; create a new version instead")
    else
      changeset
    end
  end

  defp guard_immutable(changeset, _table), do: changeset

  defp validate_data(changeset) do
    code = get_field(changeset, :code)
    data = get_field(changeset, :data)

    if is_nil(code) or is_nil(data) do
      changeset
    else
      case Schema.validate(code, data) do
        :ok -> changeset
        {:error, message} -> add_error(changeset, :data, message)
      end
    end
  end

  defp put_checksum(changeset) do
    case get_change(changeset, :data) do
      nil -> changeset
      data -> put_change(changeset, :checksum, checksum(data))
    end
  end

  defp canonical(data) when is_map(data) do
    inner =
      data
      |> Enum.sort_by(fn {k, _} -> to_string(k) end)
      |> Enum.map_join(",", fn {k, v} -> Jason.encode!(to_string(k)) <> ":" <> canonical(v) end)

    "{" <> inner <> "}"
  end

  defp canonical(data) when is_list(data),
    do: "[" <> Enum.map_join(data, ",", &canonical/1) <> "]"

  defp canonical(data), do: Jason.encode!(data)
end
