defmodule SahlaWeb.LocaleHook do
  @moduledoc """
  `on_mount` hook (§6.3) that gives every LiveView in a `live_session` its locale
  without per-view code. It reads the locale the `SahlaWeb.Plugs.Locale` plug
  persisted to the session, sets the Gettext and CLDR process locales for the
  LiveView process, and assigns `:locale` and `:dir` for the layout.
  """
  import Phoenix.Component, only: [assign: 2]

  alias SahlaWeb.Plugs.Locale

  def on_mount(:default, _params, session, socket) do
    locale = resolve(session)

    Gettext.put_locale(locale)
    Cldr.put_locale(Sahla.Cldr, locale)

    {:cont, assign(socket, locale: locale, dir: Locale.dir(locale))}
  end

  defp resolve(session) do
    case session["locale"] do
      locale when locale in ["fr", "ar"] -> locale
      _ -> Locale.default()
    end
  end
end
