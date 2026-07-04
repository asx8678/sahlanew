import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/sahla start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :sahla, SahlaWeb.Endpoint, server: true
end

config :sahla, SahlaWeb.Endpoint, http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() in [:dev, :test] do
  # Deliberately NON-SECRET deterministic keys: dev data stays decryptable
  # across restarts and tests are reproducible. Real keys exist only in the
  # production environment (CLOAK_KEY / HMAC_KEY, below).
  config :sahla, Sahla.Vault,
    ciphers: [
      default:
        {Cloak.Ciphers.AES.GCM,
         tag: "AES.GCM.V1",
         key: :crypto.hash(:sha256, "sahla-#{config_env()}-cloak-key-not-a-secret"),
         iv_length: 12}
    ]

  config :sahla, Sahla.Hashed.HMAC,
    algorithm: :sha256,
    secret: "sahla-#{config_env()}-hmac-key-not-a-secret"
end

if config_env() == :prod do
  # Fail fast: every required secret must be present in the environment
  # (/etc/sahla/app.env in production), with an error that names the
  # variable and shows an example value.
  required! = fn var, example ->
    System.get_env(var) ||
      raise """
      environment variable #{var} is missing.
      Example: #{var}=#{example}
      Production reads it from /etc/sahla/app.env (see ops/).
      """
  end

  database_url = required!.("DATABASE_URL", "ecto://sahla:pass@127.0.0.1/sahla_prod")

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :sahla, Sahla.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "15"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod, provided via the environment.
  secret_key_base = required!.("SECRET_KEY_BASE", "$(mix phx.gen.secret)")

  host = required!.("PHX_HOST", "example.ma")

  # PII encryption at rest (Law 09-08 / §12): AES-GCM-256 vault key plus a
  # SEPARATE keyed-HMAC lookup key. Both are required in prod — the app
  # refuses to boot without them.
  cloak_key =
    case Base.decode64(required!.("CLOAK_KEY", "$(openssl rand -base64 32)")) do
      {:ok, key} when byte_size(key) == 32 ->
        key

      _ ->
        raise """
        CLOAK_KEY must be a base64-encoded 32-byte AES key.
        Generate one with: openssl rand -base64 32
        """
    end

  hmac_key = required!.("HMAC_KEY", "$(openssl rand -base64 32)")

  # To rotate the vault key, add the new key as :default with a new tag and
  # keep the old cipher listed until re-encryption completes — see
  # docs/security/key-rotation.md.
  config :sahla, Sahla.Vault,
    ciphers: [
      default: {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V1", key: cloak_key, iv_length: 12}
    ]

  config :sahla, Sahla.Hashed.HMAC, algorithm: :sha256, secret: hmac_key

  config :sahla, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  # Integration settings (Appendix B). All optional at boot: integrations
  # default to their Fake adapter / disabled state until both the secret is
  # present AND the matching settings feature flag is enabled (Lessons —
  # external-provider pattern). Consuming tasks read these config keys.
  config :sahla, :sms,
    provider: System.get_env("SMS_PROVIDER", "fake"),
    api_key: System.get_env("SMS_API_KEY"),
    sender: System.get_env("SMS_SENDER")

  config :sahla, :postmark_api_key, System.get_env("POSTMARK_API_KEY")

  config :sahla, :turnstile,
    site_key: System.get_env("TURNSTILE_SITE_KEY"),
    secret: System.get_env("TURNSTILE_SECRET")

  config :sahla, :uploads_dir, System.get_env("UPLOADS_DIR", "/opt/sahla/shared/uploads")

  config :sahla, :sentry_dsn, System.get_env("SENTRY_DSN")

  config :sahla, :plausible_domain, System.get_env("PLAUSIBLE_DOMAIN")

  config :sahla, SahlaWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :sahla, SahlaWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :sahla, SahlaWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # Mailer (§11). Postmark over Req (api_client set in config/prod.exs — no
  # hackney) when POSTMARK_API_KEY is present; otherwise the Local adapter, so a
  # prod boot without the secret still runs and previews mail rather than
  # crashing (external-provider pattern — live only when the secret exists).
  # SPF/DKIM/DMARC setup: see ops/email-deliverability.md.
  if postmark_key = System.get_env("POSTMARK_API_KEY") do
    config :sahla, Sahla.Mailer,
      adapter: Swoosh.Adapters.Postmark,
      api_key: postmark_key
  end

  # Sender identity, overridable without a redeploy (falls back to config.exs).
  if from_email = System.get_env("MAIL_FROM_EMAIL") do
    config :sahla, :mail_from, {System.get_env("MAIL_FROM_NAME", "Sahla"), from_email}
  end
end
