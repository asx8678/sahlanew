defmodule Sahla.Directory.ProductGuarantee do
  @moduledoc """
  The coverage matrix row linking a `Product` to a guarantee `code`, with its
  ceiling/franchise in integer centimes (nullable per the broker's matrix).
  """
  use Sahla.Schema

  import Ecto.Changeset

  alias Sahla.Directory.Guarantee

  schema "product_guarantees" do
    field :guarantee_code, Ecto.Enum, values: Guarantee.codes()
    field :included, :boolean, default: true
    field :ceiling_centimes, :integer
    field :franchise_centimes, :integer
    field :notes_fr, :string
    field :notes_ar, :string

    belongs_to :product, Sahla.Directory.Product

    timestamps()
  end

  def changeset(product_guarantee, attrs) do
    product_guarantee
    |> cast(attrs, [
      :product_id,
      :guarantee_code,
      :included,
      :ceiling_centimes,
      :franchise_centimes,
      :notes_fr,
      :notes_ar
    ])
    |> validate_required([:product_id, :guarantee_code])
    |> validate_number(:ceiling_centimes, greater_than_or_equal_to: 0)
    |> validate_number(:franchise_centimes, greater_than_or_equal_to: 0)
    |> assoc_constraint(:product)
    |> foreign_key_constraint(:guarantee_code, name: :product_guarantees_guarantee_code_fkey)
    |> unique_constraint([:product_id, :guarantee_code])
  end
end
