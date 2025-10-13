# CollabCanvas: Complete Product Requirements Document

**Building Real-Time Collaborative Design Tools with AI**

Version: 1.0
Last Updated: October 2025
Tech Stack: Phoenix LiveView + SQLite + Auth0 + PixiJS + Claude AI

> **Note:** This project initially uses SQLite for simplicity and rapid development. We plan to migrate to Redis/Upstash for production-scale performance in a future iteration.

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [System Architecture](#system-architecture)
3. [Technology Stack](#technology-stack)
4. [Project Timeline](#project-timeline)
5. [MVP Requirements (24 Hours)](#mvp-requirements-24-hours)
6. [Phase 1: Foundation Setup](#phase-1-foundation-setup)
7. [Phase 2: Authentication with Auth0](#phase-2-authentication-with-auth0)
8. [Phase 3: Canvas Core with SQLite](#phase-3-canvas-core-with-sqlite)
9. [Phase 4: Real-Time Collaboration](#phase-4-real-time-collaboration)
10. [Phase 5: PixiJS Canvas Implementation](#phase-5-pixijs-canvas-implementation)
11. [Phase 6: AI Agent with Claude](#phase-6-ai-agent-with-claude)
12. [Phase 7: Deployment to Fly.io](#phase-7-deployment-to-flyio)
13. [Testing Strategy](#testing-strategy)
14. [Performance Targets](#performance-targets)
15. [Conflict Resolution Strategy](#conflict-resolution-strategy)
16. [Security & Best Practices](#security--best-practices)
17. [Submission Requirements](#submission-requirements)
18. [Future: Migration to Redis](#future-migration-to-redis)

---

## Executive Summary

CollabCanvas is a real-time collaborative design tool that combines the power of Phoenix LiveView for real-time synchronization, SQLite for simple and reliable state management, Auth0 for authentication, PixiJS for high-performance WebGL rendering, and Claude AI for natural language canvas manipulation.

### Key Innovation

Users can collaborate in real-time on a shared canvas while an AI agent executes natural language commands like "create a login form" or "arrange these elements in a grid" - all synced instantly across all connected users at 60 FPS.

### Why This Stack?

- **Phoenix LiveView**: Built-in real-time capabilities, minimal JavaScript
- **SQLite**: Zero-configuration, serverless, perfect for MVP and moderate traffic
- **Auth0**: Professional authentication in 15 minutes
- **PixiJS**: WebGL-based rendering, 10,000+ objects at 60 FPS
- **Claude AI**: Function calling for natural language → canvas actions

### Future Enhancement

Once the MVP is proven and scaling requirements are known, we'll migrate from SQLite to Redis/Upstash for:
- Sub-millisecond latency
- Distributed caching
- Higher concurrent user capacity
- Ephemeral cursor/presence data with TTL

---

## System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Browser Client                           │
│  ┌──────────────┐  ┌────────────────┐  ┌──────────────────────┐│
│  │  Alpine.js   │  │  PixiJS        │  │  LiveView Socket     ││
│  │  (UI Layer)  │  │  (WebGL Canvas)│  │  (Real-time)         ││
│  └──────────────┘  └────────────────┘  └──────────────────────┘│
│                              │                                    │
└──────────────────────────────┼────────────────────────────────────┘
                               │ WebSocket (Phoenix Channel)
┌──────────────────────────────┼────────────────────────────────────┐
│                    Phoenix LiveView Server                        │
│  ┌──────────────────────────────────────────────────────────────┐│
│  │                  Canvas LiveView Process                      ││
│  │  • Manages canvas state                                       ││
│  │  • Broadcasts updates via PubSub                              ││
│  │  • Coordinates AI agent                                       ││
│  │  • Enforces authorization                                     ││
│  └──────────────────────────────────────────────────────────────┘│
│           │                    │                    │              │
│  ┌────────────────┐  ┌─────────────────┐  ┌──────────────────┐  │
│  │ Phoenix.PubSub │  │  SQLite (Ecto)  │  │   Claude AI API  │  │
│  │ (Broadcasting) │  │  • Canvas state │  │  • Function call │  │
│  │                │  │  • User data    │  │  • NL→Actions    │  │
│  │                │  │  • Objects      │  │                  │  │
│  └────────────────┘  └─────────────────┘  └──────────────────┘  │
└───────────────────────────────────────────────────────────────────┘
                               │
┌──────────────────────────────┼────────────────────────────────────┐
│                          Auth0                                    │
│  • User authentication                                            │
│  • Social login (Google, GitHub)                                  │
│  • JWT token management                                           │
│  • Session handling                                               │
└───────────────────────────────────────────────────────────────────┘
```

### Data Flow

1. **User Action** → Browser captures interaction (draw, move, AI command)
2. **PixiJS** → Renders locally for instant feedback
3. **LiveView** → Sends event to server via WebSocket
4. **SQLite/Ecto** → Persists state with transaction safety
5. **PubSub** → Broadcasts to all connected users
6. **LiveView** → Pushes update to all clients
7. **PixiJS** → Renders synchronized state at 60 FPS

---

## Technology Stack

### Core Technologies

- **Elixir 1.15+** - Concurrent, fault-tolerant backend
- **Phoenix 1.7+** - Web framework with LiveView
- **Phoenix LiveView 0.20+** - Real-time server-rendered UX
- **Ecto 3.11+** - Database wrapper and query generator
- **SQLite** - Embedded, serverless SQL database
- **Auth0** - Authentication and user management

### Frontend

- **PixiJS 7.x** - WebGL 2D rendering engine (GPU-accelerated)
- **Alpine.js 3.x** - Lightweight reactive UI
- **Tailwind CSS** - Utility-first styling

### AI & APIs

- **Anthropic Claude API** - AI agent with function calling
- **Ueberauth** - OAuth integration framework

### Infrastructure

- **Fly.io** - Deployment platform with persistent volumes for SQLite

### Why SQLite for MVP?

| Feature | SQLite | Redis |
|---------|--------|-------|
| **Setup** | Zero-config ✅ | Requires separate service |
| **Persistence** | Built-in, ACID ✅ | Requires RDB/AOF config |
| **Query Language** | SQL (familiar) ✅ | Custom commands |
| **Relations** | Native support ✅ | Manual implementation |
| **Cost** | Free ✅ | $10-50/month for managed |
| **Scaling** | Good for 100s of users | Better for 1000s+ users |
| **Migration Path** | Easy to Redis later ✅ | - |

---

## Project Timeline

### One-Week Sprint with Three Checkpoints

```
Day 1 (Tuesday)     → MVP Checkpoint (24 hours) - HARD GATE
Days 2-3 (Wed-Thu)  → Core Canvas Features
Days 4-5 (Fri-Sat)  → AI Agent + Early Submission Option
Days 6-7 (Sun)      → Final Polish + Submission
```

### Detailed Breakdown

**Day 1: MVP (24 hours) - CRITICAL**
- Hours 0-2: Phoenix setup + Auth0 integration
- Hours 2-4: SQLite + Ecto setup + basic data model
- Hours 4-8: Canvas with PixiJS + pan/zoom
- Hours 8-12: Real-time sync infrastructure
- Hours 12-16: Multiplayer cursors + presence
- Hours 16-20: Testing + deployment to Fly.io
- Hours 20-24: Bug fixes + MVP demo

**Days 2-3: Canvas Features**
- Multiple shape types (rectangle, circle, text)
- Object transformations (move, resize, rotate)
- Selection (single and multi-select)
- Layer management (z-index)
- Delete and duplicate operations
- Canvas persistence
- Performance optimization (viewport culling)

**Days 4-5: AI Agent**
- AI function calling setup with Claude
- Basic commands (create, move, resize)
- Layout commands (grid, row, spacing)
- Complex commands (login form, nav bar, card)
- AI response streaming
- Multi-step operations

**Days 6-7: Final**
- End-to-end testing with 5+ users
- Performance optimization
- Demo video creation (3-5 minutes)
- Documentation polish
- AI Development Log
- Final submission

---

## MVP Requirements (24 Hours)

### Hard Gates - Must Have All

- ✅ Basic canvas with pan/zoom
- ✅ At least one shape type (rectangle)
- ✅ Ability to create and move objects
- ✅ Real-time sync between 2+ users
- ✅ Multiplayer cursors with name labels
- ✅ Presence awareness (who's online)
- ✅ User authentication (Auth0)
- ✅ Deployed and publicly accessible

### Success Criteria

Test with 2 users in different browsers:

1. **User A creates rectangle** → User B sees it instantly (<100ms)
2. **User A moves rectangle** → User B sees movement in real-time
3. **Both users see each other's cursors** with names and colors
4. **User refreshes browser** → All objects persist
5. **User logs out and back in** → Can resume editing

### What Happens If MVP Fails?

**This is a hard gate.** You cannot proceed to additional features without passing MVP. Focus entirely on:
- Basic shapes working
- Real-time sync functional
- Authentication complete
- Deployment successful

Feature richness does NOT matter if collaboration is broken.

---

## Phase 1: Foundation Setup

### Step 1.1: Create Phoenix Project

```bash
# Install Phoenix if needed
mix archive.install hex phx_new

# Create project WITH Ecto (for SQLite)
mix phx.new collab_canvas --database sqlite3

cd collab_canvas
```

### Step 1.2: Update Dependencies

```elixir
# mix.exs
defmodule CollabCanvas.MixProject do
  use Mix.Project

  def project do
    [
      app: :collab_canvas,
      version: "0.1.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  def application do
    [
      mod: {CollabCanvas.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Phoenix Core
      {:phoenix, "~> 1.7.10"},
      {:phoenix_html, "~> 3.3"},
      {:phoenix_live_reload, "~> 1.4", only: :dev},
      {:phoenix_live_view, "~> 0.20.2"},
      {:floki, ">= 0.30.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.2"},
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.2.0", runtime: Mix.env() == :dev},
      {:telemetry_metrics, "~> 0.6"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.24"},
      {:jason, "~> 1.4"},
      {:dns_cluster, "~> 0.1.1"},
      {:plug_cowboy, "~> 2.5"},

      # Database
      {:phoenix_ecto, "~> 4.4"},
      {:ecto_sql, "~> 3.11"},
      {:ecto_sqlite3, "~> 0.13"},

      # Authentication
      {:ueberauth, "~> 0.10"},
      {:ueberauth_auth0, "~> 2.1"},

      # HTTP Client for AI
      {:req, "~> 0.4"}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind default", "esbuild default"],
      "assets.deploy": ["tailwind default --minify", "esbuild default --minify", "phx.digest"]
    ]
  end
end
```

### Step 1.3: Install Dependencies

```bash
mix deps.get
mix ecto.create
mix assets.setup
```

### Step 1.4: Configure Repo

Phoenix generator should have created this, but verify:

```elixir
# lib/collab_canvas/repo.ex
defmodule CollabCanvas.Repo do
  use Ecto.Repo,
    otp_app: :collab_canvas,
    adapter: Ecto.Adapters.SQLite3
end
```

### Step 1.5: Update Application Supervisor

```elixir
# lib/collab_canvas/application.ex
defmodule CollabCanvas.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      CollabCanvasWeb.Telemetry,
      CollabCanvas.Repo,  # Ecto Repo for SQLite
      {DNSCluster, query: Application.get_env(:collab_canvas, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: CollabCanvas.PubSub},

      # Start the Finch HTTP client for distributed tasks
      {Finch, name: CollabCanvas.Finch},

      # Start Phoenix Presence (CRDT-backed for cursors)
      CollabCanvasWeb.Presence,

      # Start the Endpoint (web server)
      CollabCanvasWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: CollabCanvas.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    CollabCanvasWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
```

### Step 1.6: Configure Phoenix Presence

```elixir
# lib/collab_canvas_web/presence.ex
defmodule CollabCanvasWeb.Presence do
  @moduledoc """
  Provides presence tracking to channels and processes.
  Uses Phoenix.Tracker's built-in CRDT for cursor positions and online users.
  This gives us conflict-free real-time presence across distributed nodes.
  """
  use Phoenix.Presence,
    otp_app: :collab_canvas,
    pubsub_server: CollabCanvas.PubSub
end
```

### Step 1.7: Configure Application

```elixir
# config/config.exs
import Config

# Configure your database
config :collab_canvas, CollabCanvas.Repo,
  database: Path.expand("../collab_canvas_dev.db", Path.dirname(__ENV__.file)),
  pool_size: 5,
  stacktrace: true,
  show_sensitive_data_on_connection_error: true

config :collab_canvas,
  ecto_repos: [CollabCanvas.Repo]

# Configure your endpoint
config :collab_canvas, CollabCanvasWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Phoenix.Endpoint.Cowboy2Adapter,
  render_errors: [
    formats: [html: CollabCanvasWeb.ErrorHTML, json: CollabCanvasWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: CollabCanvas.PubSub,
  live_view: [signing_salt: "SECRET_SIGNING_SALT"]

# Configure esbuild
config :esbuild,
  version: "0.17.11",
  default: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind
config :tailwind,
  version: "3.3.2",
  default: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Import environment specific config
import_config "#{config_env()}.exs"
```

```elixir
# config/dev.exs
import Config

# Configure your database
config :collab_canvas, CollabCanvas.Repo,
  database: Path.expand("../collab_canvas_dev.db", Path.dirname(__ENV__.file)),
  pool_size: 5,
  stacktrace: true,
  show_sensitive_data_on_connection_error: true

# For development, we disable any cache and enable
# debugging and code reloading.
config :collab_canvas, CollabCanvasWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "LOCAL_SECRET_KEY_BASE_GENERATE_WITH_MIX_PHX_GEN_SECRET",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:default, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:default, ~w(--watch)]}
  ]

# Watch static and templates for browser reloading
config :collab_canvas, CollabCanvasWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r"priv/static/.*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"priv/gettext/.*(po)$",
      ~r"lib/collab_canvas_web/(controllers|live|components)/.*(ex|heex)$"
    ]
  ]

# Enable dev routes for dashboard
config :collab_canvas, dev_routes: true

# Do not include metadata nor timestamps in development logs
config :logger, :console, format: "[$level] $message\n"

# Set a higher stacktrace during development
config :phoenix, :stacktrace_depth, 20

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime
```

```elixir
# config/test.exs
import Config

# Configure your database for tests
config :collab_canvas, CollabCanvas.Repo,
  database: Path.expand("../collab_canvas_test.db", Path.dirname(__ENV__.file)),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

# We don't run a server during test
config :collab_canvas, CollabCanvasWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "TEST_SECRET_KEY_BASE",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime
```

```elixir
# config/runtime.exs
import Config

if config_env() == :prod do
  database_path =
    System.get_env("DATABASE_PATH") ||
      raise """
      environment variable DATABASE_PATH is missing.
      For example: /etc/collab_canvas/collab_canvas.db
      """

  config :collab_canvas, CollabCanvas.Repo,
    database: database_path,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "5")

  # Runtime endpoint configuration
  config :collab_canvas, CollabCanvasWeb.Endpoint,
    url: [host: System.get_env("PHX_HOST") || "example.com", port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: String.to_integer(System.get_env("PORT") || "4000")
    ],
    secret_key_base: System.fetch_env!("SECRET_KEY_BASE")
end
```

---

## Phase 2: Authentication with Auth0

### Step 2.1: Auth0 Setup

**Create Auth0 Account:**

1. Go to https://auth0.com/signup
2. Create a free account
3. Create new application: "CollabCanvas"
4. Application Type: "Regular Web Application"
5. Copy: **Domain**, **Client ID**, **Client Secret**

**Configure Auth0 Application Settings:**

```
Application URIs:

Allowed Callback URLs:
http://localhost:4000/auth/auth0/callback
https://collabcanvas.fly.dev/auth/auth0/callback

Allowed Logout URLs:
http://localhost:4000
https://collabcanvas.fly.dev

Allowed Web Origins:
http://localhost:4000
https://collabcanvas.fly.dev

Allowed Origins (CORS):
http://localhost:4000
https://collabcanvas.fly.dev
```

**Enable Social Connections:**

- Go to **Authentication → Social**
- Enable **Google** (uses Auth0 dev keys by default)
- Enable **GitHub** (uses Auth0 dev keys by default)
- Both work immediately with zero configuration!

### Step 2.2: Configure Ueberauth

```elixir
# config/config.exs
import Config

# Add Ueberauth configuration
config :ueberauth, Ueberauth,
  providers: [
    auth0: {Ueberauth.Strategy.Auth0, []}
  ]

config :ueberauth, Ueberauth.Strategy.Auth0.OAuth,
  domain: System.get_env("AUTH0_DOMAIN"),
  client_id: System.get_env("AUTH0_CLIENT_ID"),
  client_secret: System.get_env("AUTH0_CLIENT_SECRET")

# ... rest of config
```

```elixir
# config/runtime.exs (add to existing file)
if config_env() == :prod do
  # Auth0 configuration from environment
  config :ueberauth, Ueberauth.Strategy.Auth0.OAuth,
    domain: System.fetch_env!("AUTH0_DOMAIN"),
    client_id: System.fetch_env!("AUTH0_CLIENT_ID"),
    client_secret: System.fetch_env!("AUTH0_CLIENT_SECRET")

  # ... rest of runtime config
end
```

### Step 2.3: Create User Schema

```bash
mix phx.gen.schema Accounts.User users email:string name:string avatar:string provider:string provider_uid:string last_login:utc_datetime
```

Update the generated migration:

```elixir
# priv/repo/migrations/TIMESTAMP_create_users.exs
defmodule CollabCanvas.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :email, :string, null: false
      add :name, :string
      add :avatar, :string
      add :provider, :string, null: false
      add :provider_uid, :string, null: false
      add :last_login, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:provider, :provider_uid])
    create index(:users, [:email])
  end
end
```

Run migration:
```bash
mix ecto.migrate
```

### Step 2.4: Update User Schema

```elixir
# lib/collab_canvas/accounts/user.ex
defmodule CollabCanvas.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :email, :string
    field :name, :string
    field :avatar, :string
    field :provider, :string
    field :provider_uid, :string
    field :last_login, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :name, :avatar, :provider, :provider_uid, :last_login])
    |> validate_required([:email, :provider, :provider_uid])
    |> unique_constraint([:provider, :provider_uid])
  end
end
```

### Step 2.5: Create Accounts Context

```elixir
# lib/collab_canvas/accounts.ex
defmodule CollabCanvas.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias CollabCanvas.Repo
  alias CollabCanvas.Accounts.User

  @doc """
  Finds or creates a user from OAuth data.
  """
  def find_or_create_user(attrs) do
    case get_user_by_provider(attrs[:provider], attrs[:provider_uid]) do
      nil -> create_user(attrs)
      user ->
        update_last_login(user)
        {:ok, user}
    end
  end

  @doc """
  Creates a user.
  """
  def create_user(attrs \\ %{}) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a user by provider and provider_uid.
  """
  def get_user_by_provider(provider, provider_uid) do
    Repo.get_by(User, provider: provider, provider_uid: provider_uid)
  end

  @doc """
  Gets a single user.
  """
  def get_user!(id), do: Repo.get!(User, id)

  @doc """
  Updates user's last login timestamp.
  """
  def update_last_login(user) do
    user
    |> Ecto.Changeset.change(last_login: DateTime.utc_now())
    |> Repo.update()
  end

  @doc """
  Returns the list of users.
  """
  def list_users do
    Repo.all(User)
  end
end
```

### Step 2.6: Create Auth Controller

```elixir
# lib/collab_canvas_web/controllers/auth_controller.ex
defmodule CollabCanvasWeb.AuthController do
  use CollabCanvasWeb, :controller
  plug Ueberauth

  alias CollabCanvas.Accounts

  def callback(%{assigns: %{ueberauth_failure: fails}} = conn, _params) do
    conn
    |> put_flash(:error, "Failed to authenticate: #{inspect(fails.errors)}")
    |> redirect(to: ~p"/")
  end

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    user_params = %{
      provider_uid: auth.uid,
      email: auth.info.email,
      name: auth.info.name || auth.info.email,
      avatar: auth.info.image,
      provider: to_string(auth.provider),
      last_login: DateTime.utc_now()
    }

    case Accounts.find_or_create_user(user_params) do
      {:ok, user} ->
        conn
        |> put_session(:user_id, user.id)
        |> configure_session(renew: true)
        |> put_flash(:info, "Welcome, #{user.name}!")
        |> redirect(to: ~p"/dashboard")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Error creating account: #{inspect(reason)}")
        |> redirect(to: ~p"/")
    end
  end

  def delete(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> put_flash(:info, "Logged out successfully")
    |> redirect(to: ~p"/")
  end
end
```

### Step 2.7: Create Auth Plug

```elixir
# lib/collab_canvas_web/plugs/auth.ex
defmodule CollabCanvasWeb.Auth do
  @moduledoc """
  Authentication plug for loading current user from session.
  Also provides LiveView mount hooks for authentication.
  """

  import Plug.Conn
  import Phoenix.Controller

  alias CollabCanvas.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    user_id = get_session(conn, :user_id)

    cond do
      # Already assigned (for tests, etc)
      conn.assigns[:current_user] ->
        conn

      # Load user from session
      user_id ->
        case Accounts.get_user!(user_id) do
          user ->
            assign(conn, :current_user, user)
        rescue
          Ecto.NoResultsError ->
            conn
            |> configure_session(drop: true)
            |> assign(:current_user, nil)
        end

      # No user logged in
      true ->
        assign(conn, :current_user, nil)
    end
  end

  @doc """
  Used for routes that require the user to be authenticated.
  """
  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_flash(:error, "You must log in to access this page")
      |> redirect(to: ~p"/")
      |> halt()
    end
  end

  @doc """
  LiveView mount hook for authentication (requires login)
  """
  def on_mount(:default, _params, session, socket) do
    socket = Phoenix.Component.assign_new(socket, :current_user, fn ->
      case session["user_id"] do
        nil -> nil
        user_id ->
          try do
            Accounts.get_user!(user_id)
          rescue
            Ecto.NoResultsError -> nil
          end
      end
    end)

    if socket.assigns.current_user do
      {:cont, socket}
    else
      socket = Phoenix.LiveView.put_flash(socket, :error, "You must log in to access this page")
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/")}
    end
  end

  @doc """
  LiveView mount hook that allows unauthenticated access
  """
  def on_mount(:allow_unauthenticated, _params, session, socket) do
    socket = Phoenix.Component.assign_new(socket, :current_user, fn ->
      case session["user_id"] do
        nil -> nil
        user_id ->
          try do
            Accounts.get_user!(user_id)
          rescue
            Ecto.NoResultsError -> nil
          end
      end
    end)

    {:cont, socket}
  end
end
```

### Step 2.8: Update Router

```elixir
# lib/collab_canvas_web/router.ex
defmodule CollabCanvasWeb.Router do
  use CollabCanvasWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {CollabCanvasWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug CollabCanvasWeb.Auth
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Auth routes (OAuth callbacks)
  scope "/auth", CollabCanvasWeb do
    pipe_through :browser

    get "/:provider", AuthController, :request
    get "/:provider/callback", AuthController, :callback
    post "/:provider/callback", AuthController, :callback
  end

  # Public routes
  scope "/", CollabCanvasWeb do
    pipe_through :browser

    get "/", PageController, :home
    delete "/logout", AuthController, :delete
  end

  # Protected routes (require authentication)
  scope "/", CollabCanvasWeb do
    pipe_through [:browser, :require_authenticated_user]

    live "/dashboard", DashboardLive
    live "/canvas/new", CanvasLive.New
    live "/canvas/:canvas_id", CanvasLive
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:collab_canvas, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: CollabCanvasWeb.Telemetry
    end
  end

  defp require_authenticated_user(conn, _opts) do
    CollabCanvasWeb.Auth.require_authenticated_user(conn, [])
  end
end
```

### Step 2.9: Create Home Page

```elixir
# lib/collab_canvas_web/controllers/page_controller.ex
defmodule CollabCanvasWeb.PageController do
  use CollabCanvasWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end

# lib/collab_canvas_web/controllers/page_html.ex
defmodule CollabCanvasWeb.PageHTML do
  use CollabCanvasWeb, :html

  embed_templates "page_html/*"
end
```

```heex
<!-- lib/collab_canvas_web/controllers/page_html/home.html.heex -->
<div class="min-h-screen flex items-center justify-center bg-gradient-to-br from-indigo-500 via-purple-500 to-pink-500">
  <div class="max-w-md w-full bg-white rounded-lg shadow-2xl p-8">
    <%= if @current_user do %>
      <div class="text-center">
        <img src={@current_user.avatar} alt={@current_user.name} class="w-24 h-24 rounded-full mx-auto mb-4 border-4 border-indigo-200" />
        <h1 class="text-3xl font-bold text-gray-900 mb-2">Welcome back!</h1>
        <p class="text-gray-600 mb-6"><%= @current_user.name %></p>
        <div class="space-y-3">
          <a href="/dashboard" class="block w-full bg-indigo-600 text-white py-3 px-4 rounded-lg hover:bg-indigo-700 transition font-medium">
            Go to Dashboard
          </a>
          <form action="/logout" method="post">
            <input type="hidden" name="_csrf_token" value={Phoenix.HTML.Tag.csrf_token_value()} />
            <button type="submit" class="block w-full bg-gray-200 text-gray-700 py-3 px-4 rounded-lg hover:bg-gray-300 transition font-medium">
              Logout
            </button>
          </form>
        </div>
      </div>
    <% else %>
      <div class="text-center">
        <div class="mb-6">
          <svg class="w-16 h-16 mx-auto text-indigo-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 5a1 1 0 011-1h14a1 1 0 011 1v2a1 1 0 01-1 1H5a1 1 0 01-1-1V5zM4 13a1 1 0 011-1h6a1 1 0 011 1v6a1 1 0 01-1 1H5a1 1 0 01-1-1v-6zM16 13a1 1 0 011-1h2a1 1 0 011 1v6a1 1 0 01-1 1h-2a1 1 0 01-1-1v-6z" />
          </svg>
        </div>
        <h1 class="text-4xl font-bold text-gray-900 mb-2">CollabCanvas</h1>
        <p class="text-gray-600 mb-8">Real-time collaborative design with AI</p>

        <div class="space-y-3">
          <a href="/auth/auth0" class="block w-full bg-indigo-600 text-white py-3 px-4 rounded-lg hover:bg-indigo-700 transition font-medium">
            Sign in with Auth0
          </a>
        </div>

        <div class="mt-8 pt-6 border-t border-gray-200">
          <p class="text-sm text-gray-500">
            ✨ Create beautiful designs together in real-time<br />
            🤖 Let AI do the heavy lifting<br />
            ⚡ Powered by WebGL for blazing performance
          </p>
        </div>
      </div>
    <% end %>
  </div>
</div>
```

### Step 2.10: Environment Variables

Create `.env` file for local development:

```bash
# .env (add to .gitignore!)
export AUTH0_DOMAIN="your-tenant.us.auth0.com"
export AUTH0_CLIENT_ID="your_client_id"
export AUTH0_CLIENT_SECRET="your_client_secret"
export ANTHROPIC_API_KEY="your_claude_api_key"
export SECRET_KEY_BASE="run: mix phx.gen.secret"
```

Load with:
```bash
source .env
mix phx.server
```

---

## Phase 3: Canvas Core with SQLite

### Step 3.1: Generate Canvas Schema

```bash
mix phx.gen.schema Canvases.Canvas canvases name:string owner_id:references:users
mix phx.gen.schema Canvases.Object objects canvas_id:references:canvases type:string x:float y:float width:float height:float rotation:float fill:string stroke:string text:string font_size:integer font_family:string z_index:integer created_by:references:users modified_by:references:users
```

Update migrations:

```elixir
# priv/repo/migrations/TIMESTAMP_create_canvases.exs
defmodule CollabCanvas.Repo.Migrations.CreateCanvases do
  use Ecto.Migration

  def change do
    create table(:canvases) do
      add :name, :string, null: false
      add :owner_id, references(:users, on_delete: :nothing), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:canvases, [:owner_id])
  end
end
```

```elixir
# priv/repo/migrations/TIMESTAMP_create_objects.exs
defmodule CollabCanvas.Repo.Migrations.CreateObjects do
  use Ecto.Migration

  def change do
    create table(:objects) do
      add :canvas_id, references(:canvases, on_delete: :delete_all), null: false
      add :type, :string, null: false
      add :x, :float, default: 0.0
      add :y, :float, default: 0.0
      add :width, :float, default: 100.0
      add :height, :float, default: 100.0
      add :rotation, :float, default: 0.0
      add :fill, :string, default: "#000000"
      add :stroke, :string, default: "#000000"
      add :text, :string
      add :font_size, :integer, default: 16
      add :font_family, :string, default: "Arial"
      add :z_index, :integer, default: 0
      add :created_by, references(:users, on_delete: :nothing)
      add :modified_by, references(:users, on_delete: :nothing)

      timestamps(type: :utc_datetime)
    end

    create index(:objects, [:canvas_id])
    create index(:objects, [:created_by])
    create index(:objects, [:z_index])
  end
end
```

Run migrations:
```bash
mix ecto.migrate
```

### Step 3.2: Update Schemas

```elixir
# lib/collab_canvas/canvases/canvas.ex
defmodule CollabCanvas.Canvases.Canvas do
  use Ecto.Schema
  import Ecto.Changeset

  schema "canvases" do
    field :name, :string
    belongs_to :owner, CollabCanvas.Accounts.User
    has_many :objects, CollabCanvas.Canvases.Object

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(canvas, attrs) do
    canvas
    |> cast(attrs, [:name, :owner_id])
    |> validate_required([:name, :owner_id])
  end
end
```

```elixir
# lib/collab_canvas/canvases/object.ex
defmodule CollabCanvas.Canvases.Object do
  use Ecto.Schema
  import Ecto.Changeset

  schema "objects" do
    field :type, :string
    field :x, :float
    field :y, :float
    field :width, :float
    field :height, :float
    field :rotation, :float
    field :fill, :string
    field :stroke, :string
    field :text, :string
    field :font_size, :integer
    field :font_family, :string
    field :z_index, :integer

    belongs_to :canvas, CollabCanvas.Canvases.Canvas
    belongs_to :creator, CollabCanvas.Accounts.User, foreign_key: :created_by
    belongs_to :modifier, CollabCanvas.Accounts.User, foreign_key: :modified_by

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(object, attrs) do
    object
    |> cast(attrs, [:canvas_id, :type, :x, :y, :width, :height, :rotation,
                    :fill, :stroke, :text, :font_size, :font_family, :z_index,
                    :created_by, :modified_by])
    |> validate_required([:canvas_id, :type])
    |> validate_inclusion(:type, ["rectangle", "circle", "text"])
  end
end
```

### Step 3.3: Create Canvases Context

```elixir
# lib/collab_canvas/canvases.ex
defmodule CollabCanvas.Canvases do
  @moduledoc """
  The Canvases context.
  """

  import Ecto.Query, warn: false
  alias CollabCanvas.Repo
  alias CollabCanvas.Canvases.{Canvas, Object}

  # ============================================
  # Canvas Operations
  # ============================================

  @doc """
  Creates a canvas.
  """
  def create_canvas(attrs \\ %{}, owner_id) do
    %Canvas{}
    |> Canvas.changeset(Map.put(attrs, :owner_id, owner_id))
    |> Repo.insert()
  end

  @doc """
  Gets a single canvas.
  """
  def get_canvas!(id), do: Repo.get!(Canvas, id)

  @doc """
  Returns the list of canvases for a user.
  """
  def list_user_canvases(user_id) do
    Canvas
    |> where([c], c.owner_id == ^user_id)
    |> order_by([c], desc: c.updated_at)
    |> Repo.all()
  end

  @doc """
  Updates a canvas's timestamp.
  """
  def touch_canvas(canvas_id) do
    canvas = get_canvas!(canvas_id)
    canvas
    |> Ecto.Changeset.change(updated_at: DateTime.utc_now())
    |> Repo.update()
  end

  # ============================================
  # Object Operations
  # ============================================

  @doc """
  Creates an object.
  """
  def create_object(attrs \\ %{}) do
    %Object{}
    |> Object.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an object.
  """
  def update_object(object_id, attrs) do
    object = Repo.get!(Object, object_id)
    object
    |> Object.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an object.
  """
  def delete_object(object_id) do
    object = Repo.get!(Object, object_id)
    Repo.delete(object)
  end

  @doc """
  Returns the list of objects for a canvas.
  """
  def list_objects(canvas_id) do
    Object
    |> where([o], o.canvas_id == ^canvas_id)
    |> order_by([o], asc: o.z_index)
    |> Repo.all()
  end

  @doc """
  Gets a single object.
  """
  def get_object!(id), do: Repo.get!(Object, id)
end
```

### Step 3.4: Dashboard LiveView

```elixir
# lib/collab_canvas_web/live/dashboard_live.ex
defmodule CollabCanvasWeb.DashboardLive do
  use CollabCanvasWeb, :live_view

  alias CollabCanvas.Canvases

  on_mount {CollabCanvasWeb.Auth, :default}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    canvases = Canvases.list_user_canvases(user.id)

    {:ok,
     socket
     |> assign(:canvases, canvases)
     |> assign(:show_new_canvas_modal, false)}
  end

  @impl true
  def handle_event("new_canvas", _params, socket) do
    {:noreply, assign(socket, :show_new_canvas_modal, true)}
  end

  @impl true
  def handle_event("cancel_new_canvas", _params, socket) do
    {:noreply, assign(socket, :show_new_canvas_modal, false)}
  end

  @impl true
  def handle_event("create_canvas", %{"name" => name}, socket) do
    user = socket.assigns.current_user

    case Canvases.create_canvas(%{name: name}, user.id) do
      {:ok, canvas} ->
        {:noreply,
         socket
         |> assign(:show_new_canvas_modal, false)
         |> push_navigate(to: ~p"/canvas/#{canvas.id}")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to create canvas")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <!-- Header -->
      <header class="bg-white shadow">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-4">
          <div class="flex justify-between items-center">
            <h1 class="text-2xl font-bold text-gray-900">My Canvases</h1>
            <div class="flex items-center gap-4">
              <button
                phx-click="new_canvas"
                class="bg-indigo-600 text-white px-4 py-2 rounded-lg hover:bg-indigo-700 flex items-center gap-2"
              >
                <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
                </svg>
                New Canvas
              </button>
              <div class="flex items-center gap-2">
                <img src={@current_user.avatar} alt="" class="w-8 h-8 rounded-full" />
                <span class="text-sm text-gray-700"><%= @current_user.name %></span>
              </div>
            </div>
          </div>
        </div>
      </header>

      <!-- Canvas Grid -->
      <main class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <%= if @canvases == [] do %>
          <div class="text-center py-12">
            <svg class="mx-auto h-12 w-12 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 13h6m-3-3v6m5 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
            </svg>
            <h3 class="mt-2 text-sm font-medium text-gray-900">No canvases</h3>
            <p class="mt-1 text-sm text-gray-500">Get started by creating a new canvas.</p>
            <div class="mt-6">
              <button
                phx-click="new_canvas"
                class="bg-indigo-600 text-white px-4 py-2 rounded-lg hover:bg-indigo-700"
              >
                New Canvas
              </button>
            </div>
          </div>
        <% else %>
          <div class="grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-3">
            <%= for canvas <- @canvases do %>
              <a
                href={~p"/canvas/#{canvas.id}"}
                class="block bg-white rounded-lg shadow hover:shadow-lg transition overflow-hidden"
              >
                <div class="aspect-video bg-gradient-to-br from-indigo-100 to-purple-100 flex items-center justify-center">
                  <svg class="h-16 w-16 text-indigo-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 5a1 1 0 011-1h14a1 1 0 011 1v2a1 1 0 01-1 1H5a1 1 0 01-1-1V5zM4 13a1 1 0 011-1h6a1 1 0 011 1v6a1 1 0 01-1 1H5a1 1 0 01-1-1v-6zM16 13a1 1 0 011-1h2a1 1 0 011 1v6a1 1 0 01-1 1h-2a1 1 0 01-1-1v-6z" />
                  </svg>
                </div>
                <div class="p-4">
                  <h3 class="text-lg font-medium text-gray-900"><%= canvas.name %></h3>
                  <p class="text-sm text-gray-500 mt-1">
                    Updated <%= Calendar.strftime(canvas.updated_at, "%b %d, %Y") %>
                  </p>
                </div>
              </a>
            <% end %>
          </div>
        <% end %>
      </main>

      <!-- New Canvas Modal -->
      <%= if @show_new_canvas_modal do %>
        <div class="fixed inset-0 bg-gray-500 bg-opacity-75 flex items-center justify-center z-50">
          <div class="bg-white rounded-lg p-6 max-w-md w-full mx-4">
            <h2 class="text-xl font-bold mb-4">Create New Canvas</h2>
            <form phx-submit="create_canvas">
              <input
                type="text"
                name="name"
                placeholder="Canvas name"
                class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-indigo-500 focus:border-indigo-500"
                required
                autofocus
              />
              <div class="mt-4 flex justify-end gap-2">
                <button
                  type="button"
                  phx-click="cancel_new_canvas"
                  class="px-4 py-2 border border-gray-300 rounded-lg hover:bg-gray-50"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  class="px-4 py-2 bg-indigo-600 text-white rounded-lg hover:bg-indigo-700"
                >
                  Create
                </button>
              </div>
            </form>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
```

---

## Phase 4: Real-Time Collaboration

### Step 4.1: Canvas LiveView

This is the core of real-time collaboration. The LiveView handles:
- Object CRUD operations
- Real-time broadcasting via PubSub
- Presence tracking
- Cursor updates
- AI command processing

```elixir
# lib/collab_canvas_web/live/canvas_live.ex
defmodule CollabCanvasWeb.CanvasLive do
  use CollabCanvasWeb, :live_view

  alias CollabCanvas.Canvases
  alias Phoenix.PubSub

  on_mount {CollabCanvasWeb.Auth, :default}

  @presence_interval 5_000  # Update presence every 5 seconds

  @impl true
  def mount(%{"canvas_id" => canvas_id}, _session, socket) do
    user = socket.assigns.current_user

    # Load canvas
    canvas = Canvases.get_canvas!(canvas_id)

    if connected?(socket) do
      # Subscribe to canvas updates via PubSub
      PubSub.subscribe(CollabCanvas.PubSub, "canvas:#{canvas_id}")

      # Track presence using Phoenix.Tracker (CRDT-backed)
      CollabCanvasWeb.Presence.track(
        self(),
        "canvas:#{canvas_id}",
        user.id,
        %{
          name: user.name,
          avatar: user.avatar,
          color: assign_user_color(user.id),
          online_at: System.system_time(:second)
        }
      )

      # Schedule presence updates
      :timer.send_interval(@presence_interval, :update_presence)
    end

    # Load objects
    objects = Canvases.list_objects(canvas_id)

    # Get initial presence
    presence = CollabCanvasWeb.Presence.list("canvas:#{canvas_id}")

    {:ok,
     socket
     |> assign(:canvas_id, canvas_id)
     |> assign(:canvas, canvas)
     |> assign(:objects, objects)
     |> assign(:present_users, presence)
     |> assign(:ai_processing, false)
     |> assign(:user_color, assign_user_color(user.id))}
  end

  @impl true
  def handle_event("object_created", %{"object" => object_params}, socket) do
    canvas_id = socket.assigns.canvas_id
    user_id = socket.assigns.current_user.id

    object_attrs =
      object_params
      |> Map.put("canvas_id", canvas_id)
      |> Map.put("created_by", user_id)
      |> Map.put("modified_by", user_id)

    case Canvases.create_object(object_attrs) do
      {:ok, object} ->
        # Touch canvas
        Canvases.touch_canvas(canvas_id)

        # Broadcast to all users
        PubSub.broadcast(
          CollabCanvas.PubSub,
          "canvas:#{canvas_id}",
          {:object_created, object}
        )

        {:noreply, socket}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to create object")}
    end
  end

  @impl true
  def handle_event("object_updated", %{"id" => id, "properties" => props}, socket) do
    canvas_id = socket.assigns.canvas_id
    user_id = socket.assigns.current_user.id

    attrs = Map.put(props, "modified_by", user_id)

    case Canvases.update_object(id, attrs) do
      {:ok, object} ->
        # Touch canvas
        Canvases.touch_canvas(canvas_id)

        PubSub.broadcast(
          CollabCanvas.PubSub,
          "canvas:#{canvas_id}",
          {:object_updated, object}
        )

        {:noreply, socket}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("object_deleted", %{"id" => object_id}, socket) do
    canvas_id = socket.assigns.canvas_id

    Canvases.delete_object(object_id)

    # Touch canvas
    Canvases.touch_canvas(canvas_id)

    PubSub.broadcast(
      CollabCanvas.PubSub,
      "canvas:#{canvas_id}",
      {:object_deleted, object_id}
    )

    {:noreply, socket}
  end

  @impl true
  def handle_event("cursor_moved", %{"x" => x, "y" => y}, socket) do
    canvas_id = socket.assigns.canvas_id
    user_id = socket.assigns.current_user.id

    # Broadcast cursor position via PubSub (fast)
    PubSub.broadcast(
      CollabCanvas.PubSub,
      "canvas:#{canvas_id}",
      {:cursor_moved, %{
        user_id: user_id,
        name: socket.assigns.current_user.name,
        color: socket.assigns.user_color,
        x: x,
        y: y
      }}
    )

    {:noreply, socket}
  end

  @impl true
  def handle_event("ai_command", %{"command" => command}, socket) do
    canvas_id = socket.assigns.canvas_id
    user_id = socket.assigns.current_user.id
    objects = Canvases.list_objects(canvas_id)

    # Start AI processing
    socket = assign(socket, :ai_processing, true)

    # Execute AI command asynchronously
    task = Task.async(fn ->
      CollabCanvas.AI.Agent.execute_command(canvas_id, command, objects, user_id)
    end)

    {:noreply, assign(socket, :ai_task, task)}
  end

  # Handle AI command completion
  @impl true
  def handle_info({ref, result}, socket) when is_reference(ref) do
    Process.demonitor(ref, [:flush])

    case result do
      {:ok, _operations} ->
        {:noreply,
         socket
         |> assign(:ai_processing, false)
         |> put_flash(:info, "AI command executed successfully")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:ai_processing, false)
         |> put_flash(:error, "AI command failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_info(:update_presence, socket) do
    # Heartbeat to maintain presence
    {:noreply, socket}
  end

  @impl true
  def handle_info(%{event: "presence_diff"}, socket) do
    presence = CollabCanvasWeb.Presence.list("canvas:#{socket.assigns.canvas_id}")
    {:noreply, assign(socket, :present_users, presence)}
  end

  @impl true
  def handle_info({:object_created, object}, socket) do
    # Skip if it's our own event (already handled optimistically)
    if object.created_by == socket.assigns.current_user.id do
      {:noreply, socket}
    else
      objects = [object | socket.assigns.objects]
      {:noreply, push_event(socket, "object_created", %{object: object}) |> assign(:objects, objects)}
    end
  end

  @impl true
  def handle_info({:object_updated, updated_object}, socket) do
    objects =
      Enum.map(socket.assigns.objects, fn obj ->
        if obj.id == updated_object.id, do: updated_object, else: obj
      end)

    {:noreply, push_event(socket, "object_updated", %{object: updated_object}) |> assign(:objects, objects)}
  end

  @impl true
  def handle_info({:object_deleted, object_id}, socket) do
    objects = Enum.reject(socket.assigns.objects, &(&1.id == object_id))
    {:noreply, push_event(socket, "object_deleted", %{id: object_id}) |> assign(:objects, objects)}
  end

  @impl true
  def handle_info({:cursor_moved, cursor_data}, socket) do
    # Don't send own cursor back
    if cursor_data.user_id != socket.assigns.current_user.id do
      {:noreply, push_event(socket, "cursor_update", cursor_data)}
    else
      {:noreply, socket}
    end
  end

  defp assign_user_color(user_id) do
    colors = ~w(#FF6B6B #4ECDC4 #45B7D1 #FFA07A #98D8C8 #F7DC6F #C39BD3 #85C1E2)
    index = :erlang.phash2(user_id, length(colors))
    Enum.at(colors, index)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="h-screen flex flex-col" id="canvas-container" phx-hook="CanvasManager" data-objects={Jason.encode!(@objects)}>
      <!-- Toolbar -->
      <header class="bg-white border-b border-gray-200 px-4 py-2 flex items-center justify-between">
        <div class="flex items-center gap-4">
          <a href="/dashboard" class="text-gray-600 hover:text-gray-900">
            ← Back
          </a>
          <h1 class="text-lg font-semibold"><%= @canvas.name %></h1>
        </div>

        <!-- Tools -->
        <div class="flex items-center gap-2" x-data="{ selectedTool: 'select' }">
          <button
            @click="selectedTool = 'select'"
            :class="{'bg-indigo-100 text-indigo-700': selectedTool === 'select'}"
            class="px-3 py-2 rounded hover:bg-gray-100"
            data-tool="select"
            title="Select (V)"
          >
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 15l-2 5L9 9l11 4-5 2zm0 0l5 5M7.188 2.239l.777 2.897M5.136 7.965l-2.898-.777M13.95 4.05l-2.122 2.122m-5.657 5.656l-2.12 2.122" />
            </svg>
          </button>
          <button
            @click="selectedTool = 'rectangle'"
            :class="{'bg-indigo-100 text-indigo-700': selectedTool === 'rectangle'}"
            class="px-3 py-2 rounded hover:bg-gray-100"
            data-tool="rectangle"
            title="Rectangle (R)"
          >
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 5a1 1 0 011-1h14a1 1 0 011 1v14a1 1 0 01-1 1H5a1 1 0 01-1-1V5z" />
            </svg>
          </button>
          <button
            @click="selectedTool = 'circle'"
            :class="{'bg-indigo-100 text-indigo-700': selectedTool === 'circle'}"
            class="px-3 py-2 rounded hover:bg-gray-100"
            data-tool="circle"
            title="Circle (C)"
          >
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <circle cx="12" cy="12" r="10" stroke-width="2" />
            </svg>
          </button>
          <button
            @click="selectedTool = 'text'"
            :class="{'bg-indigo-100 text-indigo-700': selectedTool === 'text'}"
            class="px-3 py-2 rounded hover:bg-gray-100"
            data-tool="text"
            title="Text (T)"
          >
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 7h18M3 12h18M3 17h12" />
            </svg>
          </button>

          <div class="border-l border-gray-300 h-6 mx-2"></div>

          <div class="text-sm text-gray-600">
            <kbd class="px-2 py-1 bg-gray-100 rounded text-xs">Space</kbd> + drag to pan
          </div>
          <div class="text-sm text-gray-600">
            Scroll to zoom
          </div>
        </div>

        <!-- Presence -->
        <div class="flex items-center gap-2">
          <%= for {_id, meta} <- @present_users do %>
            <% user_meta = List.first(meta.metas) %>
            <div
              class="flex items-center gap-1 px-2 py-1 rounded-full text-sm"
              style={"background-color: #{user_meta.color}20; color: #{user_meta.color}"}
              title={user_meta.name}
            >
              <div class="w-2 h-2 rounded-full" style={"background-color: #{user_meta.color}"}></div>
              <%= user_meta.name %>
            </div>
          <% end %>
        </div>
      </header>

      <!-- Canvas Container -->
      <div class="flex-1 relative overflow-hidden bg-gray-50">
        <div id="pixi-canvas-container" style="width: 100%; height: 100%;"></div>
      </div>

      <!-- AI Panel -->
      <div class="bg-white border-t border-gray-200 p-4">
        <form phx-submit="ai_command" class="flex gap-2">
          <input
            type="text"
            name="command"
            placeholder="Tell AI what to create... (e.g., 'create a login form at position 200, 200')"
            class="flex-1 px-4 py-2 border border-gray-300 rounded-lg focus:ring-indigo-500 focus:border-indigo-500"
            disabled={@ai_processing}
          />
          <button
            type="submit"
            disabled={@ai_processing}
            class="px-6 py-2 bg-indigo-600 text-white rounded-lg hover:bg-indigo-700 disabled:opacity-50 disabled:cursor-not-allowed flex items-center gap-2"
          >
            <%= if @ai_processing do %>
              <svg class="animate-spin h-5 w-5" fill="none" viewBox="0 0 24 24">
                <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
              </svg>
              Processing...
            <% else %>
              Execute
            <% end %>
          </button>
        </form>
      </div>
    </div>
    """
  end
end
```

**Continue reading the full PRD...**

---

## Future: Migration to Redis

Once the MVP is validated and you need to scale beyond 100s of concurrent users, migrate to Redis for:

### Performance Benefits
- **Sub-millisecond latency** vs SQLite's ~5-10ms
- **Distributed caching** across multiple Fly.io regions
- **TTL-based presence** - cursors expire automatically
- **Atomic operations** - INCR, ZADD for counters/leaderboards

### Migration Strategy

1. **Phase 1**: Add Redis alongside SQLite
   - Use Redis for ephemeral data (cursors, presence)
   - Keep SQLite for persistent data (canvases, objects, users)

2. **Phase 2**: Move hot paths to Redis
   - Canvas object cache (read-through cache)
   - Recent updates buffer

3. **Phase 3**: Full Redis migration
   - Migrate all canvas state to Redis
   - SQLite becomes backup/archive only
   - Use Redis RDB/AOF for persistence

### Code Changes Required

Replace Ecto queries with Redis commands:
- `Repo.all(Object)` → `Redis.command(["SMEMBERS", "canvas:#{id}:objects"])`
- `Repo.insert(object)` → `Redis.pipeline([["HSET"...], ["SADD"...]])`
- Presence already uses CRDT, no changes needed

**Estimated migration time:** 2-4 hours

---

## Summary

This PRD provides a complete blueprint for building CollabCanvas with SQLite for rapid MVP development, with a clear path to Redis when scaling is needed. The architecture remains the same - only the data layer changes.

**Start with SQLite. Scale with Redis when ready.**

