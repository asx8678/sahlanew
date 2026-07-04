defmodule Sahla.Directory.Guarantee do
  @moduledoc """
  A guarantee (garantie) — one of a fixed, closed list of coverage codes.

  `codes/0` is the single source of truth for the 10 valid codes (§8), reused by
  `Sahla.Directory.ProductGuarantee` and mirrored by a DB `CHECK` constraint.
  """
  use Sahla.Schema

  import Ecto.Changeset

  @codes [
    :rc,
    :vol,
    :incendie,
    :bris_glace,
    :pta,
    :defense_recours,
    :assistance,
    :individuelle,
    :evenements_climatiques,
    :evcat
  ]

  schema "guarantees" do
    field :code, Ecto.Enum, values: @codes
    field :name_fr, :string
    field :name_ar, :string
    field :description_fr, :string
    field :description_ar, :string

    timestamps()
  end

  @doc "The canonical list of valid guarantee codes."
  def codes, do: @codes

  def changeset(guarantee, attrs) do
    guarantee
    |> cast(attrs, [:code, :name_fr, :name_ar, :description_fr, :description_ar])
    |> validate_required([:code, :name_fr, :name_ar])
    |> check_constraint(:code, name: :guarantees_code_must_be_valid)
    |> unique_constraint(:code)
  end
end
