defmodule CollabCanvas.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      CollabCanvasWeb.Telemetry,
      CollabCanvas.Repo,
      {Ecto.Migrator,
       repos: Application.fetch_env!(:collab_canvas, :ecto_repos), skip: skip_migrations?()},
      {DNSCluster, query: Application.get_env(:collab_canvas, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: CollabCanvas.PubSub},
      # Start the Presence system for tracking online users and cursors
      CollabCanvasWeb.Presence,
      # Start a worker by calling: CollabCanvas.Worker.start_link(arg)
      # {CollabCanvas.Worker, arg},
      # Start to serve requests, typically the last entry
      CollabCanvasWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: CollabCanvas.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    CollabCanvasWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations?() do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
  end
end
