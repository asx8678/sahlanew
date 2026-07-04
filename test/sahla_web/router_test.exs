defmodule SahlaWeb.RouterTest do
  use SahlaWeb.ConnCase, async: true

  test "the browser pipeline emits a strict Content-Security-Policy", %{conn: conn} do
    conn = get(conn, "/")

    assert [csp] = get_resp_header(conn, "content-security-policy")
    assert csp =~ "default-src 'self'"
    assert csp =~ "script-src 'self'"
    assert csp =~ "frame-ancestors 'none'"
  end

  test "the session cookie is HttpOnly and SameSite=Lax", %{conn: conn} do
    conn = get(conn, "/")

    cookie =
      conn
      |> get_resp_header("set-cookie")
      |> Enum.find(&String.starts_with?(&1, "_sahla_key"))

    assert cookie, "expected the home page to set the session cookie"
    assert cookie =~ "HttpOnly"
    assert cookie =~ "SameSite=Lax"
  end

  test "the health probe is reachable without going through the browser pipeline", %{conn: conn} do
    conn = get(conn, "/health")

    # No CSP header: /health is intentionally outside the :browser pipeline.
    assert get_resp_header(conn, "content-security-policy") == []
    assert response(conn, 200) == "ok"
  end
end
