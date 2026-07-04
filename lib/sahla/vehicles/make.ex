defmodule Sahla.Vehicles.Make do
  @moduledoc "A vehicle make (marque), e.g. Renault. `popular` surfaces common makes first."
  use Sahla.Schema

  import Ecto.Changeset

  schema "vehicle_makes" do
    field :name, :string
    field :popular, :boolean, default: false

    has_many :models, Sahla.Vehicles.Model

    timestamps()
  end

  def changeset(make, attrs) do
    make
    |> cast(attrs, [:name, :popular])
    |> validate_required([:name])
    |> unique_constraint(:name)
  end
end
