defmodule Sahla.Vehicles.Model do
  @moduledoc "A vehicle model (modèle) under a make, e.g. Clio. Searched by trigram on `name`."
  use Sahla.Schema

  import Ecto.Changeset

  schema "vehicle_models" do
    field :name, :string

    belongs_to :make, Sahla.Vehicles.Make
    has_many :versions, Sahla.Vehicles.Version

    timestamps()
  end

  def changeset(model, attrs) do
    model
    |> cast(attrs, [:make_id, :name])
    |> validate_required([:make_id, :name])
    |> assoc_constraint(:make)
    |> unique_constraint([:make_id, :name])
  end
end
