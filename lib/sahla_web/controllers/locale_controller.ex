defmodule SahlaWeb.LocaleController do
  @moduledoc """
  Language switch endpoint (§6.3). `GET /locale/:locale?redirect=<path>` sets
  the `locale` cookie the `SahlaWeb.Plugs.Locale` plug reads, then redirects to
  the mirror of `redirect` in the target locale so the funnel/offers token (and
  every other path segment) is preserved across the switch.
  """
  use SahlaWeb, :controller

  import Plug.Conn

  alias SahlaWeb.LocaleMirror
  alias SahlaWeb.Plugs.Locale

  @cookie Locale.cookie_key()
  @max_age Locale.cookie_max_age()

  @doc """
  Sets the `locale` cookie and redirects to the mirror of the caller's path in
  `target_locale`. Falls back to the home route in the target locale when no
  safe `redirect` is supplied.
  """
  def switch(conn, %{"locale" => target_locale, "redirect" => redirect})
      when target_locale in ~w(fr ar) and is_binary(redirect) do
    conn
    |> put_resp_cookie(@cookie, target_locale, max_age: @max_age, same_site: "Lax")
    |> redirect(to: LocaleMirror.to(redirect, target_locale))
  end

  def switch(conn, %{"locale" => target_locale}) when target_locale in ~w(fr ar) do
    home = if target_locale == "ar", do: "/ar", else: "/"
    redirect(conn, to: home)
  end
end
