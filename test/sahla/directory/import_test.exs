defmodule Sahla.Directory.ImportTest do
  use Sahla.DataCase, async: true
  use Oban.Testing, repo: Sahla.Repo

  alias Sahla.Directory.{Guarantee, Import, Insurer, Product, ProductGuarantee}
  alias Sahla.Directory.Workers.ProductMatrixImport

  @header "insurer_slug,kind,formula,product_name_fr,product_name_ar,guarantee_code,included,ceiling_centimes,franchise_centimes"

  setup do
    {:ok, _} =
      %Insurer{}
      |> Insurer.changeset(%{slug: "wafa", name_fr: "Wafa", name_ar: "وفا"})
      |> Repo.insert()

    for code <- [:rc, :vol] do
      {:ok, _} =
        %Guarantee{}
        |> Guarantee.changeset(%{code: code, name_fr: "G #{code}", name_ar: "غ"})
        |> Repo.insert()
    end

    :ok
  end

  defp csv(rows), do: Enum.join([@header | rows], "\n")

  describe "import_csv/1" do
    test "creates the product and its guarantee rows, parsing centimes and booleans" do
      csv =
        csv([
          "wafa,auto,tous_risques,Wafa TR,وفا,rc,true,1000000,50000",
          "wafa,auto,tous_risques,Wafa TR,وفا,vol,non,,"
        ])

      summary = Import.import_csv(csv)

      assert summary.products_created == 1
      assert summary.guarantees_inserted == 2
      assert summary.failed == 0

      product = Repo.get_by!(Product, formula: :tous_risques)
      guarantees = Repo.all(from pg in ProductGuarantee, where: pg.product_id == ^product.id)
      by_code = Map.new(guarantees, &{&1.guarantee_code, &1})

      assert by_code[:rc].included == true
      assert by_code[:rc].ceiling_centimes == 1_000_000
      assert by_code[:rc].franchise_centimes == 50_000
      # blank centimes -> nil, "non" -> false
      assert by_code[:vol].included == false
      assert by_code[:vol].ceiling_centimes == nil
      assert by_code[:vol].franchise_centimes == nil
    end

    test "re-importing the same file is idempotent (updates, no duplicates)" do
      csv = csv(["wafa,auto,tous_risques,Wafa TR,وفا,rc,true,1000000,50000"])

      _first = Import.import_csv(csv)
      second = Import.import_csv(csv)

      assert second.products_created == 0
      assert second.products_updated == 1
      assert second.guarantees_inserted == 0
      assert second.guarantees_updated == 1

      assert Repo.aggregate(Product, :count) == 1
      assert Repo.aggregate(ProductGuarantee, :count) == 1
    end

    test "an unknown insurer slug is a row-level error, not fatal" do
      csv =
        csv([
          "ghost,auto,tous_risques,X,X,rc,true,100,0",
          "wafa,auto,tous_risques,Wafa TR,وفا,rc,true,100,0"
        ])

      summary = Import.import_csv(csv)

      assert summary.failed == 1
      assert summary.guarantees_inserted == 1
      assert [%{row: 1, error: error}] = summary.errors
      assert error =~ "unknown insurer slug: ghost"
    end

    test "an unknown guarantee code is reported and skipped" do
      csv = csv(["wafa,auto,tous_risques,Wafa TR,وفا,bogus,true,100,0"])

      summary = Import.import_csv(csv)

      assert summary.failed == 1
      assert summary.guarantees_inserted == 0
      assert [%{row: 1, error: error}] = summary.errors
      assert error =~ "unknown guarantee_code: bogus"
    end

    test "an unparseable integer is reported and skipped" do
      csv = csv(["wafa,auto,tous_risques,Wafa TR,وفا,rc,true,abc,0"])

      summary = Import.import_csv(csv)

      assert summary.failed == 1
      assert [%{row: 1, error: error}] = summary.errors
      assert error =~ "invalid integer for ceiling_centimes"
    end

    test "kind defaults to auto when the column is blank" do
      csv =
        "insurer_slug,formula,guarantee_code,product_name_fr,product_name_ar,included\n" <>
          "wafa,tous_risques,rc,Wafa TR,وفا,true"

      summary = Import.import_csv(csv)

      assert summary.products_created == 1
      assert Repo.get_by!(Product, formula: :tous_risques).kind == :auto
    end
  end

  describe "ProductMatrixImport worker" do
    test "runs in the imports queue and returns the summary" do
      assert ProductMatrixImport.new(%{"csv" => ""}).changes.queue == "imports"

      csv = csv(["wafa,auto,tous_risques,Wafa TR,وفا,rc,true,100,0"])

      assert {:ok, summary} = perform_job(ProductMatrixImport, %{"csv" => csv})
      assert summary.guarantees_inserted == 1
      assert Repo.aggregate(ProductGuarantee, :count) == 1
    end
  end
end
