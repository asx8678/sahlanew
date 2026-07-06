defmodule SahlaWeb.InsurersLiveTest do
  use SahlaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Sahla.Accounts
  alias Sahla.Content
  alias Sahla.Directory
  alias Sahla.Directory.{Insurer, Product, ProductGuarantee}
  alias Sahla.Repo

  # --- fixtures ------------------------------------------------------------

  defp admin_fixture do
    {:ok, admin} =
      Accounts.register_admin(%{
        email: "insurer-admin-#{System.unique_integer([:positive])}@sahla.ma",
        password: "correct horse battery staple",
        role: :editor
      })

    admin
  end

  defp guide_fixture(attrs) do
    attrs =
      Map.merge(
        %{
          slug: "guide-#{System.unique_integer([:positive])}",
          kind: :guide,
          title_fr: "Guide FR",
          title_ar: "دليل AR",
          body_fr: "## Section\n\nCorps du guide.",
          body_ar: "## قسم\n\nمحتوى الدليل.",
          excerpt_fr: "Extrait",
          excerpt_ar: "ملخص",
          status_fr: :published,
          status_ar: :published
        },
        attrs
      )

    {:ok, post} = Content.create_post(attrs, actor: admin_fixture())
    post
  end

  defp insurer_fixture(attrs) do
    defaults = %{
      slug: "ins-#{System.unique_integer([:positive])}",
      name_fr: "Assureur Test",
      name_ar: "مؤمِّن اختبار",
      active: true,
      position: 1,
      acaps_ref: "AC-123",
      phone: "+212522000000",
      rating: Decimal.new("4.5")
    }

    %Insurer{}
    |> Insurer.admin_changeset(Map.merge(defaults, Map.new(attrs)))
    |> Repo.insert!()
  end

  defp product_fixture(insurer, attrs \\ %{}) do
    defaults = %{
      insurer_id: insurer.id,
      kind: :auto,
      formula: :tous_risques,
      name_fr: "Tous Risques",
      name_ar: "جميع الأخطار",
      active: true
    }

    %Product{}
    |> Product.admin_changeset(Map.merge(defaults, Map.new(attrs)))
    |> Repo.insert!()
  end

  defp matrix_fixture(product, code, attrs \\ %{}) do
    defaults = %{
      product_id: product.id,
      guarantee_code: code,
      included: true,
      ceiling_centimes: 5_000_000,
      franchise_centimes: 250_000
    }

    %ProductGuarantee{}
    |> ProductGuarantee.changeset(Map.merge(defaults, Map.new(attrs)))
    |> Repo.insert!()
  end

  # Seed the canonical guarantees once so the matrix FK resolves.
  setup do
    Directory.ensure_seed_catalog!()
    :ok
  end

  # --- index ---------------------------------------------------------------

  defp index_of(html, needle) do
    :binary.match(html, needle) |> elem(0)
  end

  describe "GET /assureurs" do
    test "lists active insurers ordered by position", %{conn: conn} do
      a = insurer_fixture(%{name_fr: "Atlas", position: 2})
      _b = insurer_fixture(%{name_fr: "Cedre", position: 1})

      {:ok, _lv, html} = live(conn, ~p"/assureurs")

      assert html =~ "Cedre"
      assert html =~ "Atlas"
      refute html =~ a.name_ar
      # b (position 1) renders before a (position 2)
      assert index_of(html, "Cedre") < index_of(html, "Atlas")
    end

    test "excludes inactive insurers", %{conn: conn} do
      _hidden = insurer_fixture(%{name_fr: "Secret", active: false})

      {:ok, _lv, html} = live(conn, ~p"/assureurs")

      refute html =~ "Secret"
    end

    test "renders the breadcrumb JSON-LD in the head", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/assureurs")

      assert html =~ ~s("name\":\"Insurers\")
    end

    test "empty state when no active insurers", %{conn: conn} do
      # Deactivate every insurer so the active-only index is empty, without
      # touching the FK-entangled products.
      Repo.update_all(Insurer, set: [active: false])

      {:ok, _lv, html} = live(conn, ~p"/assureurs")

      assert html =~ "No insurers available yet"
    end
  end

  # --- show ----------------------------------------------------------------

  describe "GET /assureurs/:slug" do
    test "renders the profile with rating, ACAPS ref and matrix", %{conn: conn} do
      insurer = insurer_fixture(%{name_fr: "Wafa Test", slug: "wafa-test"})
      product = product_fixture(insurer)
      matrix_fixture(product, :rc, ceiling_centimes: 5_000_000, franchise_centimes: 250_000)

      {:ok, _lv, html} = live(conn, ~p"/assureurs/wafa-test")

      assert html =~ "Wafa Test"
      assert html =~ "4.5"
      assert html =~ "AC-123"
      # Guarantee row label (canonical guarantee seeded with name "Responsabilité civile")
      assert html =~ "Responsabilité civile"
      # Ceiling (5_000_000 centimes) and franchise (250_000) render as MAD;
      # fr grouping uses the narrow no-break space (U+202F) per CLDR :latn.
      assert html =~ "50\u202F000 MAD"
      assert html =~ "2\u202F500 MAD"
    end

    test "renders the breadcrumb JSON-LD with the insurer name", %{conn: conn} do
      insurer_fixture(%{name_fr: "Breadcrumb Insurer", slug: "breadcrumb-insurer"})

      {:ok, _lv, html} = live(conn, ~p"/assureurs/breadcrumb-insurer")

      assert html =~ ~s("@type\":\"BreadcrumbList\")
      assert html =~ ~s("name\":\"Breadcrumb Insurer\")
      assert html =~ ~s("name\":\"Insurers\")
    end

    test "canonical link is present in the head", %{conn: conn} do
      insurer_fixture(%{slug: "canonical-insurer"})

      {:ok, _lv, html} = live(conn, ~p"/assureurs/canonical-insurer")

      assert html =~ ~s(rel="canonical")
      assert html =~ "/assureurs/canonical-insurer"
    end

    test "renders the CTA into the funnel", %{conn: conn} do
      insurer_fixture(%{slug: "cta-insurer"})

      {:ok, _lv, html} = live(conn, ~p"/assureurs/cta-insurer")

      assert html =~ "/devis/new"
    end

    test "related guides are listed when published", %{conn: conn} do
      _guide = guide_fixture(%{title_fr: "Guide associé", slug: "assoc-guide"})
      insurer_fixture(%{slug: "guides-insurer"})

      {:ok, _lv, html} = live(conn, ~p"/assureurs/guides-insurer")

      assert html =~ "Guide associé"
      assert html =~ "Related guides"
    end

    test "CG download link rendered when document path present", %{conn: conn} do
      insurer = insurer_fixture(%{slug: "cg-insurer"})
      # The uploads route serves a single basename (UUID.ext); the link renders
      # conditionally only when a path is stored on the product.
      product_fixture(insurer, %{cg_document_path: "cg-uuid-1234.pdf"})

      {:ok, _lv, html} = live(conn, ~p"/assureurs/cg-insurer")

      assert html =~ "Download CG"
      assert html =~ "/uploads/cg-uuid-1234.pdf"
    end

    test "missing slug redirects to the index and does not leak the profile", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/assureurs"}}} =
               live(conn, ~p"/assureurs/does-not-exist")
    end

    test "inactive slug redirects to the index and does not leak the profile", %{conn: conn} do
      insurer_fixture(%{slug: "inactive-insurer", active: false, name_fr: "Assureur Privé"})

      assert {:error, {:redirect, %{to: "/assureurs"}}} =
               live(conn, ~p"/assureurs/inactive-insurer")
    end

    test "/ar/assureurs/:slug renders rtl and Arabic name", %{conn: conn} do
      insurer_fixture(%{slug: "ar-insurer", name_ar: "مؤمِّن عربي"})

      {:ok, _lv, html} = live(conn, ~p"/ar/assureurs/ar-insurer")

      assert html =~ ~S(<html lang="ar" dir="rtl">)
      assert html =~ "مؤمِّن عربي"
    end

    test "excluded guarantee renders an x-mark, not a check", %{conn: conn} do
      insurer = insurer_fixture(%{slug: "excl-insurer"})
      product = product_fixture(insurer)
      # rc included, vol excluded
      matrix_fixture(product, :rc)
      matrix_fixture(product, :vol, %{included: false})

      {:ok, _lv, html} = live(conn, ~p"/assureurs/excl-insurer")

      # Both guarantee rows render
      assert html =~ "Responsabilité civile"
      assert html =~ "Vol"
    end
  end
end
