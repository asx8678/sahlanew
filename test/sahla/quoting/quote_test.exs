defmodule Sahla.Quoting.QuoteTest do
  use Sahla.DataCase, async: true

  alias Sahla.Quoting.Quote

  defp insert(attrs) do
    %Quote{}
    |> Quote.create_changeset(attrs)
    |> Repo.insert!()
  end

  describe "draft creation" do
    test "a draft with only a generated token and default locale inserts" do
      quote = insert(%{})

      assert quote.token
      assert quote.status == :draft
      assert quote.locale == "fr"
      assert quote.current_step == 1
      assert quote.options == []
    end

    test "tokens are unique" do
      quote = insert(%{})

      assert {:error, changeset} =
               %Quote{}
               |> Quote.changeset(%{})
               |> Ecto.Changeset.put_change(:token, quote.token)
               |> Ecto.Changeset.unique_constraint(:token)
               |> Repo.insert()

      assert %{token: ["has already been taken"]} = errors_on(changeset)
    end
  end

  describe "enum + CHECK enforcement" do
    test "invalid enum values are rejected at the changeset boundary" do
      changeset = Quote.changeset(%Quote{}, %{usage: :taxi, parking: :moon, formula: :bogus})
      errors = errors_on(changeset)
      assert errors.usage == ["is invalid"]
      assert errors.parking == ["is invalid"]
      assert errors.formula == ["is invalid"]
    end

    test "valid enum values persist" do
      quote =
        insert(%{
          usage: :personnel,
          parking: :garage,
          formula: :tous_risques,
          franchise_pref: :standard
        })

      assert quote.usage == :personnel
      assert quote.parking == :garage
      assert quote.formula == :tous_risques
    end
  end

  describe "PII: encrypted phone + keyed HMAC hash" do
    test "phone round-trips through encryption and the hash is deterministic" do
      quote = insert(%{phone: "0612345678"})
      reloaded = Repo.get!(Quote, quote.id)

      assert reloaded.phone_enc == "0612345678"

      # deterministic keyed HMAC (same input -> same hash)
      other = insert(%{phone: "0612345678"})
      assert Repo.get!(Quote, other.id).phone_hash == reloaded.phone_hash
      # a different number hashes differently
      diff = insert(%{phone: "0655555555"})
      refute Repo.get!(Quote, diff.id).phone_hash == reloaded.phone_hash
    end

    test "the stored phone bytes are ciphertext, not plaintext" do
      quote = insert(%{phone: "0612345678"})

      %{rows: [[enc]]} =
        Repo.query!("SELECT phone_enc FROM quotes WHERE id = $1", [Ecto.UUID.dump!(quote.id)])

      refute enc == "0612345678"
      refute String.contains?(enc, "0612345678")
    end

    test "changing the phone to a different number clears phone_verified_at (bypass fix)" do
      verified = insert(%{phone: "0612345678"}) |> Repo.reload!()
      verified = Repo.update!(Quote.mark_phone_verified(verified, ~U[2026-07-04 10:00:00Z]))
      assert verified.phone_verified_at

      # editing to a NEW number resets verification
      changeset = Quote.changeset(verified, %{phone: "0655555555"})
      assert changeset.changes.phone_verified_at == nil
    end

    test "re-submitting the same phone keeps phone_verified_at intact" do
      verified = insert(%{phone: "0612345678"}) |> Repo.reload!()
      verified = Repo.update!(Quote.mark_phone_verified(verified, ~U[2026-07-04 10:00:00Z]))

      changeset = Quote.changeset(verified, %{phone: "0612345678"})
      refute Map.has_key?(changeset.changes, :phone_verified_at)
    end
  end

  describe "money, crm and options" do
    test "crm within 0.50-2.50 persists as numeric(3,2)" do
      quote = insert(%{crm: Decimal.new("0.85")})
      assert Decimal.equal?(Repo.get!(Quote, quote.id).crm, Decimal.new("0.85"))
    end

    test "crm outside the range is rejected" do
      changeset = Quote.changeset(%Quote{}, %{crm: Decimal.new("3.00")})
      assert %{crm: [_]} = errors_on(changeset)
    end

    test "options persist as a text array" do
      quote = insert(%{options: ["vol", "bris_glace"]})
      assert Repo.get!(Quote, quote.id).options == ["vol", "bris_glace"]
    end

    test "vehicle_value_centimes is an integer and negatives are rejected" do
      assert insert(%{vehicle_value_centimes: 25_000_000}).vehicle_value_centimes == 25_000_000

      assert %{vehicle_value_centimes: [_]} =
               errors_on(Quote.changeset(%Quote{}, %{vehicle_value_centimes: -1}))
    end
  end

  describe "context field: ip inet" do
    test "a valid IP stores and reads back as a string" do
      quote = insert(%{ip: "196.200.1.5"})
      assert Repo.get!(Quote, quote.id).ip == "196.200.1.5"
    end

    test "an invalid IP is rejected" do
      changeset = Quote.changeset(%Quote{}, %{ip: "not-an-ip"})
      refute changeset.valid?
    end
  end
end
