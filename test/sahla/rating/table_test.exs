defmodule Sahla.Rating.TableTest do
  use Sahla.DataCase, async: true

  alias Sahla.Rating.Table

  defp valid_rc_base do
    %{
      "bands" => [
        %{"cv_min" => 1, "cv_max" => 6, "fuel" => "essence", "annual_centimes" => 198_000}
      ]
    }
  end

  defp valid_taxes_fees do
    %{
      "tax_rate" => 0.14,
      "fixed_fees_centimes" => 5000,
      "evcat" => %{"rate" => 0.05, "min_centimes" => 3000}
    }
  end

  defp insert(attrs) do
    %Table{}
    |> Table.changeset(Map.merge(%{code: :rc_base, version: 1, data: valid_rc_base()}, attrs))
    |> Repo.insert!()
  end

  describe "per-code data validation" do
    test "accepts a well-formed rc_base table" do
      changeset = Table.changeset(%Table{}, %{code: :rc_base, version: 1, data: valid_rc_base()})
      assert changeset.valid?
    end

    test "rejects an rc_base band missing annual_centimes with a field error" do
      band = %{"cv_min" => 1, "cv_max" => 6, "fuel" => "essence"}

      changeset =
        Table.changeset(%Table{}, %{code: :rc_base, version: 1, data: %{"bands" => [band]}})

      refute changeset.valid?
      assert %{data: [msg]} = errors_on(changeset)
      assert msg =~ "annual_centimes"
    end

    test "taxes_fees requires the always-on EVCAT rule (Law 110-14)" do
      no_evcat = %{"tax_rate" => 0.14, "fixed_fees_centimes" => 5000}
      changeset = Table.changeset(%Table{}, %{code: :taxes_fees, version: 1, data: no_evcat})

      assert %{data: [msg]} = errors_on(changeset)
      assert msg =~ "evcat"
    end

    test "accepts a complete taxes_fees table" do
      changeset =
        Table.changeset(%Table{}, %{code: :taxes_fees, version: 1, data: valid_taxes_fees()})

      assert changeset.valid?
    end

    test "insurer_positioning rejects an unknown key" do
      data = %{"wafa" => %{"rc" => 1.06, "spaceship" => 0.9}}

      changeset =
        Table.changeset(%Table{}, %{code: :insurer_positioning, version: 1, data: data})

      assert %{data: [msg]} = errors_on(changeset)
      assert msg =~ "unknown keys"
    end

    test "insurer_positioning accepts a fonctionnaire discount in (0, 1]" do
      data = %{"wafa" => %{"rc" => 1.05, "tous_risques" => 0.98, "fonctionnaire" => 0.9}}

      changeset =
        Table.changeset(%Table{}, %{code: :insurer_positioning, version: 1, data: data})

      assert changeset.valid?
    end

    test "insurer_positioning rejects a fonctionnaire factor above 1 (would raise the premium)" do
      data = %{"wafa" => %{"rc" => 1.05, "fonctionnaire" => 1.2}}

      changeset =
        Table.changeset(%Table{}, %{code: :insurer_positioning, version: 1, data: data})

      assert %{data: [msg]} = errors_on(changeset)
      assert msg =~ "fonctionnaire"
    end

    test "insurer_positioning rejects a non-positive fonctionnaire factor" do
      data = %{"wafa" => %{"rc" => 1.05, "fonctionnaire" => 0}}

      changeset =
        Table.changeset(%Table{}, %{code: :insurer_positioning, version: 1, data: data})

      assert %{data: [msg]} = errors_on(changeset)
      assert msg =~ "fonctionnaire"
    end

    test "city_factor requires all three risk zones" do
      data = %{"factors" => %{"1" => 0.9, "2" => 1.0}}
      changeset = Table.changeset(%Table{}, %{code: :city_factor, version: 1, data: data})

      assert %{data: [msg]} = errors_on(changeset)
      assert msg =~ "risk zones"
    end
  end

  describe "checksum" do
    test "is deterministic regardless of map key insertion order" do
      a = %{
        "bands" => [
          %{"cv_min" => 1, "cv_max" => 6, "fuel" => "essence", "annual_centimes" => 198_000}
        ]
      }

      b = %{
        "bands" => [
          %{"annual_centimes" => 198_000, "fuel" => "essence", "cv_max" => 6, "cv_min" => 1}
        ]
      }

      assert Table.checksum(a) == Table.checksum(b)
    end

    test "changes when the data changes" do
      one = Table.checksum(valid_rc_base())

      two =
        Table.checksum(%{
          "bands" => [
            %{"cv_min" => 1, "cv_max" => 6, "fuel" => "essence", "annual_centimes" => 199_000}
          ]
        })

      refute one == two
    end

    test "changeset stores the recomputed checksum" do
      changeset = Table.changeset(%Table{}, %{code: :rc_base, version: 1, data: valid_rc_base()})
      assert get_change(changeset, :checksum) == Table.checksum(valid_rc_base())
    end
  end

  describe "immutability of published/archived rows" do
    test "editing a published row's data is rejected" do
      published = insert(%{})
      {:ok, published} = published |> Ecto.Changeset.change(status: :published) |> Repo.update()

      changeset =
        Table.changeset(published, %{
          data: %{
            "bands" => [
              %{"cv_min" => 1, "cv_max" => 6, "fuel" => "diesel", "annual_centimes" => 210_000}
            ]
          }
        })

      refute changeset.valid?
      assert %{base: [msg]} = errors_on(changeset)
      assert msg =~ "immutable"
    end

    test "a draft row can still be edited" do
      draft = insert(%{})
      changeset = Table.changeset(draft, %{notes: "tweaked"})
      assert changeset.valid?
    end
  end

  describe "admin-only fields" do
    test "changeset/2 does not cast status or published_by_id" do
      admin_id = Ecto.UUID.generate()

      changeset =
        Table.changeset(%Table{}, %{
          code: :rc_base,
          version: 1,
          data: valid_rc_base(),
          status: :published,
          published_by_id: admin_id
        })

      assert get_change(changeset, :status) == nil
      assert get_change(changeset, :published_by_id) == nil
    end

    test "publish_changeset/2 does cast status and published_by_id" do
      admin_id = Ecto.UUID.generate()

      changeset =
        Table.publish_changeset(%Table{}, %{
          code: :rc_base,
          version: 1,
          data: valid_rc_base(),
          status: :published,
          published_by_id: admin_id
        })

      assert get_change(changeset, :status) == :published
      assert get_change(changeset, :published_by_id) == admin_id
    end
  end

  describe "persistence & constraints" do
    test "(code, version) is unique" do
      insert(%{code: :rc_base, version: 7})

      assert {:error, changeset} =
               %Table{}
               |> Table.changeset(%{code: :rc_base, version: 7, data: valid_rc_base()})
               |> Repo.insert()

      assert %{code: ["has already been taken"]} = errors_on(changeset)
    end

    test "a valid table round-trips through Postgres with its checksum" do
      table = insert(%{code: :taxes_fees, version: 1, data: valid_taxes_fees()})
      reloaded = Repo.get!(Table, table.id)

      assert reloaded.checksum == Table.checksum(valid_taxes_fees())
      assert reloaded.status == :draft
      assert reloaded.data["evcat"]["rate"] == 0.05
    end
  end
end
