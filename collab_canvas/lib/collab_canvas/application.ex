defmodule CollabCanvas.Application do
  @moduledoc """
  The CollabCanvas OTP Application.

  This module defines the root of the CollabCanvas application supervision tree and manages
  the application lifecycle. It implements the `Application` behavior and is responsible for
  starting all core services required for the collaborative canvas platform.

  ## Supervision Tree

  The application uses a `:one_for_one` supervision strategy, meaning if a child process
  crashes, only that specific process is restarted. The supervision tree includes the following
  child processes in order:

  1. **Telemetry** (`CollabCanvasWeb.Telemetry`) - Metrics and monitoring system for tracking
     application performance and behavior.

  2. **Repo** (`CollabCanvas.Repo`) - Ecto repository providing database access and query
     capabilities for persistent storage.

  3. **Migrator** (`Ecto.Migrator`) - Handles automatic database migrations on application
     startup. Skips migrations in development mode (see `skip_migrations?/0`).

  4. **DNS Cluster** (`DNSCluster`) - Manages node discovery and clustering in distributed
     deployments. Configured via `:dns_cluster_query` application environment.

  5. **PubSub** (`Phoenix.PubSub`) - Publisher-subscriber system enabling real-time message
     broadcasting across the application and distributed nodes.

  6. **Presence** (`CollabCanvasWeb.Presence`) - Phoenix Presence tracking system for monitoring
     online users, cursor positions, and collaborative state across connected clients.

  7. **Endpoint** (`CollabCanvasWeb.Endpoint`) - Phoenix HTTP/WebSocket endpoint serving web
     requests and managing real-time connections. Started last to ensure all dependencies are
     available before accepting traffic.

  ## Application Startup

  The application starts automatically when the Elixir runtime launches. The `start/2` callback
  initializes the supervision tree and returns `{:ok, pid}` on success. If any critical child
  process fails to start, the entire application startup fails.

  ## Configuration

  Key application environment variables:
  - `:ecto_repos` - List of Ecto repositories to manage
  - `:dns_cluster_query` - DNS query for node discovery in clustered deployments
  - `RELEASE_NAME` - Environment variable controlling migration behavior

  See the [OTP Application documentation](https://hexdocs.pm/elixir/Application.html) for more
  information on OTP Applications.
  """

  use Application

  @impl true
  @doc """
  Starts the CollabCanvas application and its supervision tree.

  This callback is invoked when the application is started. It creates a supervisor with all
  required child processes and returns the supervisor pid.

  ## Parameters

  - `type` - The application start type (`:normal`, `:takeover`, or `:failover`). Typically
    `:normal` for standard application startup.
  - `args` - Application start arguments. Not currently used by CollabCanvas.

  ## Returns

  - `{:ok, pid}` - Successfully started the supervision tree
  - `{:error, reason}` - Failed to start the application

  ## Examples

      # Called automatically by the Elixir runtime:
      {:ok, pid} = CollabCanvas.Application.start(:normal, [])

  """
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
