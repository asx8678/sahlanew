# Catalog seed data (§3.1, §8, §14). Idempotent and re-runnable: every insert
# goes through an upsert (context `upsert_*` or the idempotent CSV importers), so
# `mix run priv/repo/seeds/seeds.exs` twice leaves the same dataset.
#
#     mix run priv/repo/seeds/seeds.exs
#
# PROVISIONAL DATA: `acaps_ref`, insurer `rating`/positioning, product-guarantee
# ceilings/franchises and city `risk_zone` are placeholders pending Phase-0
# broker calibration — clearly marked, never invented firm prices.

alias Sahla.{Cities, Directory}
alias Sahla.Directory.Import, as: DirectoryImport
alias Sahla.Vehicles.Import, as: VehicleImport

# --- Runtime settings (feature flags, display name, disclaimers) --------------
Sahla.Settings.seed_defaults()

# --- Insurers (§8) — the 8 real Moroccan auto insurers ------------------------
insurers = [
  %{slug: "wafa", name_fr: "Wafa Assurance", name_ar: "وفا للتأمين", rating: "4.3", position: 1},
  %{slug: "rma", name_fr: "RMA Watanya", name_ar: "الوطنية للتأمين", rating: "4.1", position: 2},
  %{slug: "sanlam", name_fr: "Sanlam Maroc", name_ar: "سنلام المغرب", rating: "4.0", position: 3},
  %{slug: "axa", name_fr: "AXA Assurance Maroc", name_ar: "أكسا للتأمين المغرب", rating: "4.2", position: 4},
  %{slug: "atlantasanad", name_fr: "AtlantaSanad", name_ar: "أطلنطا سند", rating: "3.9", position: 5},
  %{slug: "allianz", name_fr: "Allianz Maroc", name_ar: "أليانز المغرب", rating: "4.0", position: 6},
  %{slug: "mamda", name_fr: "MAMDA-MCMA", name_ar: "مامدا-مكما", rating: "3.8", position: 7},
  %{slug: "cat", name_fr: "CAT Assurances", name_ar: "الشركة المغربية لتأمين النقل", rating: "3.7", position: 8}
]

for attrs <- insurers do
  {:ok, _} =
    attrs
    |> Map.merge(%{
      active: true,
      rating: Decimal.new(attrs.rating),
      acaps_ref: "ACAPS-TBD-#{String.upcase(attrs.slug)}",
      logo_path: "/images/insurers/#{attrs.slug}.svg"
    })
    |> Directory.upsert_insurer()
end

# --- Guarantees (§8) — the fixed 10-code list ---------------------------------
guarantees = [
  %{code: :rc, name_fr: "Responsabilité civile", name_ar: "المسؤولية المدنية"},
  %{code: :vol, name_fr: "Vol", name_ar: "السرقة"},
  %{code: :incendie, name_fr: "Incendie", name_ar: "الحريق"},
  %{code: :bris_glace, name_fr: "Bris de glace", name_ar: "تكسر الزجاج"},
  %{code: :pta, name_fr: "Personnes transportées", name_ar: "الأشخاص المنقولون"},
  %{code: :defense_recours, name_fr: "Défense et recours", name_ar: "الدفاع والمطالبة"},
  %{code: :assistance, name_fr: "Assistance", name_ar: "المساعدة"},
  %{code: :individuelle, name_fr: "Individuelle accident", name_ar: "الحوادث الفردية"},
  %{code: :evenements_climatiques, name_fr: "Événements climatiques", name_ar: "الظواهر المناخية"},
  %{code: :evcat, name_fr: "Événements catastrophiques", name_ar: "الأحداث الكارثية"}
]

for attrs <- guarantees, do: {:ok, _} = Directory.upsert_guarantee(attrs)

# --- Products + product-guarantee matrix (§8) ---------------------------------
# Which guarantees each formula bundles, and PROVISIONAL {ceiling, franchise}
# centimes placeholders (nil ceiling = no explicit cap).
coverage = %{
  rc: {nil, 0},
  vol: {50_000_000, 250_000},
  incendie: {50_000_000, 250_000},
  bris_glace: {500_000, 50_000},
  pta: {10_000_000, 0},
  defense_recours: {500_000, 0},
  assistance: {nil, 0},
  individuelle: {10_000_000, 0},
  evenements_climatiques: {30_000_000, 500_000},
  evcat: {30_000_000, 500_000}
}

formula_bundle = %{
  "rc" => [:rc, :defense_recours, :assistance],
  "tiers_etendu" => [:rc, :vol, :incendie, :bris_glace, :defense_recours, :assistance, :evcat],
  "tous_risques" => Enum.map(guarantees, & &1.code)
}

