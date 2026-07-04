defmodule Sahla.DirectoryTest do
  use Sahla.DataCase, async: true

  alias Sahla.Directory
  alias Sahla.Directory.{Guarantee, Insurer, Product, ProductGuarantee}

  defp insert_insurer(attrs \\ %{}) do
    defaults = %{
      slug: "ins-#{System.unique_integer([:positive])}",
      name_fr: "Assureur",
      name_ar: "مؤمِّن",
      active: true
    }

    %Insurer{}
    |> Insurer.admin_changeset(Map.merge(defaults, Map.new(attrs)))
    |> Repo.insert!()
  end

  defp insert_product(insurer, attrs \\ %{}) do
    defaults = %{
      insurer_id: insurer.id,
      kind: :auto,
      formula: :tous_risques,
      name_fr: "Formule",
      name_ar: "صيغة"
    }

    %Product{}
    |> Product.changeset(Map.merge(defaults, Map.new(attrs)))
    |> Repo.insert!()
  end

  defp insert_guarantee(code) do
    %Guarantee{}
    |> Guarantee.changeset(%{code: code, name_fr: "G", name_ar: "غ"})
    |> Repo.insert!()
  end

  describe "guarantee codes" do
    test "there are exactly the 10 canonical codes from §8" do
      assert length(Guarantee.codes()) == 10

      assert Guarantee.codes() == [
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
    end

    test "code is unique" do
      insert_guarantee(:vol)

      assert {:error, changeset} =
               %Guarantee{}
               |> Guarantee.changeset(%{code: :vol, name_fr: "G", name_ar: "غ"})
               |> Repo.insert()

      assert %{code: ["has already been taken"]} = errors_on(changeset)
    end
  end

  describe "enum rejection" do
    test "product rejects an out-of-range kind at the changeset boundary" do
      insurer = insert_insurer()

      changeset =
        Product.changeset(%Product{}, %{
          insurer_id: insurer.id,
          kind: :bateau,
          formula: :rc,
          name_fr: "x",
          name_ar: "س"
        })

      assert %{kind: ["is invalid"]} = errors_on(changeset)
    end

    test "guarantee rejects an unknown code at the changeset boundary" do
      changeset = Guarantee.changeset(%Guarantee{}, %{code: :nope, name_fr: "G", name_ar: "غ"})
      assert %{code: ["is invalid"]} = errors_on(changeset)
    end

    test "DB CHECK constraint backstops an invalid kind inserted via raw SQL" do
      insurer = insert_insurer()

      assert_raise Postgrex.Error, ~r/products_kind_must_be_valid/, fn ->
        Repo.query!(
          """
          INSERT INTO products (id, insurer_id, kind, formula, name_fr, name_ar,
            installments_available, active, inserted_at, updated_at)
          VALUES (gen_random_uuid(), $1, 'bateau', 'rc', 'x', 'س', false, false, now(), now())
          """,
          [Ecto.UUID.dump!(insurer.id)]
        )
      end
    end
  end

  describe "foreign-key integrity" do
    test "product with a non-existent insurer is rejected" do
      assert {:error, changeset} =
               %Product{}
               |> Product.changeset(%{
                 insurer_id: Ecto.UUID.generate(),
                 kind: :auto,
                 formula: :rc,
                 name_fr: "x",
                 name_ar: "س"
               })
               |> Repo.insert()

      assert %{insurer: ["does not exist"]} = errors_on(changeset)
    end

    test "product_guarantee with an unlinked guarantee_code is rejected" do
      product = insert_product(insert_insurer())

      assert {:error, changeset} =
               %ProductGuarantee{}
               |> ProductGuarantee.changeset(%{product_id: product.id, guarantee_code: :rc})
               |> Repo.insert()

      assert %{guarantee_code: ["does not exist"]} = errors_on(changeset)
    end
  end

  describe "centimes round-trip" do
    test "ceiling/franchise persist as integers and read back unchanged" do
      product = insert_product(insert_insurer())
      insert_guarantee(:rc)

      {:ok, pg} =
        %ProductGuarantee{}
        |> ProductGuarantee.changeset(%{
          product_id: product.id,
          guarantee_code: :rc,
          included: true,
          ceiling_centimes: 5_000_000,
          franchise_centimes: 250_000
        })
        |> Repo.insert()

      reloaded = Repo.get!(ProductGuarantee, pg.id)
      assert reloaded.ceiling_centimes == 5_000_000
      assert reloaded.franchise_centimes == 250_000
    end

    test "nil ceiling/franchise are allowed per the matrix" do
      product = insert_product(insert_insurer())
      insert_guarantee(:assistance)

      assert {:ok, pg} =
               %ProductGuarantee{}
               |> ProductGuarantee.changeset(%{
                 product_id: product.id,
                 guarantee_code: :assistance,
                 included: false
               })
               |> Repo.insert()

      assert pg.ceiling_centimes == nil
    end
  end

  describe "admin-only boolean guard" do
    test "Insurer.changeset/2 never casts :active" do
      changeset =
        Insurer.changeset(%Insurer{}, %{slug: "a", name_fr: "A", name_ar: "أ", active: true})

      assert get_change(changeset, :active) == nil
    end

    test "Insurer.admin_changeset/2 does cast :active and :position" do
      changeset =
        Insurer.admin_changeset(%Insurer{}, %{
          slug: "a",
          name_fr: "A",
          name_ar: "أ",
          active: true,
          position: 3
        })

      assert get_change(changeset, :active) == true
      assert get_change(changeset, :position) == 3
    end

    test "Product.changeset/2 never casts :active or :installments_available" do
      changeset =
        Product.changeset(%Product{}, %{
          insurer_id: Ecto.UUID.generate(),
          kind: :auto,
          formula: :rc,
          name_fr: "x",
          name_ar: "س",
          active: true,
          installments_available: true
        })

      assert get_change(changeset, :active) == nil
      assert get_change(changeset, :installments_available) == nil
    end
  end

  describe "context queries" do
    test "list_active_insurers/0 excludes inactive and orders by position then desc id" do
      insert_insurer(%{active: false, position: 0})
      a = insert_insurer(%{active: true, position: 2})
      b = insert_insurer(%{active: true, position: 1})

      assert Enum.map(Directory.list_active_insurers(), & &1.id) == [b.id, a.id]
    end

    test "get_insurer_by_slug/1 finds by slug" do
      insurer = insert_insurer(%{slug: "axa-maroc"})
      assert Directory.get_insurer_by_slug("axa-maroc").id == insurer.id
    end

    test "list_products_for_insurer/1 scopes to the insurer" do
      insurer = insert_insurer()
      other = insert_insurer()
      product = insert_product(insurer)
      _elsewhere = insert_product(other)

      assert Enum.map(Directory.list_products_for_insurer(insurer.id), & &1.id) == [product.id]
    end
  end
end
