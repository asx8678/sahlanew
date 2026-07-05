defmodule SahlaWeb.Admin.LeadLiveTest do
  use SahlaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Sahla.Accounts
  alias Sahla.Leads
  alias Sahla.Quoting
  alias SahlaWeb.AdminAuth

  @admin_password "correct horse battery staple"

  setup %{conn: conn} do
    {:ok, admin} =
      Accounts.register_admin(%{
        email: "ops-#{System.unique_integer([:positive])}@sahla.ma",
        password: @admin_password,
        role: :ops
      })

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

    {:ok, lead} = Leads.create_from_quote(quote)

    conn =
      conn
      |> Map.replace!(:secret_key_base, SahlaWeb.Endpoint.config(:secret_key_base))
      |> init_test_session(%{})

    %{conn: conn, admin: admin, lead: lead, quote: quote}
  end

  test "mount loads the lead page and shows the lead status", %{
    conn: conn,
    admin: admin,
    lead: lead
  } do
    conn =
      conn
      |> AdminAuth.log_in_admin(admin)
      |> AdminAuth.fetch_current_admin([])

    {:ok, _lv, html} = live(conn, ~p"/admin/leads/#{lead.id}")

    assert html =~ "Amina"
    assert html =~ "Lead ##{String.slice(lead.id, 0, 8)}"
  end

  test "add_note posts a note, renders it in the timeline and persists a note activity", %{
    conn: conn,
    admin: admin,
    lead: lead
  } do
    conn =
      conn
      |> AdminAuth.log_in_admin(admin)
      |> AdminAuth.fetch_current_admin([])

    {:ok, lv, _html} = live(conn, ~p"/admin/leads/#{lead.id}")

    html =
      lv
      |> element("form[name='note']")
      |> render_submit(%{"note" => %{"body" => "Client demande un rappel demain"}})

    assert html =~ "Client demande un rappel demain"
    assert html =~ "note"

    assert [activity] =
             Leads.list_activities(lead)
             |> Enum.filter(&(&1.kind == :note and &1.body == "Client demande un rappel demain"))

    assert activity.kind == :note
    assert activity.admin_id == admin.id
  end

  test "status transition updates the lead status and logs a statut activity", %{
    conn: conn,
    admin: admin,
    lead: lead
  } do
    conn =
      conn
      |> AdminAuth.log_in_admin(admin)
      |> AdminAuth.fetch_current_admin([])

    {:ok, lv, _html} = live(conn, ~p"/admin/leads/#{lead.id}")

    html =
      lv
      |> element("[phx-click='transition_status'][phx-value-status='contacte']")
      |> render_click()

    assert html =~ "contacte"
    assert Leads.get_lead!(lead.id).status == :contacte

    assert Enum.any?(
             Leads.list_activities(lead),
             &(&1.kind == :statut and &1.metadata["to"] == "contacte")
           )
  end

  test "perdu guard requires a loss_reason; providing one succeeds", %{
    conn: conn,
    admin: admin,
    lead: lead
  } do
    conn =
      conn
      |> AdminAuth.log_in_admin(admin)
      |> AdminAuth.fetch_current_admin([])

    {:ok, lv, _html} = live(conn, ~p"/admin/leads/#{lead.id}")

    # Reveal the loss-reason form by selecting perdu.
    lv
    |> element("[phx-click='transition_status'][phx-value-status='perdu']")
    |> render_click()

    error_html =
      lv
      |> element("form[phx-submit='confirm_loss_reason']")
      |> render_submit(%{"loss_reason" => %{"status" => "perdu", "loss_reason" => ""}})

    assert error_html =~ "A loss reason is required"
    assert Leads.get_lead!(lead.id).status == :nouveau

    html =
      lv
      |> element("form[phx-submit='confirm_loss_reason']")
      |> render_submit(%{
        "loss_reason" => %{"status" => "perdu", "loss_reason" => "Prix trop élevé"}
      })

    assert html =~ "perdu"
    lead = Leads.get_lead!(lead.id)
    assert lead.status == :perdu
    assert lead.loss_reason == "Prix trop élevé"

    assert Enum.any?(
             Leads.list_activities(lead),
             &(&1.kind == :statut and &1.metadata["to"] == "perdu")
           )
  end

  test "callback scheduling persists callback_at and logs an rdv activity", %{
    conn: conn,
    admin: admin,
    lead: lead
  } do
    conn =
      conn
      |> AdminAuth.log_in_admin(admin)
      |> AdminAuth.fetch_current_admin([])

    {:ok, lv, _html} = live(conn, ~p"/admin/leads/#{lead.id}")

    callback_at =
      DateTime.utc_now()
      |> DateTime.add(2, :day)
      |> DateTime.truncate(:second)

    value =
      callback_at
      |> DateTime.to_naive()
      |> NaiveDateTime.to_iso8601()

    html =
      lv
      |> element("form[name='callback_at']")
      |> render_submit(%{"callback_at" => %{"callback_at" => value}})

    assert html =~ "rdv"

    reloaded = Leads.get_lead!(lead.id)
    assert reloaded.callback_at == callback_at

    assert Enum.any?(
             Leads.list_activities(lead),
             &(&1.kind == :rdv and &1.admin_id == admin.id)
           )
  end

  test "unauthenticated access is redirected to the admin login page", %{lead: lead} do
    conn = Phoenix.ConnTest.build_conn()

    assert {:error, {:redirect, %{to: "/admin/login"}}} =
             live(conn, ~p"/admin/leads/#{lead.id}")
  end
end
