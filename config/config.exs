# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :sahla,
  ecto_repos: [Sahla.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

# Repo-wide migration defaults: uuid (binary_id) primary/foreign keys and
# utc_datetime timestamps so every generated migration follows the shared
# schema conventions (§8) without per-migration boilerplate.
config :sahla, Sahla.Repo,
  migration_primary_key: [name: :id, type: :binary_id],
  migration_foreign_key: [type: :binary_id],
  migration_timestamps: [type: :utc_datetime]

# Background jobs (§7.3, §12). Oban replaces system cron for app schedules.
# Only queues + the Cron scheduler home are defined here; concrete cron entries
# (abandon +2h/+24h, retention purges) are attached by their owning domains.
config :sahla, Oban,
  repo: Sahla.Repo,
  queues: [sms: 10, email: 10, followups: 20, imports: 5, maintenance: 5],
  plugins: [{Oban.Plugins.Cron, crontab: []}]

# Configure the endpoint
config :sahla, SahlaWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: SahlaWeb.ErrorHTML, json: SahlaWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Sahla.PubSub,
  live_view: [signing_salt: "g1eqhlFQ"]

# SMS kill-switch (§11): when false, Notifications.SMS.send/3 short-circuits to
# {:error, :disabled}. Flipped at runtime by the budget/settings system. The
# provider defaults to the Fake adapter until a live one is configured.
config :sahla, :sms_enabled, true

# Email kill-switch (§11): when false, Notifications.Email.deliver/1
# short-circuits to {:error, :disabled}, so a budget alarm or incident can halt
# all transactional email at runtime — mirrors the SMS kill-switch.
config :sahla, :email_enabled, true

# Default From: for transactional email (§11). Overridable at runtime via
# MAIL_FROM_* env; the display name still resolves the brand separately.
config :sahla, :mail_from, {"Sahla", "no-reply@sahla.ma"}

# Brand display name (§5.3, §11): resolved by the notification/template layer so
# no message hardcodes it. Overridable at runtime via settings/admin-studio.
config :sahla, :brand_name, "Sahla"

# Private upload storage (§12): outside priv/static, served by an authenticated
# controller. Defaults to a system temp directory; production overrides via
# runtime.exs / UPLOADS_DIR.
config :sahla, :uploads_dir,
       System.get_env("UPLOADS_DIR", Path.join([System.tmp_dir!(), "sahla_uploads"]))

# i18n: French is the default UI language; Arabic is the second locale (§6.3).
# msgids are English dev-keys; catalogs live in priv/gettext/{fr,ar}.
config :sahla, Sahla.Gettext,
  default_locale: "fr",
  allowed_locales: ~w(fr ar)

# CLDR (number/date formatting) shares the Gettext locale; Sahla.Cldr is the
# default backend so `Cldr.put_locale/1` and formatters resolve without args.
config :ex_cldr, default_backend: Sahla.Cldr

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :sahla, Sahla.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  sahla: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  sahla: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