formula_label = %{
  "rc" => {"RC", "المسؤولية المدنية"},
  "tiers_etendu" => {"Tiers Étendu", "الغير الموسع"},
  "tous_risques" => {"Tous Risques", "جميع الأخطار"}
}

matrix_rows =
  for insurer <- insurers,
      {formula, codes} <- formula_bundle,
      code <- codes do
    {ceiling, franchise} = Map.fetch!(coverage, code)
    {label_fr, label_ar} = Map.fetch!(formula_label, formula)

    %{
      "insurer_slug" => insurer.slug,
      "kind" => "auto",
      "formula" => formula,
      "product_name_fr" => "#{insurer.name_fr} #{label_fr}",
      "product_name_ar" => "#{insurer.name_ar} #{label_ar}",
      "guarantee_code" => Atom.to_string(code),
      "included" => "true",
      "ceiling_centimes" => if(ceiling, do: Integer.to_string(ceiling), else: ""),
      "franchise_centimes" => Integer.to_string(franchise)
    }
  end

matrix_summary = DirectoryImport.import_rows(matrix_rows)

if matrix_summary.failed > 0 do
  raise "product matrix seed failed: #{inspect(matrix_summary.errors)}"
end

# --- Vehicle catalog (~200 popular versions) ----------------------------------
vehicle_summary =
  __DIR__
  |> Path.join("vehicles.csv")
  |> File.read!()
  |> VehicleImport.import_csv()

if vehicle_summary.failed > 0 do
  raise "vehicle seed failed: #{inspect(vehicle_summary.errors)}"
end

# --- Cities with provisional risk zones (§3.1) --------------------------------
cities = [
  %{name_fr: "Casablanca", name_ar: "الدار البيضاء", region: "Casablanca-Settat", risk_zone: 3},
  %{name_fr: "Mohammedia", name_ar: "المحمدية", region: "Casablanca-Settat", risk_zone: 3},
  %{name_fr: "Tanger", name_ar: "طنجة", region: "Tanger-Tétouan-Al Hoceïma", risk_zone: 3},
  %{name_fr: "Rabat", name_ar: "الرباط", region: "Rabat-Salé-Kénitra", risk_zone: 2},
  %{name_fr: "Salé", name_ar: "سلا", region: "Rabat-Salé-Kénitra", risk_zone: 2},
  %{name_fr: "Kénitra", name_ar: "القنيطرة", region: "Rabat-Salé-Kénitra", risk_zone: 2},
  %{name_fr: "Marrakech", name_ar: "مراكش", region: "Marrakech-Safi", risk_zone: 2},
  %{name_fr: "Fès", name_ar: "فاس", region: "Fès-Meknès", risk_zone: 2},
  %{name_fr: "Meknès", name_ar: "مكناس", region: "Fès-Meknès", risk_zone: 2},
  %{name_fr: "Agadir", name_ar: "أكادير", region: "Souss-Massa", risk_zone: 2},
  %{name_fr: "Tétouan", name_ar: "تطوان", region: "Tanger-Tétouan-Al Hoceïma", risk_zone: 2},
  %{name_fr: "El Jadida", name_ar: "الجديدة", region: "Casablanca-Settat", risk_zone: 2},
  %{name_fr: "Témara", name_ar: "تمارة", region: "Rabat-Salé-Kénitra", risk_zone: 2},
  %{name_fr: "Oujda", name_ar: "وجدة", region: "Oriental", risk_zone: 1},
  %{name_fr: "Nador", name_ar: "الناظور", region: "Oriental", risk_zone: 1},
  %{name_fr: "Safi", name_ar: "آسفي", region: "Marrakech-Safi", risk_zone: 1},
  %{name_fr: "Béni Mellal", name_ar: "بني ملال", region: "Béni Mellal-Khénifra", risk_zone: 1},
  %{name_fr: "Khouribga", name_ar: "خريبكة", region: "Béni Mellal-Khénifra", risk_zone: 1},
  %{name_fr: "Settat", name_ar: "سطات", region: "Casablanca-Settat", risk_zone: 1},
  %{name_fr: "Laâyoune", name_ar: "العيون", region: "Laâyoune-Sakia El Hamra", risk_zone: 1}
]

for attrs <- cities, do: {:ok, _} = Cities.upsert_city(attrs)

IO.puts("""
Seed complete:
  insurers:  #{length(insurers)}
  guarantees:#{length(guarantees)}
  products:  created #{matrix_summary.products_created}, guarantees #{matrix_summary.guarantees_inserted} inserted / #{matrix_summary.guarantees_updated} updated
  vehicles:  #{vehicle_summary.versions_inserted} inserted / #{vehicle_summary.versions_updated} updated across #{vehicle_summary.makes_created} makes
  cities:    #{length(cities)}
""")
