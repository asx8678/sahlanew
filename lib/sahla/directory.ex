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

  @doc """
  Idempotently seeds the minimal catalog needed by the rating engine if any
  piece is missing: 8 insurers, the 10 canonical guarantees, and 3 products
  (RC / Tiers Étendu / Tous Risques) per insurer. Existing rows are never
  overwritten, so this is safe to call repeatedly.
  """
  def ensure_seed_catalog! do
    ensure_insurers()
    ensure_guarantees()
    ensure_products()
  end

  def get_insurer!(id), do: Repo.get!(Insurer, id)

  def get_insurer_by_slug(slug), do: Repo.get_by(Insurer, slug: slug)

  @doc """
  Active insurer by `slug` for public profile pages. Inactive insurers are
  invisible to the public path (returns `nil`), so an inactive or missing slug
  renders the branded 404 rather than a private profile.
  """
  def get_active_insurer_by_slug(slug) do
    Insurer
    |> where([i], i.slug == ^slug and i.active == true)
    |> Repo.one()
  end

  @default_insurers [
    %{slug: "wafa", name_fr: "Wafa Assurance", name_ar: "وفا للتأمين", position: 1},
    %{slug: "rma", name_fr: "RMA Watanya", name_ar: "الوطنية للتأمين", position: 2},
    %{slug: "sanlam", name_fr: "Sanlam Maroc", name_ar: "سنلام المغرب", position: 3},
    %{slug: "axa", name_fr: "AXA Assurance Maroc", name_ar: "أكسا للتأمين المغرب", position: 4},
    %{slug: "atlantasanad", name_fr: "AtlantaSanad", name_ar: "أطلنطا سند", position: 5},
    %{slug: "allianz", name_fr: "Allianz Maroc", name_ar: "أليانز المغرب", position: 6},
    %{slug: "mamda", name_fr: "MAMDA-MCMA", name_ar: "مامدا-مكما", position: 7},
    %{
      slug: "cat",
      name_fr: "CAT Assurances",
      name_ar: "الشركة المغربية لتأمين النقل",
      position: 8
    }
  ]

  @default_guarantees [
    %{code: :rc, name_fr: "Responsabilité civile", name_ar: "المسؤولية المدنية"},
    %{code: :vol, name_fr: "Vol", name_ar: "السرقة"},
    %{code: :incendie, name_fr: "Incendie", name_ar: "الحريق"},
    %{code: :bris_glace, name_fr: "Bris de glace", name_ar: "تكسر الزجاج"},
    %{code: :pta, name_fr: "Personnes transportées", name_ar: "الأشخاص المنقولون"},
    %{code: :defense_recours, name_fr: "Défense et recours", name_ar: "الدفاع والمطالبة"},
    %{code: :assistance, name_fr: "Assistance", name_ar: "المساعدة"},
    %{code: :individuelle, name_fr: "Individuelle accident", name_ar: "الحوادث الفردية"},
    %{
      code: :evenements_climatiques,
      name_fr: "Événements climatiques",
      name_ar: "الظواهر المناخية"
    },
    %{code: :evcat, name_fr: "Événements catastrophiques", name_ar: "الأحداث الكارثية"}
  ]

  @formula_labels %{
    "rc" => {"RC", "المسؤولية المدنية"},
    "tiers_etendu" => {"Tiers Étendu", "الغير الموسع"},
    "tous_risques" => {"Tous Risques", "جميع الأخطار"}
  }

  defp ensure_insurers do
    for attrs <- @default_insurers do
      if is_nil(get_insurer_by_slug(attrs.slug)) do
        %Insurer{}
        |> Insurer.admin_changeset(Map.put(attrs, :active, true))
        |> Repo.insert!()
      end
    end
  end

  defp ensure_guarantees do
    for attrs <- @default_guarantees do
      if is_nil(Repo.get_by(Guarantee, code: attrs.code)) do
        %Guarantee{}
        |> Guarantee.changeset(attrs)
        |> Repo.insert!()
      end
    end
  end

  defp ensure_products do
    for attrs <- @default_insurers,
        formula <- Product.formulas() do
      insurer = get_insurer_by_slug(attrs.slug)

      unless product_exists?(insurer.id, formula) do
        {label_fr, label_ar} = Map.fetch!(@formula_labels, Atom.to_string(formula))

        %Product{}
        |> Product.admin_changeset(%{
          insurer_id: insurer.id,
          kind: :auto,
          formula: formula,
          name_fr: "#{attrs.name_fr} #{label_fr}",
          name_ar: "#{attrs.name_ar} #{label_ar}",
          active: true
        })
        |> Repo.insert!()
      end
    end
  end

  defp product_exists?(insurer_id, formula) do
    Product
    |> where([p], p.insurer_id == ^insurer_id and p.kind == :auto and p.formula == ^formula)
    |> Repo.exists?()
  end

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

  @doc """
  Active products for `insurer_id` with their guarantee matrix preloaded, for
  the public profile page. Inactive products are hidden from the public path.
  """
  def list_public_products_for_insurer(insurer_id) do
    Product
    |> where([p], p.insurer_id == ^insurer_id and p.active == true)
    |> order_by([p], asc: p.name_fr, desc: p.id)
    |> preload([p], [:product_guarantees])
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
