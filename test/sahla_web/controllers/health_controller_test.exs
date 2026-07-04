defmodule SahlaWeb.HealthControllerTest do
  # async: false — the 503 case mutates application env (the injected probe).
  use SahlaWeb.ConnCase, async: false

  test "GET /health returns 200 ok when the database is reachable", %{conn: conn} do
    conn = get(conn, "/health")
    assert response(conn, 200) == "ok"
    assert response_content_type(conn, :text) =~ "text/plain"
  end

  test "GET /health returns 503 when the probe raises", %{conn: conn} do
    Application.put_env(:sahla, :health_probe, fn -> raise "db down" end)
    on_exit(fn -> Application.delete_env(:sahla, :health_probe) end)

    conn = get(conn, "/health")
    assert conn.status == 503
    assert conn.resp_body == "unavailable"
  end
end
