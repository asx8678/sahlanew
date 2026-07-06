defmodule SahlaWeb.LocaleControllerTest do
  # async: false — asserts the global locale cookie drives the locale plug on a
  # second request; cookie state is process-global within the test endpoint.
  use SahlaWeb.ConnCase, async: false

  alias SahlaWeb.Plugs.Locale

  describe "GET /locale/:locale" do
    test "sets the locale cookie and redirects to the mirror path (fr → ar)", %{conn: conn} do
      conn = get(conn, "/locale/ar?redirect=/devis/abc-123")

      assert redirected_to(conn) == "/ar/devis/abc-123"
      assert conn.resp_cookies["locale"].value == "ar"
      assert conn.resp_cookies["locale"].max_age == Locale.cookie_max_age()
    end

    test "preserves a /devis/:token across the switch (ar → fr)", %{conn: conn} do
      conn = get(conn, "/locale/fr?redirect=/ar/devis/abc-123")
      assert redirected_to(conn) == "/devis/abc-123"
      assert conn.resp_cookies["locale"].value == "fr"
    end

    test "preserves an /offres/:token across the switch (fr → ar)", %{conn: conn} do
      conn = get(conn, "/locale/ar?redirect=/offres/xyz-789")
      assert redirected_to(conn) == "/ar/offres/xyz-789"
    end

    test "preserves the query string across the switch", %{conn: conn} do
      conn = get(conn, "/locale/ar?redirect=/devis/abc-123?step=2")
      assert redirected_to(conn) == "/ar/devis/abc-123?step=2"
    end

    test "falls back to the target-locale home when no redirect is supplied", %{conn: conn} do
      assert redirected_to(get(conn, "/locale/ar")) == "/ar"
      assert redirected_to(get(conn, "/locale/fr")) == "/"
    end

    test "the written cookie drives the locale plug on a subsequent request" do
      # A request that switched to Arabic wrote the `locale=ar` cookie; replay
      # it on a fresh request to a non-/ar route. The path can't decide the
      # locale, so the plug must resolve `ar` from the cookie and flip dir to rtl.
      conn =
        build_conn()
        |> put_req_cookie("locale", "ar")
        |> get("/assureurs")

      assert conn.assigns.locale == "ar"
      assert conn.assigns.dir == "rtl"
    end

    test "resolving fr from the cookie yields ltr direction" do
      conn =
        build_conn()
        |> put_req_cookie("locale", "fr")
        |> get("/devis/abc-123")

      assert conn.assigns.locale == "fr"
      assert conn.assigns.dir == "ltr"
    end
  end
end
