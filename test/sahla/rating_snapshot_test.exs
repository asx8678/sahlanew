defmodule Sahla.RatingSnapshotTest do
  use Sahla.DataCase, async: true

  alias Sahla.Quoting.{Offer, Quote}
  alias Sahla.Rating
  alias Sahla.Rating.Run

  defp quote_fixture do
    %Quote{} |> Quote.create_changeset(%{}) |> Repo.insert!()
  end

  defp offer_struct(overrides \\ %{}) do
    Map.merge(
      %Sahla.Rating.Offer{
        insurer: %{id: nil},
        product: %{id: nil},
        formula: :tous_risques,
        annual_premium_centimes: 480_000,
        monthly_equiv_centimes: 40_000,
        breakdown: %{rc: 400_000, evcat: 20_000, taxes: 55_000, fees: 5000, total: 480_000},
        estimated?: false,
        rank: 1,
        badges: [%{kind: :cheapest, justification: "Cheapest price"}]
      },
      overrides
    )
  end

  defp meta do
    %{
      engine_version: "v1",
      table_versions: %{"rc_base" => 3, "taxes_fees" => 1},
      inputs: %{
        fiscal_power: 6,
        crm: Decimal.new("1.00"),
        today: ~D[2026-01-01],
        phone: "0612345678",
        first_name: "Ali",
        email: "a@b.ma"
      },
      duration_us: 1234
    }
  end

  test "snapshot/3 inserts one run and N offers atomically and links the quote" do
    quote = quote_fixture()

    offers = [
      offer_struct(%{rank: 1}),
      offer_struct(%{rank: 2, annual_premium_centimes: 500_000})
    ]

    assert {:ok, %Run{} = run} = Rating.snapshot(quote, offers, meta())

    assert run.quote_id == quote.id
    assert run.engine_version == "v1"
    assert run.table_versions == %{"rc_base" => 3, "taxes_fees" => 1}
    assert run.duration_us == 1234

    persisted = Repo.all(Offer)
    assert length(persisted) == 2
    assert Repo.reload!(quote).rating_run_id == run.id
  end

  test "inputs store only a non-PII projection" do
    quote = quote_fixture()
    {:ok, run} = Rating.snapshot(quote, [offer_struct()], meta())

    keys = Map.keys(run.inputs)
    refute "phone" in keys
    refute "first_name" in keys
    refute "email" in keys
    assert "fiscal_power" in keys
    # Decimal/Date are stringified for jsonb
    assert run.inputs["crm"] == "1.00"
    assert run.inputs["today"] == "2026-01-01"
  end

  test "offers persist breakdown, badges, rank and monthly_equiv == round(annual/12)" do
    quote = quote_fixture()

    {:ok, _run} =
      Rating.snapshot(
        quote,
        [offer_struct(%{monthly_equiv_centimes: nil, annual_premium_centimes: 480_000})],
        meta()
      )

    offer = Repo.one(Offer)
    assert offer.badges == ["cheapest"]
    assert offer.rank == 1
    assert offer.breakdown["total"] == 480_000
    assert offer.monthly_equiv_centimes == round(480_000 / 12)
  end

  test "a partial failure rolls everything back" do
    quote = quote_fixture()
    good = offer_struct(%{rank: 1})
    # invalid: negative premium violates the changeset
    bad = offer_struct(%{rank: 2, annual_premium_centimes: -1})

    assert {:error, _changeset} = Rating.snapshot(quote, [good, bad], meta())

    assert Repo.all(Offer) == []
    assert Repo.all(Run) == []
    assert Repo.reload!(quote).rating_run_id == nil
  end
end
