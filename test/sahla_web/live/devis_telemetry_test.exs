defmodule SahlaWeb.DevisTelemetryTest do
  @moduledoc false
  # async: false — attaches :telemetry handlers to the global handler table,
  # which is shared across all tests; a unique id per test avoids collisions
  # but async:false keeps the capture-and-assert sequence deterministic.
  use SahlaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Sahla.Cities
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

    Sahla.Notifications.SMSProvider.Fake.clear()
    Sahla.AntiBot.Fake.clear()
    Application.put_env(:sahla, :sms_enabled, true)
    %{conn: conn, city: city}
  end

  # Attaches a one-shot handler that delivers the event to the test mailbox.
  defp capture(event) do
    id = {__MODULE__, event, make_ref()}
    parent = self()

    :telemetry.attach(
      id,
      [:sahla, :funnel, event],
      fn _name, measurements, metadata, _config ->
        send(parent, {event, measurements, metadata})
      end,
      nil
    )

    id
  end

  defp detach(id), do: :telemetry.detach(id)

  describe "step_completed telemetry" do
    test "emits [:sahla, :funnel, :step_completed] on each step advance with non-PII metadata", %{
      conn: conn,
      city: city
    } do
      {:ok, quote} = Quoting.create_quote(%{locale: "fr"})
      {:ok, lv, _html} = live(conn, ~p"/devis/#{quote.token}")

      id = capture(:step_completed)

      lv
      |> element("#vehicle-form")
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

      assert_received {:step_completed, measurements, metadata}
      assert measurements == %{count: 1}
      assert metadata == %{token: quote.token, step: :driver, step_number: 2, locale: "fr"}

      # Non-PII only.
      refute Map.has_key?(metadata, :phone)
      refute Map.has_key?(metadata, :first_name)
      refute Map.has_key?(metadata, :last_name)
      refute Map.has_key?(metadata, :email)

      detach(id)
    end
  end

  describe "otp_verified telemetry" do
    test "emits [:sahla, :funnel, :otp_verified] when the contact phone is verified", %{
      conn: conn,
      city: city
    } do
      phone = "0600000010"

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

      lv |> element("button[phx-click='request_otp']") |> render_click()
      code = last_sent_code(phone)

      id = capture(:otp_verified)

      lv
      |> element("input[name='code']")
      |> render_change(%{"code" => code})

      assert_received {:otp_verified, measurements, metadata}
      assert measurements == %{count: 1}
      assert metadata == %{token: quote.token, locale: "fr"}

      # The phone number must never appear in the telemetry metadata.
      refute Map.has_key?(metadata, :phone)
      refute Map.has_key?(metadata, :first_name)
      refute Map.has_key?(metadata, :last_name)
      refute Map.has_key?(metadata, :email)
      refute metadata == %{}
      refute inspect(metadata) =~ phone

      detach(id)
    end
  end

  defp last_sent_code(phone) do
    messages =
      Sahla.Notifications.SMSProvider.Fake.sent()
      |> Enum.filter(&match?(%{template: :otp_code}, &1))
      |> Enum.filter(&(&1.to == phone))

    if messages == [] do
      raise "no OTP code was sent (SMS disabled or rate-limited)"
    end

    %{vars: %{code: code}} = hd(messages)
    code
  end
end
