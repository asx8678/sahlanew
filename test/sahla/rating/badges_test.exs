defmodule Sahla.Rating.BadgesTest do
  use ExUnit.Case, async: true

  alias Sahla.Rating.{Badges, Offer}

  defp offer(slug, price, guarantees \\ [], formula \\ :tous_risques) do
    %Offer{
      insurer: %{slug: slug},
      product: %{formula: formula, guarantees: guarantees},
      formula: formula,
      annual_premium_centimes: price,
      breakdown: %{},
      estimated?: false
    }
  end

  defp kinds(offer), do: Enum.map(offer.badges, & &1.kind)
  defp find(offers, slug), do: Enum.find(offers, &(&1.insurer.slug == slug))

  describe "rank" do
    test "is 1..n ascending by price with a stable tiebreak" do
      offers = Badges.assign([offer("c", 3000), offer("a", 1000), offer("b", 2000)])

      assert Enum.map(offers, &{&1.insurer.slug, &1.rank}) == [{"a", 1}, {"b", 2}, {"c", 3}]
    end

    test "equal prices order deterministically by insurer slug" do
      a = Badges.assign([offer("zeta", 1000), offer("alpha", 1000)])
      b = Badges.assign([offer("alpha", 1000), offer("zeta", 1000)])

      assert Enum.map(a, & &1.insurer.slug) == ["alpha", "zeta"]
      assert Enum.map(a, & &1.rank) == Enum.map(b, & &1.rank)
    end
  end

  describe "cheapest" do
    test "lands on the single lowest total" do
      offers = Badges.assign([offer("a", 3000), offer("b", 1000), offer("c", 2000)])

      assert :cheapest in kinds(find(offers, "b"))
      assert Enum.count(offers, &(:cheapest in kinds(&1))) == 1
    end
  end

  describe "best_value" do
    test "selects max coverage_score/price with weights from opts" do
      # "b" is pricier but covers much more per dirham with these weights
      offers =
        Badges.assign(
          [
            offer("a", 1000, ["rc"]),
            offer("b", 1500, ["rc", "vol", "incendie"])
          ],
          coverage_weights: %{"rc" => 1, "vol" => 5, "incendie" => 5}
        )

      assert :best_value in kinds(find(offers, "b"))
      assert Enum.count(offers, &(:best_value in kinds(&1))) == 1
    end

    test "is not assigned without weights (nothing hard-coded)" do
      offers = Badges.assign([offer("a", 1000, ["rc"]), offer("b", 2000, ["rc", "vol"])])
      assert Enum.all?(offers, &(:best_value not in kinds(&1)))
    end
  end

  describe "expert_pick" do
    test "is applied only to offers matching a settings pin" do
      offers =
        Badges.assign(
          [offer("wafa", 1000), offer("axa", 2000)],
          expert_pins: [%{insurer_slug: "axa", formula: :tous_risques}]
        )

      assert :expert_pick in kinds(find(offers, "axa"))
      assert :expert_pick not in kinds(find(offers, "wafa"))
    end

    test "no pins means no expert_pick badge" do
      offers = Badges.assign([offer("wafa", 1000), offer("axa", 2000)])
      assert Enum.all?(offers, &(:expert_pick not in kinds(&1)))
    end
  end

  test "each badge carries an English dev-key justification" do
    offers =
      Badges.assign([offer("a", 1000, ["rc"])],
        coverage_weights: %{"rc" => 1},
        expert_pins: [%{insurer_slug: "a"}]
      )

    badges = hd(offers).badges
    assert Enum.map(badges, & &1.kind) |> Enum.sort() == [:best_value, :cheapest, :expert_pick]
    assert Enum.all?(badges, &is_binary(&1.justification))
    assert "Cheapest price" in Enum.map(badges, & &1.justification)
  end
end
