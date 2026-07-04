defmodule Sahla.Cities.City do
  @moduledoc """
  A Moroccan city of circulation — a core RC rating factor and funnel field
  (§3.1, §5.2). `risk_zone` (1..3) is an underwriting judgement; seeds set a
  provisional value pending broker confirmation.
  """
  use Sahla.Schema

  import Ecto.Changeset

  schema "cities" do
    field :name_fr, :string
    field :name_ar, :string
    field :region, :string
    field :risk_zone, :integer

    timestamps()
  end

  def changeset(city, attrs) do
    city
    |> cast(attrs, [:name_fr, :name_ar, :region, :risk_zone])
    |> validate_required([:name_fr, :name_ar, :region, :risk_zone])
    |> validate_inclusion(:risk_zone, 1..3)
    |> check_constraint(:risk_zone, name: :cities_risk_zone_must_be_valid)
    |> unique_constraint(:name_fr)
  end
end
