defmodule SahlaWeb.ComponentsControllerTest do
  use SahlaWeb.ConnCase, async: true

  test "GET /design/components renders the component showcase", %{conn: conn} do
    conn = get(conn, ~p"/design/components")
    html = html_response(conn, 200)

    assert html =~ "Core components"
    assert html =~ "Buttons"
    assert html =~ "Cards"
    assert html =~ "Badges"
    assert html =~ "Option cards"
    assert html =~ "Price"
    assert html =~ "Inputs"
  end

  test "GET /ar/design/components renders the Arabic showcase route", %{conn: conn} do
    conn = get(conn, ~p"/ar/design/components")
    assert html_response(conn, 200) =~ "Core components"
  end
end
