defmodule SahlaWeb.ErrorHTMLTest do
  use SahlaWeb.ConnCase, async: true

  # Bring render_to_string/4 for testing custom views
  import Phoenix.Template, only: [render_to_string: 4]

  defp render(status), do: render_to_string(SahlaWeb.ErrorHTML, status, "html", [])

  test "renders a branded 404 page (not a stack trace)" do
    html = render("404")
    assert html =~ "404"
    assert html =~ "Page introuvable"
    assert html =~ "accueil"
    # Brand pulled from Settings/config, never hardcoded.
    assert html =~ "Sahla"
  end

  test "renders a branded 500 page" do
    html = render("500")
    assert html =~ "500"
    assert html =~ "Une erreur est survenue"
  end

  test "renders a branded 403 page (used by the authz plug)" do
    html = render("403")
    assert html =~ "403"
    assert html =~ "Accès refusé"
  end

  test "falls back to the plain status message for other codes" do
    assert render("418") =~ "teapot"
  end

  test "an unknown route renders the branded 404 template through the endpoint" do
    conn = get(build_conn(), "/no-such-route-#{System.unique_integer([:positive])}")
    assert conn.status == 404
    assert conn.resp_body =~ "Page introuvable"
  end
end
