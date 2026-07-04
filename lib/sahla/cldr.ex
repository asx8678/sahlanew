defmodule Sahla.Cldr do
  @moduledoc """
  CLDR backend (§6.3) for locale-aware number and date/time formatting, wired to
  the Gettext backend so the two share one locale. Locales mirror the app's:
  French (default) and Arabic.
  """
  use Cldr,
    locales: ["fr", "ar"],
    default_locale: "fr",
    gettext: Sahla.Gettext,
    providers: [Cldr.Number, Cldr.Calendar, Cldr.DateTime],
    otp_app: :sahla
end
