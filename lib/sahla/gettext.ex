defmodule Sahla.Gettext do
  @moduledoc """
  Gettext backend for all translatable copy — web UI, SMS/WhatsApp templates,
  emails (§6.3).

  Conventions:

    * Locales are `fr` (default) and `ar`; configured in `config.exs`.
    * **msgids are English dev-keys** — e.g. `gettext("Compare")` — so catalogs
      stay stable and reviewable. French and Arabic are authored in the
      catalogs under `priv/gettext/{fr,ar}/LC_MESSAGES/`.
    * The `errors` domain is separate from `default` so Ecto changeset
      messages translate independently of UI copy.

  Use it via:

      use Gettext, backend: Sahla.Gettext

  Run `mix gettext.update` to extract new msgids and merge them into the
  fr/ar catalogs.
  """
  use Gettext.Backend, otp_app: :sahla
end
