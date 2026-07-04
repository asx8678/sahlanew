defmodule Sahla.Directory do
  @moduledoc """
  Read/query boundary for the insurer/product/guarantee catalog (§7.2, §8).

  Every "newest-first"-style query carries a `desc: :id` tiebreaker because
  timestamps are only second-precision (see `Sahla.Schema`).
  """
  import Ecto.Query

  alias Sahla.Directory.{Guarantee, Insurer, Product}
  alias Sahla.Repo

  @doc "All insurers ordered by curated position, then newest first."
  def list_insurers do
    Insurer
    |> order_by([i], asc: i.position, desc: i.id)
    |> Repo.all()
  end

  @doc "Only active insurers, for public-facing pages."
  def list_active_insurers do
    Insurer
    |> where([i], i.active == true)
    |> order_by([i], asc: i.position, desc: i.id)
    |> Repo.all()
  end

  def get_insurer!(id), do: Repo.get!(Insurer, id)

  def get_insurer_by_slug(slug), do: Repo.get_by(Insurer, slug: slug)

  @doc """
  Idempotently creates or updates an insurer keyed by `slug` (admin changeset, so
  seeds/admin can set `active`/`position`). Safe to call repeatedly.
  """
  def upsert_insurer(attrs) do
    (get_insurer_by_slug(attrs[:slug] || attrs["slug"]) || %Insurer{})
    |> Insurer.admin_changeset(attrs)
    |> Repo.insert_or_update()
  end

  @doc "Idempotently creates or updates a guarantee keyed by `code`."
  def upsert_guarantee(attrs) do
    (Repo.get_by(Guarantee, code: attrs[:code] || attrs["code"]) || %Guarantee{})
    |> Guarantee.changeset(attrs)
    |> Repo.insert_or_update()
  end

  @doc "All products, ordered by French name with a newest-first tiebreaker."
  def list_products do
    Product
    |> order_by([p], asc: p.name_fr, desc: p.id)
    |> Repo.all()
  end

  def list_products_for_insurer(insurer_id) do
    Product
    |> where([p], p.insurer_id == ^insurer_id)
    |> order_by([p], asc: p.name_fr, desc: p.id)
    |> Repo.all()
  end

  def get_product!(id), do: Repo.get!(Product, id)

  @doc "All guarantees ordered by code."
  def list_guarantees do
    Guarantee
    |> order_by([g], asc: g.code)
    |> Repo.all()
  end
end
