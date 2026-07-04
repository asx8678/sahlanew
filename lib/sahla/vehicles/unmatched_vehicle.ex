defmodule Sahla.Vehicles.UnmatchedVehicle do
  @moduledoc """
  A vehicle a driver typed as free text because it is absent from the catalog
  (§10.5). We keep it as a demand signal and an admin resolution queue — **only
  vehicle descriptors, never funnel contact PII**.

  Rows dedupe on `dedup_key` (normalized make|model|version); a repeat sighting
  increments `occurrences`. `resolved_version_id` links to the catalog once an
  admin maps it.
  """
  use Sahla.Schema

  import Ecto.Changeset

  @statuses [:pending, :resolved, :ignored]

  schema "unmatched_vehicles" do
    field :raw_make, :string
    field :raw_model, :string
    field :raw_version, :string
    field :dedup_key, :string
    field :fiscal_power, :integer
    field :fuel, :string
    field :occurrences, :integer, default: 1
    field :status, Ecto.Enum, values: @statuses, default: :pending

    belongs_to :resolved_version, Sahla.Vehicles.Version

    timestamps()
  end

  def statuses, do: @statuses

  @doc "Insert changeset for a sighting."
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:raw_make, :raw_model, :raw_version, :dedup_key, :fiscal_power, :fuel])
    |> validate_required([:dedup_key])
    |> unique_constraint(:dedup_key)
  end

  @doc "Admin resolution: set status and (for `:resolved`) the mapped version."
  def status_changeset(entry, attrs) do
    entry
    |> cast(attrs, [:status, :resolved_version_id])
    |> validate_required([:status])
    |> assoc_constraint(:resolved_version)
    |> check_constraint(:status, name: :unmatched_vehicles_status_must_be_valid)
  end
end
