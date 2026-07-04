defmodule Sahla.Directory.Insurer do
  @moduledoc """
  An insurer (compagnie d'assurance) whose products appear in comparisons.

  `active` is an **admin-only** flag and is deliberately absent from
  `changeset/2` — only `admin_changeset/2` may set it, so a user-facing
  changeset can never flip an insurer live (§ PII/admin discipline).
  """
  use Sahla.Schema

  import Ecto.Changeset

  schema "insurers" do
    field :slug, :string
    field :name_fr, :string
    field :name_ar, :string
    field :logo_path, :string
    field :acaps_ref, :string
    field :phone, :string
    field :rating, :decimal
    field :active, :boolean, default: false
    field :position, :integer, default: 0

    has_many :products, Sahla.Directory.Product

    timestamps()
  end

  @doc """
  Safe changeset for descriptive fields. Never casts the admin-only `:active`
  or ordering `:position` fields.
  """
  def changeset(insurer, attrs) do
    insurer
    |> cast(attrs, [:slug, :name_fr, :name_ar, :logo_path, :acaps_ref, :phone, :rating])
    |> validate_required([:slug, :name_fr, :name_ar])
    |> validate_number(:rating, greater_than_or_equal_to: 0, less_than_or_equal_to: 5)
    |> unique_constraint(:slug)
  end

  @doc "Admin changeset: everything in `changeset/2` plus `:active` and `:position`."
  def admin_changeset(insurer, attrs) do
    insurer
    |> changeset(attrs)
    |> cast(attrs, [:active, :position])
  end
end
