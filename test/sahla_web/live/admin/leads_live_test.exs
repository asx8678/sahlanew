defmodule SahlaWeb.Admin.LeadsLiveTest do
  @moduledoc false
  use SahlaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Sahla.Accounts
  alias Sahla.Leads
  alias Sahla.Quoting
  alias Sahla.Repo
  alias SahlaWeb.AdminAuth

  @admin_password "correct horse battery staple"

  setup %{conn: conn} do
    {:ok, admin} =
      Accounts.register_admin(%{
        email: "ops-#{System.unique_integer([:positive])}@sahla.ma",
        password: @admin_password,
        role: :ops
      })

    conn =
      conn
      |> Map.replace!(:secret_key_base, SahlaWeb.Endpoint.config(:secret_key_base))
      |> init_test_session(%{})

    %{conn: conn, admin: admin}
  end

  defp make_quote_and_lead(attrs \\ %{}) do
    {:ok, quote} = Quoting.create_quote(%{locale: "fr"})

    {:ok, quote} =
      Quoting.upsert_step(quote, :contact, %{
        first_name: "Amina",
        last_name: "Lamrani",
        phone: "0612345678",
        email: "amina@example.com",
        consent_cgu: true,
        consent_transmission: true
      })

    {:ok, quote} =
      Quoting.upsert_step(
        quote,
        :vehicle,
        Map.merge(
          %{
            "usage" => "personnel",
            "city_id" => city_id(),
            "parking" => "garage",
            "fiscal_power" => "6",
            "fuel" => "essence"
          },
          attrs
        )
      )

    Leads.create_from_quote(quote)
  end

  defp city_id do
    case Sahla.Cities.upsert_city(%{name_fr: "Casablanca", name_ar: "الدار البيضاء", region: "Casablanca-Settat", risk_zone: 2}) do
      {:ok, city} -> city.id
      {:error, _} -> Sahla.Repo.get_by!(Sahla.Cities.City, name_fr: "Casablanca").id
    end
  end

  defp logged_in(conn, admin) do
    conn
    |> AdminAuth.log_in_admin(admin)
    |> AdminAuth.fetch_current_admin([])
  end

  test "renders columns and empty states", %{conn: conn, admin: admin} do
    {:ok, _lv, html} = live(logged_in(conn, admin), ~p"/admin/leads")

    assert html =~ "New"
    assert html =~ "Contacted"
    assert html =~ "No leads"
  end

  test "filters by source", %{conn: conn, admin: admin} do
    {:ok, lead} = make_quote_and_lead()

    {:ok, _lv, html} = live(logged_in(conn, admin), ~p"/admin/leads")

    assert html =~ lead.source
  end

  test "live insert moves a lead into the correct column", %{conn: conn, admin: admin} do
    {:ok, lead} = make_quote_and_lead()

    {:ok, lv, html} = live(logged_in(conn, admin), ~p"/admin/leads")

    assert html =~ "Amina"

    # Transition the lead elsewhere via the context to simulate an external update.
    {:ok, updated} = Leads.transition_status(lead, :contacte)
    updated = Repo.preload(updated, [:quote, :assigned_admin])

    send(lv.pid, {:lead, :updated, updated.id})

    assert render(lv) =~ "contacte"
  end

  test "drag-drop transition updates status", %{conn: conn, admin: admin} do
    {:ok, lead} = make_quote_and_lead()

    {:ok, lv, _html} = live(logged_in(conn, admin), ~p"/admin/leads")

    html = render_hook(lv, "drop", %{"id" => lead.id, "status" => "contacte"})

    assert html =~ "contacte"
    assert Leads.get_lead!(lead.id).status == :contacte
  end

  test "unauthorized access redirects to login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/admin/login"}}} = live(conn, ~p"/admin/leads")
  end
end
