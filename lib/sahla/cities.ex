defmodule Sahla.Cities do
  @moduledoc """
  Query boundary for the city catalog that feeds the funnel's city select and the
  rating engine's `city_factor` resolution (§3.1, §5.2).
  """
  import Ecto.Query

  alias Sahla.Cities.City
  alias Sahla.Repo

  @doc "All cities ordered for a funnel select (French name ascending)."
  def list_cities do
    City
    |> order_by([c], asc: c.name_fr)
    |> Repo.all()
  end

  def get_city!(id), do: Repo.get!(City, id)

  @doc "Idempotently creates or updates a city keyed by `name_fr`. Safe to re-run."
  def upsert_city(attrs) do
    (Repo.get_by(City, name_fr: attrs[:name_fr] || attrs["name_fr"]) || %City{})
    |> City.changeset(attrs)
    |> Repo.insert_or_update()
  end

  @doc "Fetches the `risk_zone` for a city, or `nil` if the city is unknown."
  def get_risk_zone(city_id) do
    City
    |> where([c], c.id == ^city_id)
    |> select([c], c.risk_zone)
    |> Repo.one()
  end
end
