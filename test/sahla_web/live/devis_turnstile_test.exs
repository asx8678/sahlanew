defmodule SahlaWeb.DevisTurnstileTest do
  @moduledoc false
  # async: false — flips the global Settings turnstile flag (ETS cache + DB)
  # and pins the :antibot_adapter application env. Running alongside the
  # async DevisLiveTest would leak the flag into its mount path.
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

    # Deterministic adapter: always the Fake; outcome flipped per-test.
    Application.put_env(:sahla, :antibot_adapter, Sahla.AntiBot.Fake)

    on_exit(fn ->
      Application.delete_env(:sahla, :antibot_adapter)
      Sahla.Settings.put_feature("turnstile", false)
      Sahla.AntiBot.Fake.clear()
    end)

    %{conn: conn, city: city, make: make, model: model, version: version}
  end

  describe "step 1 Turnstile anti-bot gate" do
    test "flag off passes through with no widget rendered", %{conn: conn} do
      Sahla.Settings.put_feature("turnstile", false)

      {:ok, quote} = Quoting.create_quote(%{locale: "fr"})

      {:ok, _lv, html} = live(conn, ~p"/devis/#{quote.token}")

      # No Turnstile widget when the flag is off.
      refute html =~ "Security check"
    end

    test "flag on with a Fake success token advances step 1 to 2", %{
      conn: conn,
      city: city
    } do
      Sahla.Settings.put_feature("turnstile", true)

      {:ok, quote} = Quoting.create_quote(%{locale: "fr"})
      {:ok, lv, _html} = live(conn, ~p"/devis/#{quote.token}")

      # Simulate the widget callback pushing a verified token.
      render_hook(lv, "set_turnstile_token", %{"token" => "XXXX.DUMMY.TOKEN.XXXX"})

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

      assert Quoting.get_quote_by_token(quote.token).current_step == 2
    end

    test "flag on with a failed verification blocks step 1 progression", %{
      conn: conn,
      city: city
    } do
      Sahla.Settings.put_feature("turnstile", true)
      Sahla.AntiBot.Fake.set_result({:error, :challenge_failed})

      {:ok, quote} = Quoting.create_quote(%{locale: "fr"})
      {:ok, lv, _html} = live(conn, ~p"/devis/#{quote.token}")

      render_hook(lv, "set_turnstile_token", %{"token" => "bad-token"})

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

      html = lv |> element("button[phx-click='continue']") |> render_click()

      # Gate fired: still on step 1 (vehicle form heading present, quote not advanced).
      assert html =~ "Your vehicle"
      assert Quoting.get_quote_by_token(quote.token).current_step == 1
    end

    test "flag on with no token at all blocks step 1 progression", %{
      conn: conn,
      city: city
    } do
      Sahla.Settings.put_feature("turnstile", true)

      {:ok, quote} = Quoting.create_quote(%{locale: "fr"})
      {:ok, lv, _html} = live(conn, ~p"/devis/#{quote.token}")

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

      # Continue without ever pushing a Turnstile token.
      html = lv |> element("button[phx-click='continue']") |> render_click()

      # Gate fired: still on step 1 (vehicle form heading present, quote not advanced).
      assert html =~ "Your vehicle"
      assert Quoting.get_quote_by_token(quote.token).current_step == 1
    end
  end
end
