defmodule SahlaWeb.ErrorHTML do
  @moduledoc """
  Branded HTML error pages (§10, Appendix A). Renders friendly 403/404/500
  pages instead of raw Plug fallbacks; the `AdminAuthz` plug also renders its
  403 through here.

  The pages are **self-contained** — inline styles, no dependency on the asset
  build or app layout — so a 500 caused by the pipeline or a broken asset still
  renders cleanly. The brand comes from `Settings.display_name/0` (ETS-backed,
  safe even during a DB outage) rather than a hardcoded string, and copy is
  translated via Gettext. Layout is RTL-safe: direction comes from `dir` and
  spacing uses logical (margin-block/inline) properties.
  """
  use SahlaWeb, :html

  alias Sahla.Settings

  def render("404.html", assigns) do
    page(
      error_assigns(
        assigns,
        404,
        gettext("Page introuvable"),
        gettext("La page que vous cherchez n'existe pas ou a été déplacée.")
      )
    )
  end

  def render("403.html", assigns) do
    page(
      error_assigns(
        assigns,
        403,
        gettext("Accès refusé"),
        gettext("Vous n'avez pas l'autorisation d'accéder à cette page.")
      )
    )
  end

  def render("500.html", assigns) do
    page(
      error_assigns(
        assigns,
        500,
        gettext("Une erreur est survenue"),
        gettext("Un problème est survenu de notre côté. Réessayez dans un instant.")
      )
    )
  end

  # Any other status falls back to the plain status message.
  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end

  # The render/2 assigns arrive as a bare map (no change tracking), so build a
  # plain assigns map rather than piping through `assign/3`.
  defp error_assigns(assigns, status, title, detail) do
    %{
      __changed__: nil,
      status: status,
      title: title,
      detail: detail,
      brand: Settings.display_name(),
      locale: assigns[:locale] || "fr",
      dir: assigns[:dir] || "ltr"
    }
  end

  defp page(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang={@locale} dir={@dir}>
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>{@status} · {@brand}</title>
        <style>
          :root { color-scheme: light dark; }
          body {
            margin: 0;
            min-height: 100vh;
            display: grid;
            place-items: center;
            font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
            background: #0f172a;
            color: #e2e8f0;
          }
          .card { max-width: 32rem; padding: 2.5rem; text-align: center; }
          .status { font-size: 3.5rem; font-weight: 700; margin: 0; color: #38bdf8; }
          .title { font-size: 1.5rem; font-weight: 600; margin: 0.5rem 0 0; }
          .detail { margin: 1rem 0 1.75rem; color: #94a3b8; line-height: 1.6; }
          .home {
            display: inline-block;
            padding: 0.65rem 1.4rem;
            border-radius: 0.5rem;
            background: #38bdf8;
            color: #0f172a;
            font-weight: 600;
            text-decoration: none;
          }
          .brand { margin-block-start: 2rem; font-size: 0.85rem; color: #64748b; }
        </style>
      </head>
      <body>
        <main class="card">
          <p class="status">{@status}</p>
          <h1 class="title">{@title}</h1>
          <p class="detail">{@detail}</p>
          <a class="home" href="/">{gettext("Retour à l'accueil")}</a>
          <p class="brand">{@brand}</p>
        </main>
      </body>
    </html>
    """
  end
end
