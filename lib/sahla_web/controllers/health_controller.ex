defmodule SahlaWeb.HealthController do
  @moduledoc """
  Liveness/readiness probe at `GET /health` for uptime monitors and the deploy
  rollback gate (§13.5, §13.7). Returns 200 `ok` when the database answers a
  trivial query, 503 otherwise.
  """
  use SahlaWeb, :controller

  def index(conn, _params) do
    {status, body} = if database_ready?(), do: {200, "ok"}, else: {503, "unavailable"}

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(status, body)
  end

  # The probe query is injectable so tests can simulate a database failure
  # without tearing down the real Repo. Any raise is treated as "not ready".
  defp database_ready? do
    probe = Application.get_env(:sahla, :health_probe, &default_probe/0)
    probe.()
    true
  rescue
    _ -> false
  end

  defp default_probe, do: Sahla.Repo.query!("SELECT 1")
end
