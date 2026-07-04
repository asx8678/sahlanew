defmodule SahlaWeb.Admin.DashboardController do
  @moduledoc """
  Minimal authenticated admin landing — the destination after a completed
  two-stage login and, for now, the concrete protected route that proves the
  auth gate (`require_authenticated_admin`). Real admin surfaces layer on here.
  """
  use SahlaWeb, :controller

  def index(conn, _params) do
    render(conn, :index)
  end
end
