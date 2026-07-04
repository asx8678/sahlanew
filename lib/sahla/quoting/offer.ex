defmodule Sahla.Quoting.Offer do
  @moduledoc """
  A persisted offer from a rating run (§8, §9.1) — the immutable record of a
  price we displayed. `breakdown` mirrors the engine's line itemization;
  `badges` and `rank` drive the results UI; `selected_at` is stamped when the
  user picks this offer (by a later flow, not here).
  """
  use Sahla.Schema

  import Ecto.Changeset

  @formulas [:rc, :tiers_etendu, :tous_risques]

  schema "offers" do
    field :formula, Ecto.Enum, values: @formulas
    field :annual_premium_centimes, :integer
    field :monthly_equiv_centimes, :integer
    field :breakdown, :map
    field :badges, {:array, :string}, default: []
    field :rank, :integer
    field :selected_at, :utc_datetime

    belongs_to :rating_run, Sahla.Rating.Run
    belongs_to :quote, Sahla.Quoting.Quote
    belongs_to :insurer, Sahla.Directory.Insurer
    belongs_to :product, Sahla.Directory.Product

    timestamps()
  end

  def changeset(offer, attrs) do
    offer
    |> cast(attrs, [
      :rating_run_id,
      :quote_id,
      :insurer_id,
      :product_id,
      :formula,
      :annual_premium_centimes,
      :monthly_equiv_centimes,
      :breakdown,
      :badges,
      :rank,
      :selected_at
    ])
    |> validate_required([:rating_run_id, :quote_id, :formula, :annual_premium_centimes])
    |> validate_number(:annual_premium_centimes, greater_than_or_equal_to: 0)
    |> assoc_constraint(:rating_run)
    |> assoc_constraint(:quote)
    |> check_constraint(:formula, name: :offers_formula_must_be_valid)
  end
end
