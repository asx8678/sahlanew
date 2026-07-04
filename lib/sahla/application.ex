defmodule Sahla.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      SahlaWeb.Telemetry,
      # The vault must be running before anything dumps/loads encrypted fields.
      Sahla.Vault,
      Sahla.Repo,
      {DNSCluster, query: Application.get_env(:sahla, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Sahla.PubSub},
      # ETS cache of runtime settings (subscribes to PubSub for cross-node invalidation).
      Sahla.Settings.Cache,
      # ETS cache of published rate tables (subscribes to PubSub for invalidation).
      Sahla.Rating.TableCache,
      # Records SMS sends for the Fake adapter (dev/test); inert in prod when a
      # live provider is configured.
      Sahla.Notifications.SMSProvider.Fake,
      # ETS-backed rate-limit buckets (anti-abuse/anti-pump).
      {Sahla.Notifications.RateLimit, clean_period: :timer.minutes(10)},
      # Background jobs (§7.3). Inline in test (see config/test.exs) so runs are
      # deterministic; base convention lives in `Sahla.Worker`.
      {Oban, Application.fetch_env!(:sahla, Oban)},
      # Start to serve requests, typically the last entry
      SahlaWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Sahla.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    SahlaWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
