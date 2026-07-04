defmodule Sahla.Directory.Product do
  @moduledoc """
  A product (offre) sold by an insurer for a given `kind` and `formula`.

  `active` and `installments_available` are **admin-only** flags, absent from
  `changeset/2` and settable only via `admin_changeset/2`, so a user-facing
  changeset can never toggle them (§ PII/admin discipline).
  """
  use Sahla.Schema

  import Ecto.Changeset

  @kinds [:auto, :moto, :voyage, :habitation]
  @formulas [:rc, :tiers_etendu, :tous_risques]

  schema "products" do
    field :kind, Ecto.Enum, values: @kinds
    field :formula, Ecto.Enum, values: @formulas
    field :name_fr, :string
    field :name_ar, :string
    field :cg_document_path, :string
    field :installments_available, :boolean, default: false
    field :active, :boolean, default: false

    belongs_to :insurer, Sahla.Directory.Insurer
    has_many :product_guarantees, Sahla.Directory.ProductGuarantee

    timestamps()
  end

  @doc "Valid product kinds."
  def kinds, do: @kinds

  @doc "Valid product formulas."
  def formulas, do: @formulas

  @doc """
  Safe changeset for descriptive fields. Never casts the admin-only `:active`
  or `:installments_available` flags.
  """
  def changeset(product, attrs) do
    product
    |> cast(attrs, [:insurer_id, :kind, :formula, :name_fr, :name_ar, :cg_document_path])
    |> validate_required([:insurer_id, :kind, :formula, :name_fr, :name_ar])
    |> assoc_constraint(:insurer)
    |> check_constraint(:kind, name: :products_kind_must_be_valid)
    |> check_constraint(:formula, name: :products_formula_must_be_valid)
  end

  @doc "Admin changeset: `changeset/2` plus `:active` and `:installments_available`."
  def admin_changeset(product, attrs) do
    product
    |> changeset(attrs)
    |> cast(attrs, [:installments_available, :active])
  end
end
