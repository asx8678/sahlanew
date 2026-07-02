defmodule Sahla.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      SahlaWeb.Telemetry,
      Sahla.Repo,
      {DNSCluster, query: Application.get_env(:sahla, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Sahla.PubSub},
      # Start a worker by calling: Sahla.Worker.start_link(arg)
      # {Sahla.Worker, arg},
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
