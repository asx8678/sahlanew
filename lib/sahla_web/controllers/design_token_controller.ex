defmodule SahlaWeb.DesignTokenController do
  use SahlaWeb, :controller

  def index(conn, _params) do
    render(conn, :index)
  end
end
