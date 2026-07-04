defmodule SahlaWeb.Plugs.Locale do
  @moduledoc """
  Resolves the request locale (§5.1, §6.3) in this exact order (Lessons):

      path (`/ar`) → cookie → session → `accept-language` header → default `fr`

  It then sets the Gettext and CLDR process locales and assigns `:locale` and
  `:dir` (`ltr`/`rtl`), and persists the resolved locale to the session and a
  long-lived cookie so the choice survives across requests — the language
  switcher writes the same cookie.
  """
  import Plug.Conn

  @behaviour Plug

  @default "fr"
  @supported ~w(fr ar)
  @cookie "locale"
  @cookie_max_age 60 * 60 * 24 * 365

  @doc "The supported locale codes."
  def supported, do: @supported

  @doc "The default locale."
  def default, do: @default

  @doc "Text direction for a locale: rtl for Arabic, ltr otherwise."
  def dir("ar"), do: "rtl"
  def dir(_locale), do: "ltr"

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    conn = fetch_cookies(conn)
    locale = resolve(conn)

    Gettext.put_locale(locale)
    Cldr.put_locale(Sahla.Cldr, locale)

    conn
    |> assign(:locale, locale)
    |> assign(:dir, dir(locale))
    |> persist(locale)
  end

  defp resolve(conn) do
    from_path(conn) ||
      from_cookie(conn) ||
      from_session(conn) ||
      from_header(conn) ||
      @default
  end

  defp from_path(%{path_info: ["ar" | _]}), do: "ar"
  defp from_path(_conn), do: nil

  defp from_cookie(conn), do: supported(conn.cookies[@cookie])

  defp from_session(conn), do: supported(get_session(conn, @cookie))

  defp from_header(conn) do
    conn
    |> get_req_header("accept-language")
    |> List.first()
    |> preferred_from_header()
  end

  # Parses `accept-language` into languages ordered by q-weight and returns the
  # first supported base language, or nil.
  defp preferred_from_header(nil), do: nil

  defp preferred_from_header(header) do
    header
    |> String.split(",")
    |> Enum.map(&parse_language/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(fn {_lang, q} -> q end, :desc)
    |> Enum.find_value(fn {lang, _q} -> supported(lang) end)
  end

  defp parse_language(entry) do
    case entry |> String.trim() |> String.split(";") do
      [""] -> nil
      [tag] -> {base(tag), 1.0}
      [tag | params] -> {base(tag), quality(params)}
    end
  end

  defp base(tag), do: tag |> String.trim() |> String.downcase() |> String.split("-") |> hd()

  defp quality(params) do
    Enum.find_value(params, 1.0, fn param ->
      case param |> String.trim() |> String.split("=") do
        ["q", value] -> parse_q(value)
        _ -> nil
      end
    end)
  end

  defp parse_q(value) do
    case Float.parse(value) do
      {q, _} -> q
      :error -> 1.0
    end
  end

  defp supported(locale) when locale in @supported, do: locale
  defp supported(_locale), do: nil

  defp persist(conn, locale) do
    conn
    |> put_session(@cookie, locale)
    |> put_resp_cookie(@cookie, locale, max_age: @cookie_max_age, same_site: "Lax")
  end
end
