defmodule SahlaWeb.DevisLiveTest do
  @moduledoc false
  use SahlaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Sahla.Cities
  alias Sahla.Compliance
  alias Sahla.Quoting
  alias Sahla.Vehicles

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

    make =
      %Sahla.Vehicles.Make{}
      |> Ecto.Changeset.change(%{name: "Renault", popular: true})
      |> Sahla.Repo.insert!()

    model =
      %Sahla.Vehicles.Model{}
      |> Ecto.Changeset.change(%{make_id: make.id, name: "Clio"})
      |> Sahla.Repo.insert!()

    version =
      %Sahla.Vehicles.Version{}
      |> Ecto.Changeset.change(%{
        model_id: model.id,
        name: "Clio 4 1.5 dCi",
        fiscal_power: 5,
        years: 2012..2019
      })
      |> Sahla.Repo.insert!()

    Sahla.Notifications.SMSProvider.Fake.clear()
    Application.put_env(:sahla, :sms_enabled, true)
    %{conn: conn, city: city, make: make, model: model, version: version}
  end

  test "GET /devis/new creates a fresh quote and redirects", %{conn: conn} do
    conn = get(conn, ~p"/devis/new")
    assert %{status: 302} = conn
    assert String.starts_with?(redirected_to(conn), "/devis/")
  end

  test "mount loads an existing quote and shows the current step", %{conn: conn} do
    {:ok, quote} = Quoting.create_quote(%{locale: "fr"})

    {:ok, _lv, html} = live(conn, ~p"/devis/#{quote.token}")

    assert html =~ "Your vehicle"
    assert html =~ ~s(aria-label="Quote progress")
  end

  test "an unknown token creates a new quote and redirects", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/devis/" <> _}}} = live(conn, ~p"/devis/unknown-token")
  end

  test "autosave persists a field", %{conn: conn} do
    {:ok, quote} = Quoting.create_quote(%{locale: "fr"})

    {:ok, lv, _html} = live(conn, ~p"/devis/#{quote.token}")

    html = lv |> element("form") |> render_change(%{step: %{plate: "12345-A-67"}})
    assert html =~ "12345-A-67"

    reloaded = Quoting.get_quote_by_token(quote.token)
    assert reloaded.plate == "12345-A-67"
  end

  test "continue advances the step and resumes at that step", %{conn: conn, city: city} do
    {:ok, quote} = Quoting.create_quote(%{locale: "fr"})

    {:ok, lv, _html} = live(conn, ~p"/devis/#{quote.token}")

    lv
    |> element("form")
    |> render_change(%{
      step: %{
        usage: "personnel",
        city_id: city.id,
        parking: "garage",
        fuel: "essence",
        fiscal_power: "6",
        first_registration: "2020-01-01"
      }
    })

    lv |> element("button[phx-click='continue']") |> render_click()

    assert Quoting.get_quote_by_token(quote.token).current_step == 2

    {:ok, _lv, html} = live(conn, ~p"/devis/#{quote.token}")
    assert html =~ "Driver profile"
  end

  test "back returns to the previous step", %{conn: conn} do
    {:ok, quote} = Quoting.create_quote(%{locale: "fr", current_step: 2})

    {:ok, lv, _html} = live(conn, ~p"/devis/#{quote.token}")

    lv |> element("button[phx-click='back']") |> render_click()

    assert Quoting.get_quote_by_token(quote.token).current_step == 1
  end

  test "route is mirrored under /ar", %{conn: conn} do
    {:ok, quote} = Quoting.create_quote(%{locale: "ar"})

    {:ok, _lv, html} = live(conn, ~p"/ar/devis/#{quote.token}")
    assert html =~ ~S(<html lang="ar" dir="rtl">)
    assert html =~ "Your vehicle"
  end

  test "an expired quote renders the expired screen", %{conn: conn} do
    {:ok, quote} = Quoting.create_quote(%{locale: "fr"})
    {:ok, _quote} = Quoting.expire_quote(quote)

    {:ok, _lv, html} = live(conn, ~p"/devis/#{quote.token}")
    assert html =~ "This quote link has expired"
  end

  test "mounting a resumed quote pushes a funnel_start plausible event", %{conn: conn} do
    {:ok, quote} = Quoting.create_quote(%{locale: "fr"})

    {:ok, lv, _html} = live(conn, ~p"/devis/#{quote.token}")

    assert_push_event(lv, "plausible-event", %{name: "funnel_start", props: %{source: "resume"}})
  end

  test "step 1 option cards persist usage, city and parking", %{conn: conn, city: city} do
    {:ok, quote} = Quoting.create_quote(%{locale: "fr"})

    {:ok, lv, _html} = live(conn, ~p"/devis/#{quote.token}")

    lv
    |> element("form")
    |> render_change(%{
      step: %{
        usage: "personnel",
        city_id: city.id,
        parking: "garage"
      }
    })

    reloaded = Quoting.get_quote_by_token(quote.token)
    assert reloaded.usage == :personnel
    assert reloaded.city_id == city.id
    assert reloaded.parking == :garage
  end

  test "step 1 autocomplete pick prefills make/version", %{conn: conn, make: make, version: version} do
    {:ok, quote} = Quoting.create_quote(%{locale: "fr"})

    {:ok, lv, _html} = live(conn, ~p"/devis/#{quote.token}")

    lv
    |> element("#vehicle-form")
    |> render_change(%{
      step: %{
        make_id: make.id,
        version_id: version.id,
        usage: "personnel",
        parking: "garage",
        fuel: "diesel"
      }
    })

    reloaded = Quoting.get_quote_by_token(quote.token)
    assert reloaded.make_id == make.id
    assert reloaded.version_id == version.id
  end

  test "step 1 free-text vehicle records unmatched entry", %{conn: conn} do
    {:ok, quote} = Quoting.create_quote(%{locale: "fr"})

    {:ok, lv, _html} = live(conn, ~p"/devis/#{quote.token}")

    lv
    |> element("#vehicle-form")
    |> render_change(%{
      step: %{
        autocomplete: "false",
        raw_make: "Dacia",
        raw_model: "Logan",
        raw_version: "1.0 SCe"
      }
    })

    assert Vehicles.list_unmatched() |> Enum.any?(fn u ->
      u.raw_make == "Dacia" && u.raw_model == "Logan"
    end)
  end

  test "step 3 formula switch persists and EVCAT stays selected", %{conn: conn} do
    {:ok, quote} = Quoting.create_quote(%{locale: "fr", current_step: 3})

    {:ok, lv, _html} = live(conn, ~p"/devis/#{quote.token}")

    lv
    |> element("#coverage-form")
    |> render_change(%{step: %{formula: "tous_risques", options: ["vol"]}})

    reloaded = Quoting.get_quote_by_token(quote.token)
    assert reloaded.formula == :tous_risques
    assert "evcat" in reloaded.options
  end

  test "step 3 effect date defaults to today", %{conn: conn} do
    {:ok, quote} = Quoting.create_quote(%{locale: "fr", current_step: 3})

    {:ok, _lv, html} = live(conn, ~p"/devis/#{quote.token}")

    assert html =~ Date.to_iso8601(Date.utc_today())
  end

  test "step 4 gating blocks continue until phone verified", %{conn: conn, city: city} do
    {:ok, quote} =
      Quoting.create_quote(%{locale: "fr", current_step: 4})
      |> then(fn {:ok, q} ->
        Quoting.upsert_step(q, :contact, %{
          first_name: "Amina",
          last_name: "Lamrani",
          phone: "0612345678",
          city_id: city.id,
          consent_cgu: true,
          consent_transmission: true,
          consent_marketing: false
        })
      end)

    {:ok, _lv, html} = live(conn, ~p"/devis/#{quote.token}")

    assert html =~ "Send verification code"
    # Continue is disabled because the phone is not verified.
    assert html =~ "disabled"
  end

  test "step 4 phone change resets OTP section", %{conn: conn, city: city} do
    phone_a = "0600000001"
    phone_b = "0600000002"

    {:ok, quote} = Quoting.create_quote(%{locale: "fr", current_step: 4})

    {:ok, quote} =
      Quoting.upsert_step(quote, :contact, %{
        first_name: "Amina",
        last_name: "Lamrani",
        phone: phone_a,
        city_id: city.id,
        consent_cgu: true,
        consent_transmission: true,
        consent_marketing: false
      })

    {:ok, _otp} = Sahla.Accounts.OTP.request_otp(phone_a, ip: "127.0.0.1")
    quote = Quoting.get_quote_by_token(quote.token)
    {:ok, quote} = Sahla.Accounts.OTP.verify_otp(quote, phone_a, last_sent_code(phone_a))

    {:ok, lv, _html} = live(conn, ~p"/devis/#{quote.token}")

    html =
      lv
      |> element("#contact-form")
      |> render_change(%{step: %{phone: phone_b}})

    assert html =~ "Send verification code"
  end

  test "step 4 consent submit records three rows", %{conn: conn, city: city} do
    phone = "0600000003"

    {:ok, quote} = Quoting.create_quote(%{locale: "fr", current_step: 4})

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

    {:ok, lv, _html} = live(conn, ~p"/devis/#{quote.token}")

    lv
    |> element("#contact-form")
    |> render_submit(%{
      "consent_cgu" => "true",
      "consent_transmission" => "true",
      "consent_marketing" => "false"
    })

    consents = Compliance.consents_for(quote)
    assert length(consents) == 3
    assert Enum.any?(consents, &(&1.kind == :cgu and &1.granted))
    assert Enum.any?(consents, &(&1.kind == :transmission and &1.granted))
    assert Enum.any?(consents, &(&1.kind == :marketing and not &1.granted))
  end

  test "step 4 OTP verify enables continue", %{conn: conn, city: city} do
    phone = "0600000004"

    {:ok, quote} =
      Quoting.create_quote(%{locale: "fr", current_step: 4})
      |> then(fn {:ok, q} ->
        Quoting.upsert_step(q, :contact, %{
          first_name: "Amina",
          last_name: "Lamrani",
          phone: phone,
          city_id: city.id,
          consent_cgu: true,
          consent_transmission: true,
          consent_marketing: false
        })
      end)

    {:ok, lv, _html} = live(conn, ~p"/devis/#{quote.token}")

    html = lv |> element("button[phx-click='request_otp']") |> render_click()
    refute html =~ "Enter a phone number first"
    refute html =~ "Too many attempts"

    code = last_sent_code(phone)

    html =
      lv
      |> element("input[name='code']")
      |> render_change(%{"code" => code})

    assert html =~ "Phone verified"

    reloaded = Quoting.get_quote_by_token(quote.token)
    assert not is_nil(reloaded.phone_verified_at)
  end

  test "step 2 CRM 'I do not know' stores null and still allows continue", %{conn: conn} do
    {:ok, quote} = Quoting.create_quote(%{locale: "fr", current_step: 2})

    {:ok, lv, _html} = live(conn, ~p"/devis/#{quote.token}")

    lv
    |> element("#driver-form")
    |> render_change(%{
      step: %{
        birth_date: "1990-01-01",
        license_date: "2010-01-01",
        is_public_servant: "false",
        at_fault_claims_36m: "0",
        crm: ""
      }
    })

    reloaded = Quoting.get_quote_by_token(quote.token)
    assert reloaded.birth_date == ~D[1990-01-01]
    assert reloaded.license_date == ~D[2010-01-01]
    assert reloaded.is_public_servant == false
    assert reloaded.at_fault_claims_36m == 0
    assert is_nil(reloaded.crm)

    lv |> element("button[phx-click='continue']") |> render_click()

    assert Quoting.get_quote_by_token(quote.token).current_step == 3
  end

  test "step 2 relevé upload stores private path and encrypted metadata", %{conn: conn} do
    dir =
      Path.join(System.tmp_dir!(), "sahla_devis_upload_test_#{System.unique_integer([:positive])}")

    Application.put_env(:sahla, :uploads_dir, dir)
    on_exit(fn -> File.rm_rf(dir) end)

    {:ok, quote} = Quoting.create_quote(%{locale: "fr", current_step: 2})

    {:ok, lv, _html} = live(conn, ~p"/devis/#{quote.token}")

    # Fill required driver fields first so the step is valid.
    lv
    |> element("#driver-form")
    |> render_change(%{
      step: %{
        birth_date: "1990-01-01",
        license_date: "2010-01-01",
        is_public_servant: "false",
        at_fault_claims_36m: "0"
      }
    })

    pdf = <<0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x34, 0x0A>>
    lv
    |> file_input("#driver-form", :releve_doc, [%{
      name: "releve.pdf",
      content: pdf
    }])
    |> render_upload("releve.pdf")

    lv
    |> element("#driver-form")
    |> render_submit(%{})

    reloaded = Quoting.get_quote_by_token(quote.token)
    assert is_binary(reloaded.releve_doc_path)

    assert %{
             "content_type" => "application/pdf",
             "original_name" => "releve.pdf",
             "size" => 9
           } = reloaded.releve_doc_meta_enc
  end

  defp last_sent_code(phone) do
    messages =
      Sahla.Notifications.SMSProvider.Fake.sent()
      |> Enum.filter(&match?(%{template: :otp_code}, &1))
      |> maybe_filter_phone(phone)

    if messages == [] do
      raise "no OTP code was sent (SMS disabled or rate-limited)"
    end

    %{vars: %{code: code}} = hd(messages)
    code
  end

  defp maybe_filter_phone(messages, nil), do: messages
  defp maybe_filter_phone(messages, phone), do: Enum.filter(messages, &(&1.to == phone))
end
