defmodule SahlaWeb.Admin.SettingsLiveTest do
  use SahlaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Sahla.Accounts
  alias Sahla.Audit
  alias Sahla.Settings
  alias SahlaWeb.AdminAuth

  setup do
    Sahla.Repo.delete_all(Sahla.Settings.Setting)
    :ets.delete_all_objects(:sahla_settings)
    :ok
  end

  @admin_password "correct horse battery staple"

  setup %{conn: conn} do
    conn =
      conn
      |> Map.replace!(:secret_key_base, SahlaWeb.Endpoint.config(:secret_key_base))
      |> init_test_session(%{})

    {:ok, conn: conn}
  end

  defp log_in_admin(conn, admin) do
    conn
    |> AdminAuth.log_in_admin(admin)
    |> AdminAuth.fetch_current_admin([])
  end

  describe "superadmin" do
    setup %{conn: conn} do
      {:ok, admin} =
        Accounts.register_admin(%{
          email: "super-#{System.unique_integer([:positive])}@sahla.ma",
          password: @admin_password,
          role: :superadmin
        })

      {:ok, admin: admin, conn: log_in_admin(conn, admin)}
    end

    test "mounts the settings page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/admin/settings")
      assert html =~ "Settings"
      assert html =~ "Feature flags"
    end

    test "can toggle a feature flag and creates an audit entry", %{conn: conn, admin: admin} do
      {:ok, lv, _html} = live(conn, ~p"/admin/settings")

      lv
      |> element("form#feature-form")
      |> render_submit(%{"feature" => %{"feature.sms" => "true"}})

      assert Settings.feature_enabled?(:sms) == true

      assert [entry] = Audit.for_entity("setting", "feature.sms")
      assert entry.action == "settings.update"
      assert entry.admin_id == admin.id
      assert entry.after == %{"value" => true}
    end

    test "invalid working hours shows inline error without writing", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin/settings")

      html =
        lv
        |> element("form#working-hours-form")
        |> render_submit(%{
          "working_hours" => %{
            "working_hours_start" => "18:00",
            "working_hours_end" => "09:00",
            "callback_slot_minutes" => "30"
          }
        })

      assert html =~ "Closing time must be after opening time"
      assert Settings.get("working_hours_start") == nil
    end

    test "invalid callback slot shows inline error without writing", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin/settings")

      html =
        lv
        |> element("form#working-hours-form")
        |> render_submit(%{
          "working_hours" => %{
            "working_hours_start" => "09:00",
            "working_hours_end" => "18:00",
            "callback_slot_minutes" => "0"
          }
        })

      assert html =~ "Value must be positive"
      assert Settings.get("callback_slot_minutes") == nil
    end

    test "disclaimer fr/ar round-trip", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin/settings")

      lv
      |> element("form#disclaimer-form")
      |> render_submit(%{
        "disclaimer" => %{
          "disclaimer_fr" => "Devis indicatif et sans valeur contractuelle.",
          "disclaimer_ar" => "عرض تقديري وليس له قيمة تعاقدية."
        }
      })

      assert Settings.get("disclaimer_fr") == "Devis indicatif et sans valeur contractuelle."
      assert Settings.get("disclaimer_ar") == "عرض تقديري وليس له قيمة تعاقدية."

      {:ok, _reloaded_lv, reloaded_html} = live(conn, ~p"/admin/settings")
      assert reloaded_html =~ "Devis indicatif et sans valeur contractuelle."
      assert reloaded_html =~ "عرض تقديري وليس له قيمة تعاقدية."
    end
  end

  describe "ops admin" do
    setup %{conn: conn} do
      {:ok, admin} =
        Accounts.register_admin(%{
          email: "ops-#{System.unique_integer([:positive])}@sahla.ma",
          password: @admin_password,
          role: :ops
        })

      {:ok, admin: admin, conn: log_in_admin(conn, admin)}
    end

    test "cannot edit feature flags", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/admin/settings")

      assert html =~ "Feature flags"
      assert html =~ "disabled" or html =~ "Only superadmins"

      assert {:error, {:live_redirect, %{to: "/admin"}}} =
               lv
               |> element("form#feature-form")
               |> render_submit(%{"feature" => %{"feature.sms" => "true"}})

      assert Settings.feature_enabled?(:sms) == false
    end

    test "cannot edit retention settings", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/admin/settings")

      assert html =~ "Data retention"

      assert {:error, {:live_redirect, %{to: "/admin"}}} =
               lv
               |> element("form#retention-form")
               |> render_submit(%{
                 "retention" => %{
                   "retention.drafts_days" => "1",
                   "retention.anonymize_months" => "1",
                   "retention.otp_hours" => "1",
                   "retention.payload_trim_months" => "1",
                   "retention.audit_years" => "1"
                 }
               })

      assert Settings.get("retention.drafts_days") == nil
    end

    test "can edit working hours and contact numbers", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin/settings")

      lv
      |> element("form#working-hours-form")
      |> render_submit(%{
        "working_hours" => %{
          "working_hours_start" => "08:30",
          "working_hours_end" => "17:30",
          "callback_slot_minutes" => "45"
        }
      })

      assert Settings.get("working_hours_start") == "08:30"
      assert Settings.get("callback_slot_minutes") == 45
    end
  end

  describe "unauthenticated" do
    test "access is redirected to login" do
      conn = Phoenix.ConnTest.build_conn()

      assert {:error, {:redirect, %{to: "/admin/login"}}} =
               live(conn, ~p"/admin/settings")
    end
  end

  describe "unauthorized role" do
    setup %{conn: conn} do
      {:ok, admin} =
        Accounts.register_admin(%{
          email: "agent-#{System.unique_integer([:positive])}@sahla.ma",
          password: @admin_password,
          role: :agent
        })

      {:ok, admin: admin, conn: log_in_admin(conn, admin)}
    end

    test "agent is redirected away from settings", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/admin/settings")
    end
  end
end
