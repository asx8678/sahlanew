defmodule SahlaWeb.PageController do
  use SahlaWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
