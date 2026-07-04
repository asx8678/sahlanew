defmodule SahlaWeb.SecurityHeadersTest do
  use SahlaWeb.ConnCase, async: true

  describe "response security headers" do
    setup %{conn: conn}, do: %{conn: get(conn, ~p"/")}

    test "sets a strict, LiveView-compatible CSP with a per-request nonce", %{conn: conn} do
      [csp] = get_resp_header(conn, "content-security-policy")

      assert csp =~ "default-src 'self'"
      assert csp =~ "connect-src 'self' ws: wss:"
      assert csp =~ "frame-ancestors 'none'"
      assert [_, nonce] = Regex.run(~r/script-src 'self' 'nonce-([^']+)'/, csp)
      assert nonce != ""
    end

    test "pins frame, referrer and permissions headers", %{conn: conn} do
      assert get_resp_header(conn, "x-frame-options") == ["DENY"]
      assert get_resp_header(conn, "referrer-policy") == ["strict-origin-when-cross-origin"]
      assert [permissions] = get_resp_header(conn, "permissions-policy")
      assert permissions =~ "geolocation=()"
    end

    test "stamps the same nonce on the inline layout script (no unsafe-inline needed)", %{
      conn: conn
    } do
      [csp] = get_resp_header(conn, "content-security-policy")
      [_, nonce] = Regex.run(~r/'nonce-([^']+)'/, csp)

      assert html_response(conn, 200) =~ ~s(nonce="#{nonce}")
    end

    test "the nonce changes per request", %{conn: conn} do
      [csp1] = get_resp_header(conn, "content-security-policy")
      [csp2] = build_conn() |> get(~p"/") |> get_resp_header("content-security-policy")
      refute csp1 == csp2
    end
  end

  describe "session cookie flags" do
    test "the session cookie is HttpOnly and SameSite=Lax" do
      conn = get(build_conn(), ~p"/")
      cookies = get_resp_header(conn, "set-cookie")
      assert Enum.any?(cookies, &(&1 =~ "HttpOnly" and &1 =~ "SameSite=Lax"))
    end
  end

  describe "prod TLS/HSTS config" do
    test "force_ssl uses forwarded-proto rewrite and HSTS >= 1 year; cookies are secure" do
      config = Config.Reader.read!("config/prod.exs", env: :prod)
      ssl = get_in(config, [:sahla, SahlaWeb.Endpoint, :force_ssl])

      assert ssl[:rewrite_on] == [:x_forwarded_proto]
      assert ssl[:hsts] == true
      assert ssl[:expires] >= 31_536_000
      assert get_in(config, [:sahla, :secure_session_cookie]) == true
    end
  end
end
