defmodule CollabCanvasWeb.Router do
  @moduledoc """
  Defines the application's routing structure and request pipelines.

  ## Overview

  This router configures all HTTP routes and LiveView endpoints for the CollabCanvas
  application, organizing them into logical scopes with appropriate pipeline processing.

  ## Pipelines

  ### Browser Pipeline

  The `:browser` pipeline is used for traditional web requests and LiveView connections.
  It includes:

  - HTML content acceptance
  - Session management (`fetch_session`)
  - LiveView flash message support (`fetch_live_flash`)
  - Root layout configuration
  - CSRF protection (`protect_from_forgery`)
  - Security headers (`put_secure_browser_headers`)

  ### API Pipeline

  The `:api` pipeline is used for JSON API endpoints and includes:

  - JSON content acceptance

  ## Routes

  ### Health Check Route

  - `GET /health` - Health check endpoint (no authentication required)
    - Uses API pipeline for JSON responses
    - Handled by `HealthController.index/2`

  ### Main Application Routes (Browser Pipeline)

  - `GET /` - Home page
    - Handled by `PageController.home/2`

  - `GET /dashboard` - Dashboard LiveView
    - Real-time collaborative canvas management interface
    - Handled by `DashboardLive`

  - `GET /canvas/:id` - Individual canvas LiveView
    - Real-time collaborative drawing interface
    - Handles live object manipulation and multi-user collaboration
    - Handled by `CanvasLive`

  ### Authentication Routes (Browser Pipeline)

  OAuth authentication flow using Ueberauth:

  - `GET /auth/logout` - User logout
  - `GET /auth/:provider` - Initiate OAuth flow with provider
  - `GET /auth/:provider/callback` - OAuth callback handler
  - `POST /auth/:provider/callback` - OAuth callback handler (POST variant)

  Supported providers are configured via Ueberauth in the application config.

  ### Development Routes

  When `:dev_routes` is enabled in configuration (development environment):

  - `GET /dev/dashboard` - Phoenix LiveDashboard for monitoring
  - `/dev/mailbox` - Swoosh email preview interface

  **Note:** These routes should be properly secured before enabling in production.

  ## Security Considerations

  - All browser routes include CSRF protection via `:protect_from_forgery`
  - LiveDashboard and development tools are conditionally compiled based on environment
  - Health check endpoint bypasses authentication for monitoring purposes
  - OAuth callbacks support both GET and POST methods for provider compatibility
  """
  use CollabCanvasWeb, :router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {CollabCanvasWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  # API endpoints (no auth required)
  scope "/api", CollabCanvasWeb do
    pipe_through(:api)
    post("/transcribe", WhisperController, :transcribe)
  end

  # Health check endpoint (no auth required)
  scope "/", CollabCanvasWeb do
    pipe_through(:api)
    get("/health", HealthController, :index)
  end

  scope "/", CollabCanvasWeb do
    pipe_through(:browser)

    get("/", PageController, :home)
    live("/dashboard", DashboardLive)
    live("/canvas/:id", CanvasLive)
  end

  # Auth routes
  scope "/auth", CollabCanvasWeb do
    pipe_through(:browser)

    get("/logout", AuthController, :logout)
    get("/:provider", AuthController, :request)
    get("/:provider/callback", AuthController, :callback)
    post("/:provider/callback", AuthController, :callback)
  end

  # Other scopes may use custom stacks.

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:collab_canvas, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through(:browser)

      live_dashboard("/dashboard", metrics: CollabCanvasWeb.Telemetry)
      forward("/mailbox", Plug.Swoosh.MailboxPreview)
    end
  end
end
