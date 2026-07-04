defmodule Sahla.QuotingTest do
  use Sahla.DataCase, async: true

  import Ecto.Query, only: [from: 2]

  alias Sahla.Cities.City
  alias Sahla.Leads
  alias Sahla.Quoting
  alias Sahla.Quoting.{Quote, Steps}

  defp city_fixture do
    Repo.insert!(
      City.changeset(%City{}, %{
        name_fr: "Casablanca-#{System.unique_integer([:positive])}",
        name_ar: "الدار البيضاء",
        region: "Casablanca-Settat",
        risk_zone: 3
      })
    )
  end

  defp vehicle_params(city) do
    %{
      fiscal_power: 7,
      fuel: :diesel,
      usage: :personnel,
      city_id: city.id,
      parking: :garage
    }
  end

  describe "create_quote/1" do
    test "returns a draft with a unique token" do
      assert {:ok, %Quote{} = quote} = Quoting.create_quote()
      assert quote.status == :draft
      assert is_binary(quote.token) and quote.token != ""
      assert quote.current_step == 1

      {:ok, other} = Quoting.create_quote()
      assert other.token != quote.token
    end

    test "stores locale, ip and user_agent" do
      {:ok, quote} =
        Quoting.create_quote(%{locale: "ar", ip: "196.200.1.1", user_agent: "Mozilla/5.0"})

      assert quote.locale == "ar"
      assert quote.ip == "196.200.1.1"
      assert quote.user_agent == "Mozilla/5.0"
    end

    test "keeps only known utm keys and drops unexpected/raw params" do
      {:ok, quote} =
        Quoting.create_quote(%{
          utm: %{
            "utm_source" => "google",
            "utm_medium" => "cpc",
            "evil" => "<script>",
            "password" => "secret",
            :utm_campaign => "ramadan"
          }
        })

      assert quote.utm == %{
               "utm_source" => "google",
               "utm_medium" => "cpc",
               "utm_campaign" => "ramadan"
             }

      refute Map.has_key?(quote.utm, "evil")
      refute Map.has_key?(quote.utm, "password")
    end
  end

  describe "get_quote_by_token/1" do
    test "returns the quote for a known token" do
      {:ok, quote} = Quoting.create_quote()
      assert %Quote{id: id} = Quoting.get_quote_by_token(quote.token)
      assert id == quote.id
    end

    test "returns nil for an unknown token" do
      assert Quoting.get_quote_by_token("does-not-exist") == nil
    end

    test "an expired quote is not resumable (returns nil)" do
      {:ok, quote} = Quoting.create_quote()
      {:ok, _expired} = Quoting.expire_quote(quote)

      assert Quoting.get_quote_by_token(quote.token) == nil
    end
  end

  describe "upsert_step/3 — autosave" do
    test "persists only the given step's fields and advances current_step" do
      city = city_fixture()
      {:ok, quote} = Quoting.create_quote()

      assert {:ok, saved} = Quoting.upsert_step(quote, :vehicle, vehicle_params(city))
      assert saved.fiscal_power == 7
      assert saved.fuel == :diesel
      assert saved.city_id == city.id
      assert saved.current_step == 1

      assert {:ok, saved} =
               Quoting.upsert_step(saved, :coverage, %{formula: :rc, options: ~w(vol)})

      assert saved.formula == :rc
      assert saved.options == ~w(vol)
      # advanced to step 3, earlier vehicle data still present
      assert saved.current_step == 3
      assert saved.fiscal_power == 7
    end

    test "returns {:error, changeset} with field-keyed errors on invalid params" do
      {:ok, quote} = Quoting.create_quote()

      assert {:error, changeset} = Quoting.upsert_step(quote, :driver, %{})
      errors = Steps.field_errors(changeset)
      assert errors.birth_date == "can't be blank"
      assert errors.license_date == "can't be blank"
      # nothing was persisted
      assert Quoting.get_quote_by_token(quote.token).birth_date == nil
    end

    test "the vehicle step's conditional value requirement reads the quote's stored formula" do
      city = city_fixture()
      {:ok, quote} = Quoting.create_quote()

      # choose a valuing formula first
      {:ok, quote} = Quoting.upsert_step(quote, :coverage, %{formula: :tous_risques})

      # now the vehicle step must demand a value
      assert {:error, changeset} = Quoting.upsert_step(quote, :vehicle, vehicle_params(city))
      assert Steps.field_errors(changeset).vehicle_value_centimes == "can't be blank"

      params = Map.put(vehicle_params(city), :vehicle_value_centimes, 18_000_000)
      assert {:ok, saved} = Quoting.upsert_step(quote, :vehicle, params)
      assert saved.vehicle_value_centimes == 18_000_000
    end

    test "the contact step encrypts the phone (keyed HMAC) and drops consent booleans" do
      {:ok, quote} = Quoting.create_quote()

      params = %{
        first_name: "Amina",
        last_name: "El Fassi",
        phone: "+212612345678",
        consent_cgu: true,
        consent_transmission: true
      }

      assert {:ok, saved} = Quoting.upsert_step(quote, :contact, params)
      assert saved.first_name == "Amina"
      assert saved.phone_enc == "+212612345678"
      assert saved.phone_hash

      # raw phone is never stored in the column
      %{rows: [[raw]]} =
        Repo.query!("SELECT phone_enc FROM quotes WHERE id = $1", [Ecto.UUID.dump!(saved.id)])

      refute String.contains?(to_string(raw), "612345678")

      # consent booleans are not quote columns — they are dropped here (persisted by lrs.3)
      refute Map.has_key?(Map.from_struct(saved), :consent_cgu)
    end
  end

  describe "resume_url/2" do
    test "builds a locale-correct absolute /devis/:token URL" do
      {:ok, quote} = Quoting.create_quote()

      fr = Quoting.resume_url(quote, "fr")
      ar = Quoting.resume_url(quote, "ar")

      assert fr =~ "/devis/#{quote.token}"
      refute fr =~ "/ar/devis/"
      assert ar =~ "/ar/devis/#{quote.token}"
      # absolute (carries the endpoint host)
      assert String.starts_with?(fr, "http")
    end

    test "defaults to French" do
      {:ok, quote} = Quoting.create_quote()
      assert Quoting.resume_url(quote) =~ "/devis/#{quote.token}"
    end
  end

  describe "list_abandoned_drafts/1" do
    @cutoff ~U[2026-07-04 12:00:00Z]

    defp draft_at(dt) do
      {:ok, quote} = Quoting.create_quote()
      {1, _} = Repo.update_all(from(q in Quote, where: q.id == ^quote.id), set: [updated_at: dt])
      Repo.reload!(quote)
    end

    test "returns only draft, lead-free quotes older than the cutoff, newest-first" do
      old = draft_at(~U[2026-07-04 09:00:00Z])
      newer = draft_at(~U[2026-07-04 10:00:00Z])

      # excluded: at/after the cutoff boundary
      _boundary = draft_at(@cutoff)
      _recent = draft_at(~U[2026-07-04 13:00:00Z])

      # excluded: has a lead
      with_lead = draft_at(~U[2026-07-04 08:00:00Z])
      {:ok, _} = Leads.create_from_quote(with_lead)

      # excluded: completed / expired
      completed = draft_at(~U[2026-07-04 08:00:00Z])
      Repo.update_all(from(q in Quote, where: q.id == ^completed.id), set: [status: "completed"])
      expired = draft_at(~U[2026-07-04 08:00:00Z])
      {:ok, _} = Quoting.expire_quote(expired)

      ids = Quoting.list_abandoned_drafts(@cutoff) |> Enum.map(& &1.id)
      assert ids == [newer.id, old.id]
    end

    test "orders same-timestamp drafts by a desc :id tiebreaker" do
      same = ~U[2026-07-04 07:00:00Z]
      a = draft_at(same)
      b = draft_at(same)

      ids = Quoting.list_abandoned_drafts(@cutoff) |> Enum.map(& &1.id)
      expected = [a.id, b.id] |> Enum.sort() |> Enum.reverse()
      assert ids == expected
    end
  end
end
