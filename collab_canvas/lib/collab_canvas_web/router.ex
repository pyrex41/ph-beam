defmodule CollabCanvasWeb.Router do
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
