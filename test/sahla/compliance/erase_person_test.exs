defmodule Sahla.Compliance.ErasePersonTest do
  use Sahla.DataCase, async: true

  alias Sahla.Accounts
  alias Sahla.Audit
  alias Sahla.Compliance
  alias Sahla.Compliance.Consent
  alias Sahla.Notifications.Log
  alias Sahla.Quoting
  alias Sahla.Quoting.Quote

  @phone "+212612345678"
  @password "correct-horse-battery-staple-42"

  defp admin(role) do
    {:ok, admin} =
      Accounts.register_admin(%{
        email: "#{role}-#{System.unique_integer([:positive])}@sahla.ma",
        password: @password,
        role: role
      })

    admin
  end

  # A quote carrying full PII, a verified phone, two consents (with IPs) and one
  # logged message addressed to the same phone.
  defp person_fixture do
    {:ok, quote} = Quoting.create_quote()

    {:ok, _} =
      Quoting.upsert_step(quote, :contact, %{
        first_name: "Amina",
        last_name: "El Fassi",
        phone: @phone,
        email: "amina@example.ma",
        consent_cgu: true,
        consent_transmission: true
      })

    quote = Quoting.get_quote_by_token(quote.token)
    verified_at = DateTime.truncate(DateTime.utc_now(), :second)
    {:ok, quote} = quote |> Quote.mark_phone_verified(verified_at) |> Repo.update()

    {:ok, _consents} =
      Compliance.capture_consents(quote, %{cgu: true, transmission: true, ip: "196.200.1.1"})

    {:ok, _log} =
      Log.record(%{
        channel: :sms,
        recipient: @phone,
        template: "otp_code",
        idempotency_key: "otp-#{quote.id}"
      })

    quote
  end

  defp reload(quote), do: Repo.get!(Quote, quote.id)

  describe "erase_person/2 authorization" do
    test "refuses without an actor" do
      person_fixture()
      assert Compliance.erase_person(@phone) == {:error, :forbidden}
    end

    test "refuses an agent (lacks :erase_person)" do
      person_fixture()
      assert Compliance.erase_person(@phone, actor: admin(:agent)) == {:error, :forbidden}
    end

    test "allows ops and superadmin" do
      person_fixture()
      assert {:ok, _} = Compliance.erase_person(@phone, actor: admin(:ops))

      person_fixture()
      assert {:ok, _} = Compliance.erase_person(@phone, actor: admin(:superadmin))
    end
  end

  describe "erase_person/2 scrubbing" do
    setup do
      quote = person_fixture()
      {:ok, result} = Compliance.erase_person(@phone, actor: admin(:ops), ip: "41.1.1.1")
      %{quote: quote, result: result}
    end

    test "nulls every PII column but keeps the pseudonymous hash and stats", %{quote: quote} do
      erased = reload(quote)

      assert is_nil(erased.phone_enc)
      assert is_nil(erased.first_name)
      assert is_nil(erased.last_name)
      assert is_nil(erased.email)
      assert is_nil(erased.phone_verified_at)

      # Retained: the one-way hash (tombstone lookup) and anonymous stats.
      refute is_nil(erased.phone_hash)
      assert erased.status == quote.status
      refute is_nil(erased.erased_at)
    end

    test "leaves the tombstone findable by phone_hash with no recoverable PII" do
      found = Repo.all(from q in Quote, where: q.phone_hash == ^@phone)
      assert [row] = found
      assert is_nil(row.phone_enc)
      assert is_nil(row.first_name)
    end

    test "nulls consent IPs while keeping the consent rows" do
      consents = Repo.all(Consent)
      # capture_consents writes one row per kind (cgu, transmission, marketing).
      assert length(consents) == 3
      assert Enum.all?(consents, &is_nil(&1.ip))
    end

    test "nulls the recipient hash on matching log rows" do
      assert [log] = Repo.all(Sahla.Notifications.DeliveryLog)
      assert is_nil(log.to_hash)
    end

    test "reports the scrub counts", %{result: result} do
      assert result.quotes == 1
      assert result.consents == 3
      assert result.messages == 1
      assert is_binary(result.target_hash)
    end

    test "writes an audit entry naming the actor and target hash", %{result: result} do
      entries = Audit.for_entity("person", result.target_hash)
      assert [entry] = entries
      assert entry.action == "erase_person"
      refute is_nil(entry.admin_id)
      assert entry.after["quotes"] == 1
    end
  end

  test "is idempotent — a second erase finds the tombstone and re-scrubs harmlessly" do
    quote = person_fixture()
    {:ok, _} = Compliance.erase_person(@phone, actor: admin(:ops))
    assert {:ok, result} = Compliance.erase_person(@phone, actor: admin(:ops))
    assert result.quotes == 1
    assert is_nil(reload(quote).first_name)
  end
end
