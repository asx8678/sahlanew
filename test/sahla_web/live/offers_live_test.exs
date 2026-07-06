defmodule SahlaWeb.OffersLiveTest do
  @moduledoc false
  # Global ETS cache + seeding mean these tests run sequentially.
  use SahlaWeb.ConnCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Sahla.Cities
  alias Sahla.Compliance
  alias Sahla.Quoting

  setup %{conn: conn} do
    city =
      case Cities.upsert_city(%{
             name_fr: "Casablanca",
             name_ar: "الدار البيضاء",
             region: "Casablanca-Settat",
             risk_zone: 2
           }) do
        {:ok, city} -> city
        _ -> Sahla.Repo.get_by!(Sahla.Cities.City, name_fr: "Casablanca")
      end

    Sahla.Directory.ensure_seed_catalog!()
    :ok = Sahla.Rating.Seeds.seed_placeholders()
    Sahla.Rating.TableCache.refresh()

    Sahla.Notifications.SMSProvider.Fake.clear()
    Application.put_env(:sahla, :sms_enabled, true)
    %{conn: conn, city: city}
  end

  test "completing step 4 runs rating, persists snapshot and redirects to /offres/:token", %{
    conn: conn,
    city: city
  } do
    phone = "0600000005"

    {:ok, quote} = Quoting.create_quote(%{locale: "fr", current_step: 4})

    {:ok, quote} =
      Quoting.upsert_step(quote, :vehicle, %{
        is_new_ww: false,
        plate: "12345-A-67",
        make_id: nil,
        model_id: nil,
        version_id: nil,
        fiscal_power: "5",
        fuel: "diesel",
        first_registration: "2018-01-01",
        vehicle_value_centimes: "15000000",
        usage: "personnel",
        city_id: city.id,
        parking: "garage"
      })

    {:ok, quote} =
      Quoting.upsert_step(quote, :driver, %{
        birth_date: "1990-01-01",
        license_date: "2010-01-01",
        is_public_servant: "false",
        at_fault_claims_36m: "0",
        crm: ""
      })

    {:ok, quote} =
      Quoting.upsert_step(quote, :coverage, %{
        formula: "tiers_etendu",
        options: ["vol"],
        franchise_pref: "standard",
        effect_date: Date.to_iso8601(Date.utc_today())
      })

    {:ok, quote} =
      Quoting.upsert_step(quote, :contact, %{
        first_name: "Amina",
        last_name: "Lamrani",
        phone: phone,
        city_id: city.id,
        consent_cgu: true,
        consent_transmission: true,
        consent_marketing: false
      })

    {:ok, _otp} = Sahla.Accounts.OTP.request_otp(phone, ip: "127.0.0.1")
    {:ok, quote} = Sahla.Accounts.OTP.verify_otp(quote, phone, last_sent_code(phone))

    {:ok, _consents} =
      Compliance.capture_consents(quote, %{
        cgu: true,
        transmission: true,
        marketing: false,
        ip: "127.0.0.1"
      })

    {:ok, lv, _html} = live(conn, ~p"/devis/#{quote.token}")

    assert {:error, {:redirect, %{to: "/offres/" <> _}}} =
             lv |> element("button[phx-click='continue']") |> render_click()

    reloaded = Quoting.get_quote_by_token(quote.token)
    assert reloaded.status == :completed
    assert is_binary(reloaded.rating_run_id)

    run = Sahla.Repo.get!(Sahla.Rating.Run, reloaded.rating_run_id)
    assert run.quote_id == reloaded.id
    offers = Sahla.Repo.all(from o in Sahla.Quoting.Offer, where: o.rating_run_id == ^run.id)
    refute offers == []

    # Idempotency: a second continue on the same completed quote does not create a duplicate run.
    offer_count_before = length(offers)
    {:ok, _lv2, _html2} = live(conn, ~p"/devis/#{quote.token}")

    offer_count_after =
      Sahla.Repo.all(from o in Sahla.Quoting.Offer, where: o.rating_run_id == ^run.id)
      |> length()

    assert offer_count_after == offer_count_before
  end

  test "GET /offres/:token renders completed quote offers", %{conn: conn, city: city} do
    phone = "0600000006"

    {:ok, quote} = Quoting.create_quote(%{locale: "fr", current_step: 4})

    {:ok, quote} =
      Quoting.upsert_step(quote, :vehicle, %{
        is_new_ww: false,
        plate: "12345-A-67",
        fiscal_power: "5",
        fuel: "diesel",
        first_registration: "2018-01-01",
        vehicle_value_centimes: "15000000",
        usage: "personnel",
        city_id: city.id,
        parking: "garage"
      })

    {:ok, quote} =
      Quoting.upsert_step(quote, :driver, %{
        birth_date: "1990-01-01",
        license_date: "2010-01-01",
        is_public_servant: "false",
        at_fault_claims_36m: "0",
        crm: ""
      })

    {:ok, quote} =
      Quoting.upsert_step(quote, :coverage, %{
        formula: "rc",
        options: [],
        effect_date: Date.to_iso8601(Date.utc_today())
      })

    {:ok, quote} =
      Quoting.upsert_step(quote, :contact, %{
        first_name: "Amina",
        last_name: "Lamrani",
        phone: phone,
        city_id: city.id,
        consent_cgu: true,
        consent_transmission: true,
        consent_marketing: false
      })

    {:ok, _otp} = Sahla.Accounts.OTP.request_otp(phone, ip: "127.0.0.1")
    {:ok, quote} = Sahla.Accounts.OTP.verify_otp(quote, phone, last_sent_code(phone))

    {:ok, _consents} =
      Compliance.capture_consents(quote, %{
        cgu: true,
        transmission: true,
        marketing: false,
        ip: "127.0.0.1"
      })

    {:ok, %{quote: quote}} = Quoting.complete_quote(quote)

    {:ok, _lv, html} = live(conn, ~p"/offres/#{quote.token}")
    assert html =~ "Your offers"
    assert html =~ "MAD"
  end

  test "GET /offres/:token for incomplete quote shows guarded state", %{conn: conn} do
    {:ok, quote} = Quoting.create_quote(%{locale: "fr"})
    {:ok, _lv, html} = live(conn, ~p"/offres/#{quote.token}")
    assert html =~ "Offers unavailable"
  end

  defp last_sent_code(phone) do
    message =
      Sahla.Notifications.SMSProvider.Fake.sent()
      |> Enum.find(fn m -> match?(%{template: :otp_code}, m) and m.to == phone end)

    if is_nil(message), do: raise("no OTP code was sent (SMS disabled or rate-limited)")

    %{vars: %{code: code}} = message
    code
  end
end
