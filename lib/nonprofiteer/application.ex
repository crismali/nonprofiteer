defmodule Nonprofiteer.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      NonprofiteerWeb.Telemetry,
      Nonprofiteer.Repo,
      {DNSCluster, query: Application.get_env(:nonprofiteer, :dns_cluster_query) || :ignore},
      {Oban, Application.fetch_env!(:nonprofiteer, Oban)},
      {Phoenix.PubSub, name: Nonprofiteer.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: Nonprofiteer.Finch},
      # Start a worker by calling: Nonprofiteer.Worker.start_link(arg)
      # {Nonprofiteer.Worker, arg},
      # Start to serve requests, typically the last entry
      NonprofiteerWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Nonprofiteer.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    NonprofiteerWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
