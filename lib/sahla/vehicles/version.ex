defmodule Sahla.Vehicles.Version do
  @moduledoc """
  A specific version (finition) of a model. Carries `fiscal_power` — the dominant
  RC rating factor (§3.1) that prefills the funnel — plus `fuel`, `seats`, the
  new-vehicle value in centimes, and the `years` span it was produced.
  """
  use Sahla.Schema

  import Ecto.Changeset

  alias Sahla.Vehicles.YearRange

  @fuels [:essence, :diesel, :hybride, :electrique]

  schema "vehicle_versions" do
    field :name, :string
    field :fiscal_power, :integer
    field :fuel, Ecto.Enum, values: @fuels
    field :seats, :integer
    field :new_value_centimes, :integer
    field :years, YearRange

    belongs_to :model, Sahla.Vehicles.Model

    timestamps()
  end

  @doc "Valid fuel types."
  def fuels, do: @fuels

  def changeset(version, attrs) do
    version
    |> cast(attrs, [:model_id, :name, :fiscal_power, :fuel, :seats, :new_value_centimes, :years])
    |> validate_required([:model_id, :name])
    |> validate_number(:fiscal_power, greater_than: 0)
    |> validate_number(:seats, greater_than: 0)
    |> validate_number(:new_value_centimes, greater_than_or_equal_to: 0)
    |> assoc_constraint(:model)
    |> check_constraint(:fuel, name: :vehicle_versions_fuel_must_be_valid)
    |> unique_constraint([:model_id, :name])
  end
end
