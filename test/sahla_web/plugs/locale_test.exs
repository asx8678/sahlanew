defmodule SahlaWeb.Plugs.LocaleTest do
  use ExUnit.Case, async: true

  import Plug.Test
  import Plug.Conn

  alias SahlaWeb.Plugs.Locale

  defp run(conn), do: Locale.call(conn, Locale.init([]))

  defp build(path, opts \\ []) do
    conn(:get, path)
    |> init_test_session(Keyword.get(opts, :session, %{}))
    |> maybe_cookie(opts[:cookie])
    |> maybe_header(opts[:accept_language])
  end

  defp maybe_cookie(conn, nil), do: conn
  defp maybe_cookie(conn, value), do: put_req_cookie(conn, "locale", value)

  defp maybe_header(conn, nil), do: conn
  defp maybe_header(conn, value), do: put_req_header(conn, "accept-language", value)

  describe "resolution order: path → cookie → session → accept-language → default" do
    test "the /ar path wins over every other signal" do
      conn =
        run(build("/ar", cookie: "fr", session: %{"locale" => "fr"}, accept_language: "fr"))

      assert conn.assigns.locale == "ar"
      assert conn.assigns.dir == "rtl"
    end

    test "the cookie wins when the path is not /ar" do
      conn = run(build("/", cookie: "ar", session: %{"locale" => "fr"}, accept_language: "fr"))
      assert conn.assigns.locale == "ar"
    end

    test "the session wins when there is no path and no cookie" do
      conn = run(build("/", session: %{"locale" => "ar"}, accept_language: "fr"))
      assert conn.assigns.locale == "ar"
    end

    test "the accept-language header is used when nothing else matches" do
      conn = run(build("/", accept_language: "ar"))
      assert conn.assigns.locale == "ar"
    end

    test "defaults to fr when there is no signal at all" do
      conn = run(build("/"))
      assert conn.assigns.locale == "fr"
      assert conn.assigns.dir == "ltr"
    end
  end

  describe "accept-language parsing" do
    test "respects q-weights, picking the highest supported language" do
      assert run(build("/", accept_language: "fr;q=0.5, ar;q=0.9")).assigns.locale == "ar"
    end

    test "reads a region-tagged Arabic (ar-MA) as ar" do
      assert run(build("/", accept_language: "ar-MA,ar;q=0.9,en;q=0.8")).assigns.locale == "ar"
    end

    test "an unknown language falls back to the default fr" do
      assert run(build("/", accept_language: "es-ES,es;q=0.9")).assigns.locale == "fr"
    end

    test "picks fr over an unsupported higher-priority language" do
      assert run(build("/", accept_language: "en-US,en;q=0.9,fr;q=0.8")).assigns.locale == "fr"
    end
  end

  describe "path matching is exact" do
    test "a path merely starting with 'ar' does not trigger Arabic" do
      assert run(build("/arabica")).assigns.locale == "fr"
    end
  end

  describe "side effects" do
    test "sets the Gettext process locale" do
      run(build("/ar"))
      assert Gettext.get_locale() == "ar"
    end

    test "persists the resolved locale to the session and a cookie" do
      conn = run(build("/ar"))
      assert get_session(conn, "locale") == "ar"
      assert conn.resp_cookies["locale"].value == "ar"
    end

    test "an invalid cookie value is ignored" do
      conn = run(build("/", cookie: "zz", accept_language: "ar"))
      assert conn.assigns.locale == "ar"
    end
  end

  describe "dir/1" do
    test "Arabic is rtl, everything else ltr" do
      assert Locale.dir("ar") == "rtl"
      assert Locale.dir("fr") == "ltr"
    end
  end
end
