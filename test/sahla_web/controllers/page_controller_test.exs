defmodule SahlaWeb.PageControllerTest do
  use SahlaWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Peace of mind from prototype to production"
  end

  test "GET / renders French with ltr direction", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)
    assert html =~ ~s(lang="fr")
    assert html =~ ~s(dir="ltr")
  end

  test "GET /ar mirrors the page in Arabic with rtl direction", %{conn: conn} do
    html = conn |> get(~p"/ar") |> html_response(200)
    assert html =~ ~s(lang="ar")
    assert html =~ ~s(dir="rtl")
  end
end
