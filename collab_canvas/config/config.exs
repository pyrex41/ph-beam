# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

# AI Provider Configuration
config :collab_canvas, :ai,
  # Default provider for simple commands (fast path)
  default_provider: CollabCanvas.AI.Providers.Groq,
  
  # Fallback provider if default fails
  fallback_provider: CollabCanvas.AI.Providers.Claude,
  
  # Enable/disable fast path classification
  fast_path_enabled: true,
  
  # API timeouts (milliseconds)
  groq_timeout: 5_000,
  claude_timeout: 10_000,
  
  # Rate limiting
  max_requests_per_minute: 60,
  rate_limit_window_ms: 60_000,
  
  # Circuit breaker configuration
  circuit_breaker_enabled: true,
  circuit_breaker_threshold: 5,  # failures before opening
  circuit_breaker_timeout: 60_000,  # time before retry (ms)
  
  # Health check configuration
  health_check_enabled: true,
  health_check_interval: 300_000,  # 5 minutes
  
  # Validate API keys on startup
  validate_keys_on_startup: true

config :collab_canvas,
  ecto_repos: [CollabCanvas.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :collab_canvas, CollabCanvasWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: CollabCanvasWeb.ErrorHTML, json: CollabCanvasWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: CollabCanvas.PubSub,
  live_view: [signing_salt: "04fK4JjR"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :collab_canvas, CollabCanvas.Mailer, adapter: Swoosh.Adapters.Local

# Configure Vite for better ESM support (recommended for PixiJS v8)
# Note: Vite runs via npm scripts, Phoenix just needs to know about the watcher
# The actual build happens via: npm run build (production) or npm run dev (development)

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.7",
  collab_canvas: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Configure Ueberauth for Auth0
config :ueberauth, Ueberauth,
  providers: [
    auth0: {Ueberauth.Strategy.Auth0, []}
  ]

# Auth0 OAuth configuration is set in runtime.exs

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
