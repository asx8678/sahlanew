defmodule Sahla.Quoting.Steps.Vehicle do
  @moduledoc """
  Step 1 — vehicle (§5.2). Pure embedded schema; no Repo.

  `vehicle_value_centimes` is required **only** when the chosen coverage formula
  values the vehicle (Tiers étendu / Tous risques). Because the formula is picked
  in step 3, it is supplied as context to `changeset/3` rather than being a field
  of this step.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Sahla.Quoting.{Enums, Steps}

  @required [:fiscal_power, :fuel, :usage, :city_id, :parking]
  @optional [
    :plate,
    :is_new_ww,
    :make_id,
    :model_id,
    :version_id,
    :first_registration,
    :vehicle_value_centimes
  ]

  @primary_key false
  embedded_schema do
    field :plate, :string
    field :is_new_ww, :boolean, default: false
    field :make_id, :binary_id
    field :model_id, :binary_id
    field :version_id, :binary_id
    field :fiscal_power, :integer
    field :fuel, Ecto.Enum, values: Enums.fuels()
    field :first_registration, :date
    field :vehicle_value_centimes, :integer
    field :usage, Ecto.Enum, values: Enums.usages()
    field :city_id, :binary_id
    field :parking, Ecto.Enum, values: Enums.parkings()
  end

  @doc """
  Validates step 1. `opts` may carry `:formula` (the step-3 choice) and `:today`
  (defaults to `Date.utc_today/0`) to drive the conditional value requirement and
  the registration-date check deterministically.
  """
  def changeset(vehicle, attrs, opts \\ []) do
    today = Keyword.get(opts, :today, Date.utc_today())
    formula = Keyword.get(opts, :formula)

    vehicle
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_number(:fiscal_power, greater_than: 0)
    |> Steps.validate_not_future(:first_registration, today)
    |> validate_vehicle_value(formula)
  end

  defp validate_vehicle_value(changeset, formula) do
    if formula in Enums.valued_formulas() do
      changeset
      |> validate_required([:vehicle_value_centimes])
      |> validate_number(:vehicle_value_centimes, greater_than: 0)
    else
      changeset
    end
  end
end
