defmodule Sahla.Rating.Seeds do
  @moduledoc """
  Idempotent placeholder seeding of the seven rating tables and the minimal
  directory catalog (insurers, guarantees, products) the engine needs to
  produce a full 8 × 3 offer matrix in a fresh environment.

  All numbers are provisional and calibrated so that:

    * an old-car RC-only persona lands roughly 1 600–2 500 MAD/year;
    * a median Dacia-Sandera-style persona with Tous Risques lands
      roughly 3 500–5 500 MAD/year.

  Re-running the seed is safe: existing published table versions and existing
  insurer/product names are never overwritten.
  """

  import Ecto.Query

  alias Sahla.Directory
  alias Sahla.Rating.{Table, TableCache, Tables}
  alias Sahla.Repo

  @notes "placeholder — replace with broker barème"

  @doc """
  Seeds the directory catalog (if missing) and the seven placeholder rate
  tables, then refreshes the table cache.
  """
  def seed_placeholders do
    Directory.ensure_seed_catalog!()
    ensure_tables!()
    TableCache.refresh()
    :ok
  end

  # -- rate tables ------------------------------------------------------------

  defp ensure_tables! do
    today = Date.utc_today()

    for code <- Table.codes() do
      unless published_version_1?(code) do
        code
        |> find_or_build_draft_v1()
        |> Table.changeset(%{data: table_data(code), notes: @notes})
        |> Repo.insert_or_update!()
        |> Tables.publish(today)
      end
    end
  end

  defp published_version_1?(code) do
    Table
    |> where([t], t.code == ^code and t.status == :published and t.version == 1)
    |> Repo.exists?()
  end

  defp find_or_build_draft_v1(code) do
    case Table
         |> where([t], t.code == ^code and t.version == 1 and t.status == :draft)
         |> Repo.one() do
      nil -> %Table{code: code, version: 1}
      table -> table
    end
  end

  defp table_data(:rc_base) do
    %{
      "bands" => [
        %{"cv_min" => 1, "cv_max" => 4, "fuel" => "essence", "annual_centimes" => 240_000},
        %{"cv_min" => 1, "cv_max" => 4, "fuel" => "diesel", "annual_centimes" => 260_000},
        %{"cv_min" => 1, "cv_max" => 4, "fuel" => "*", "annual_centimes" => 240_000},
        %{"cv_min" => 5, "cv_max" => 7, "fuel" => "essence", "annual_centimes" => 290_000},
        %{"cv_min" => 5, "cv_max" => 7, "fuel" => "diesel", "annual_centimes" => 310_000},
        %{"cv_min" => 5, "cv_max" => 7, "fuel" => "*", "annual_centimes" => 290_000},
        %{"cv_min" => 8, "cv_max" => 11, "fuel" => "essence", "annual_centimes" => 350_000},
        %{"cv_min" => 8, "cv_max" => 11, "fuel" => "diesel", "annual_centimes" => 370_000},
        %{"cv_min" => 8, "cv_max" => 11, "fuel" => "*", "annual_centimes" => 350_000},
        %{"cv_min" => 12, "cv_max" => 16, "fuel" => "essence", "annual_centimes" => 410_000},
        %{"cv_min" => 12, "cv_max" => 16, "fuel" => "diesel", "annual_centimes" => 430_000},
        %{"cv_min" => 12, "cv_max" => 16, "fuel" => "*", "annual_centimes" => 410_000},
        %{"cv_min" => 17, "cv_max" => 99, "fuel" => "essence", "annual_centimes" => 480_000},
        %{"cv_min" => 17, "cv_max" => 99, "fuel" => "diesel", "annual_centimes" => 500_000},
        %{"cv_min" => 17, "cv_max" => 99, "fuel" => "*", "annual_centimes" => 480_000}
      ]
    }
  end

  defp table_data(:usage_factor) do
    %{
      "factors" => %{
        "personnel" => 1.0,
        "professionnel" => 1.2,
        "taxi" => 1.5,
        "location" => 1.4,
        "utilitaire" => 1.1
      }
    }
  end

  defp table_data(:city_factor) do
    %{
      "factors" => %{
        "1" => 0.9,
        "2" => 1.0,
        "3" => 1.15
      }
    }
  end

  defp table_data(:crm) do
    %{
      "start" => 1.0,
      "floor" => 0.5,
      "ceiling" => 2.5,
      "clean_year_factor" => 0.9,
      "claim_factor" => 1.2
    }
  end

  defp table_data(:option_pricing) do
    %{
      "options" => %{
        "vol" => %{"annual_centimes" => 70_000},
        "incendie" => %{"annual_centimes" => 55_000},
        "bris_glace" => %{"annual_centimes" => 40_000},
        "pta" => %{"annual_centimes" => 25_000},
        "defense_recours" => %{"annual_centimes" => 15_000},
        "assistance" => %{"annual_centimes" => 30_000},
        "individuelle" => %{"annual_centimes" => 20_000},
        "evenements_climatiques" => %{"annual_centimes" => 35_000}
      }
    }
  end

  defp table_data(:insurer_positioning) do
    %{
      "wafa" => %{
        "rc" => 1.00,
        "tiers_etendu" => 0.95,
        "tous_risques" => 0.90,
        "fonctionnaire" => 0.90
      },
      "rma" => %{
        "rc" => 1.05,
        "tiers_etendu" => 1.00,
        "tous_risques" => 0.95
      },
      "sanlam" => %{
        "rc" => 1.00,
        "tiers_etendu" => 1.00,
        "tous_risques" => 1.00
      },
      "axa" => %{
        "rc" => 1.10,
        "tiers_etendu" => 1.05,
        "tous_risques" => 1.05
      },
      "atlantasanad" => %{
        "rc" => 1.05,
        "tiers_etendu" => 1.00,
        "tous_risques" => 1.00
      },
      "allianz" => %{
        "rc" => 1.05,
        "tiers_etendu" => 1.05,
        "tous_risques" => 1.10
      },
      "mamda" => %{
        "rc" => 1.00,
        "tiers_etendu" => 0.95,
        "tous_risques" => 0.95
      },
      "cat" => %{
        "rc" => 1.10,
        "tiers_etendu" => 1.10,
        "tous_risques" => 1.15
      }
    }
  end

  defp table_data(:taxes_fees) do
    %{
      "tax_rate" => 0.14,
      "fixed_fees_centimes" => 5_000,
      "evcat" => %{
        "rate" => 0.05,
        "min_centimes" => 8_000
      }
    }
  end

  # -- catalog helpers -------------------------------------------------------

  @doc false
  def build_catalog do
    for insurer <- Directory.list_active_insurers(),
        product <- Directory.list_products_for_insurer(insurer.id) do
      %{
        insurer: %{slug: insurer.slug, name_fr: insurer.name_fr},
        product: %{formula: product.formula}
      }
    end
  end
end
