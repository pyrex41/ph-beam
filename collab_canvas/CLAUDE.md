# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

CollabCanvas is a real-time collaborative canvas application built with Phoenix LiveView and PixiJS. Think Figma-lite: multiple users can simultaneously create, edit, and manipulate shapes, text, and UI components on a shared canvas with real-time synchronization.

**Tech Stack:**
- **Backend:** Elixir 1.15+, Phoenix 1.8, Phoenix LiveView 1.1
- **Database:** SQLite (via Ecto 3.13)
- **Frontend:** JavaScript (ES6+), PixiJS v8 (WebGL canvas rendering)
- **Build:** Vite (ESM bundler), Tailwind CSS 4.1.7
- **Auth:** Auth0 via Ueberauth
- **Real-time:** Phoenix PubSub (multi-user sync), Phoenix Presence (cursor tracking)
- **AI:** Claude 3.5 Sonnet API (natural language canvas commands)

## Development Commands

```bash
# Initial setup (install deps, create DB, compile assets)
mix setup

# Start development server (http://localhost:4000)
mix phx.server

# Interactive Elixir shell with app loaded
iex -S mix phx.server

# Database operations
mix ecto.create           # Create database
mix ecto.migrate          # Run migrations
mix ecto.reset            # Drop, create, migrate, seed
mix ecto.rollback         # Rollback last migration

# Testing
mix test                  # Run all tests
mix test test/path/to/file_test.exs          # Single file
mix test test/path/to/file_test.exs:42       # Single test at line 42

# Code quality (pre-commit workflow)
mix precommit             # Compile with warnings-as-errors, format, test

# Asset management
npm install --prefix assets              # Install JS dependencies
npm run dev --prefix assets              # Vite dev server (auto in mix phx.server)
npm run build --prefix assets            # Production build
mix tailwind collab_canvas               # Compile Tailwind CSS
```

## Architecture Overview

### Real-Time Collaboration Flow

CollabCanvas uses a **LiveView + PubSub + Presence** architecture for multi-user collaboration:

1. **Client Action** → User draws/edits on PixiJS canvas (JavaScript)
2. **LiveView Event** → JS hook sends event to `CanvasLive` via `phx-` bindings
3. **Server Processing** → LiveView validates, persists to SQLite via `Canvases` context
4. **PubSub Broadcast** → Change broadcast to topic `"canvas:{canvas_id}"` via `Phoenix.PubSub`
5. **All Clients Update** → All connected LiveViews receive broadcast via `handle_info/2`
6. **Client Rendering** → Server pushes event to JS hooks, which update PixiJS canvas

**Key files:**
- `lib/collab_canvas_web/live/canvas_live.ex` - LiveView orchestration (1762 lines)
- `lib/collab_canvas/canvases.ex` - Database context for canvas/object CRUD
- `assets/js/hooks/canvas_manager.js` - PixiJS rendering and user interaction

### AI-Powered Canvas Manipulation

Natural language commands (e.g., "create 3 blue circles in a row") are processed via:

1. **AI Agent** (`lib/collab_canvas/ai/agent.ex`) - Calls Claude API with function calling tools
2. **Tool Definitions** (`lib/collab_canvas/ai/tools.ex`) - Defines 15+ tools (create_shape, arrange_objects, etc.)
3. **Layout Engine** (`lib/collab_canvas/ai/layout.ex`) - Algorithms for grid, circular, constraint-based layouts
4. **Component Builder** (`lib/collab_canvas/ai/component_builder.ex`) - Builds complex UI (login forms, navbars, cards)

**AI Execution Flow:**
- User types command → `execute_ai_command` event → `Task.async` spawns AI call (non-blocking)
- Claude API returns tool calls → Agent executes tools → Objects created/updated → PubSub broadcast
- 30-second timeout protection, graceful error handling

**Supported AI providers:**
- Claude (default) via `CLAUDE_API_KEY`
- OpenAI via `OPENAI_API_KEY` + `AI_PROVIDER=openai`
- Groq via `GROQ_API_KEY` + `AI_PROVIDER=groq`

### Database Schema

**Core entities:**
- `canvases` - User-owned workspaces
- `objects` - Shapes/text on canvases (polymorphic: rectangles, circles, text, components)
  - `position: map` - `%{x: float, y: float}`
  - `data: text` - JSON blob with type-specific properties (width, height, color, text content, etc.)
  - `locked_by: string` - User ID for edit locking (prevents conflicts)
- `canvas_user_viewports` - Saves per-user viewport position/zoom for each canvas
- `components` - Reusable UI component templates
- `styles` - Shared styling definitions

**Important:** Objects use JSON `data` field for flexibility. Always decode with `Jason.decode!` before reading, encode with `Jason.encode!` before writing.

### Object Locking System

Prevents simultaneous edits to the same object:

1. User selects object → `lock_object` event → `Canvases.lock_object(object_id, user_id)`
2. Server checks `locked_by` field → Returns `:already_locked` if locked by another user
3. On success → Broadcast `{:object_locked, object}` to all clients → Visual feedback (grayed out)
4. User deselects → `unlock_object` event → `locked_by` set to `nil` → Broadcast unlock
5. On disconnect → `terminate/2` callback unlocks all objects for that user

**Key functions:**
- `Canvases.lock_object/2` - Acquire lock
- `Canvases.unlock_object/2` - Release lock
- `Canvases.check_lock/1` - Query lock status

### Frontend Architecture (PixiJS)

**File structure:**
- `assets/js/app.js` - Entry point, initializes LiveView socket and hooks
- `assets/js/hooks/canvas_manager.js` - Main PixiJS hook, handles all canvas rendering
- `assets/js/core/canvas_manager.js` - Core PixiJS logic (object creation, selection, dragging)
- `assets/js/core/performance_monitor.js` - FPS tracking and performance metrics

**PixiJS integration:**
- LiveView hook lifecycle: `mounted()` initializes PixiJS app, `destroyed()` cleans up
- Server events (`push_event`) trigger PixiJS updates (create, update, delete objects)
- Client events (`pushEvent`) send user actions to server (object created, dragged, etc.)

**Pan & zoom:**
- Space + drag = pan canvas
- Ctrl/Cmd + scroll = zoom in/out
- Two-finger scroll (trackpad) = pan
- Viewport position auto-saved to DB on change

## Context Modules (Business Logic Layer)

Phoenix contexts provide clean separation between web and domain logic:

- **`CollabCanvas.Canvases`** - Canvas and object management (CRUD operations)
  - `create_canvas/2`, `get_canvas_with_preloads/2`, `list_user_canvases/1`
  - `create_object/3`, `update_object/2`, `delete_object/1`
  - `lock_object/2`, `unlock_object/2`, `check_lock/1`
  - `save_viewport/3`, `get_viewport/2`

- **`CollabCanvas.Accounts`** - User management
  - `get_user/1`, `create_user/1`, `find_or_create_user_from_auth/1`

- **`CollabCanvas.Components`** - Component templates
  - `create_component/1`, `instantiate_component/2` (creates objects from template)

- **`CollabCanvas.Styles`** - Shared styles
  - `create_style/1`, `apply_style_to_object/2`

**Convention:** Always use context functions, never query Ecto directly from LiveViews or controllers.

## LiveView Patterns

### Event Handling

```elixir
# Handle event from client
def handle_event("create_object", %{"type" => type} = params, socket) do
  # 1. Validate and transform params
  # 2. Call context function (Canvases.create_object)
  # 3. Broadcast to PubSub topic
  # 4. Update local state
  # 5. Push event to JS hook (push_event)
  {:noreply, socket}
end

# Handle PubSub broadcast from other clients
def handle_info({:object_created, object}, socket) do
  # 1. Check for duplicates (originating client already has it)
  # 2. Update local state
  # 3. Push event to JS hook
  {:noreply, socket}
end
```

### Async Operations (AI Commands)

```elixir
# Spawn non-blocking task
task = Task.async(fn -> Agent.execute_command(command, canvas_id) end)
Process.send_after(self(), {:ai_timeout, task.ref}, 30_000)
{:noreply, assign(socket, ai_loading: true, ai_task_ref: task.ref)}

# Handle task completion
def handle_info({ref, result}, socket) when is_reference(ref) do
  if ref == socket.assigns.ai_task_ref do
    Process.demonitor(ref, [:flush])
    # Process result...
  end
end
```

## Important Patterns & Conventions

### JSON Data Handling

Objects store type-specific data in a JSON blob:

```elixir
# Creating object with data
data = %{width: 100, height: 50, color: "#FF0000"}
attrs = %{
  position: %{x: 10, y: 20},
  data: Jason.encode!(data)  # ALWAYS encode before saving
}
Canvases.create_object(canvas_id, "rectangle", attrs)

# Reading object data
object = Canvases.get_object(object_id)
decoded_data = Jason.decode!(object.data)  # ALWAYS decode after reading
width = decoded_data["width"]
```

### PubSub Topics

Each canvas has a dedicated topic:

```elixir
topic = "canvas:#{canvas_id}"

# Subscribe on mount
Phoenix.PubSub.subscribe(CollabCanvas.PubSub, topic)

# Broadcast changes
Phoenix.PubSub.broadcast(CollabCanvas.PubSub, topic, {:object_created, object})
Phoenix.PubSub.broadcast(CollabCanvas.PubSub, topic, {:object_updated, object})
Phoenix.PubSub.broadcast(CollabCanvas.PubSub, topic, {:object_deleted, object_id})
```

### Presence Tracking (User Cursors)

```elixir
# Track user on mount
Presence.track(self(), topic, user_id, %{
  online_at: System.system_time(:second),
  cursor: nil,
  color: "#3b82f6",
  name: user.name,
  email: user.email
})

# Update cursor position
Presence.update(self(), topic, user_id, fn meta ->
  Map.put(meta, :cursor, %{x: x, y: y})
end)

# Handle presence changes
def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
  presences = Presence.list(topic)
  {:noreply, socket |> assign(:presences, presences) |> push_event("presence_updated", %{presences: presences})}
end
```

## Testing Conventions

- Tests live in `test/collab_canvas` and `test/collab_canvas_web`
- Context tests: Test CRUD operations, validation, edge cases
- LiveView tests: Use `Phoenix.LiveViewTest` helpers (`live/2`, `render_click/2`, etc.)
- Always test happy path + error cases (not found, validation failures)

## Configuration Files

- **`config/config.exs`** - Base config (shared across all environments)
- **`config/dev.exs`** - Development-specific (DB path, live reload, debug settings)
- **`config/runtime.exs`** - Runtime config (reads env vars: `CLAUDE_API_KEY`, `AUTH0_*`, etc.)
- **`.env`** - Local secrets (NOT committed, used by `dotenvy` in dev)

**Required environment variables for AI features:**
- `CLAUDE_API_KEY` - Anthropic API key for AI commands (default provider)
- `OPENAI_API_KEY` - OpenAI GPT-4 (optional, set `AI_PROVIDER=openai`)
- `GROQ_API_KEY` - Groq Llama 3.3 (optional, set `AI_PROVIDER=groq`)

## Performance Considerations

- **Layout operations** must complete in <500ms for up to 50 objects (per PRD requirement)
- **Batch updates** use `update_objects_batch` for multi-select drag (transactional, single broadcast)
- **PixiJS rendering** is optimized via:
  - Object pooling for rectangles/circles
  - Texture atlasing for icons
  - Performance monitoring (`performance_monitor.js`)
- **Database queries** use preloading to avoid N+1 queries (`get_canvas_with_preloads/2`)

## Common Tasks

### Adding a New Object Type

1. Update `Object` schema in `lib/collab_canvas/canvases/object.ex` (if needed)
2. Add AI tool definition in `lib/collab_canvas/ai/tools.ex`
3. Implement tool handler in `lib/collab_canvas/ai/agent.ex` (`execute_tool_call/2`)
4. Add PixiJS rendering logic in `assets/js/core/canvas_manager.js`
5. Update LiveView event handlers in `lib/collab_canvas_web/live/canvas_live.ex`

### Adding a New AI Tool

1. Define tool schema in `Tools.get_tool_definitions/0` with name, description, parameters
2. Implement `execute_tool_call/2` clause in `Agent` module
3. Test with AI command: "Create a {your new feature}"

### Adding a New LiveView Event

1. Add `phx-click` or `phx-` binding in template (`render/1`)
2. Implement `handle_event/3` in LiveView module
3. Add corresponding `handle_info/2` for PubSub broadcast if needed
4. Update JS hook to trigger event (`this.pushEvent("event_name", data)`)

## Migration Workflow

```bash
# Generate migration
mix ecto.gen.migration add_field_to_objects

# Edit generated file in priv/repo/migrations/
# Run migration
mix ecto.migrate

# Rollback if needed
mix ecto.rollback
```

## Debugging Tips

- **LiveView debugging:** Use `IO.inspect(socket.assigns, label: "ASSIGNS")` in event handlers
- **PubSub debugging:** Add `require Logger` and `Logger.info("Broadcast: ...")` in broadcasts
- **AI debugging:** Check `Logger.info` output in terminal for Claude API requests/responses
- **PixiJS debugging:** Open browser DevTools Console, check for errors in `canvas_manager.js`
- **Database debugging:** Use `Ecto.Adapters.SQL.explain/2` for query performance

## Code Style

- **Elixir:** Follow `mix format` style (runs on `mix precommit`)
- **JavaScript:** ES6+ syntax, async/await preferred over promises
- **Documentation:** Use `@moduledoc` and `@doc` for all public functions
- **Naming:**
  - Elixir: `snake_case` for functions/variables
  - JavaScript: `camelCase` for functions/variables
  - Phoenix: Plural context names (`Canvases`, not `Canvas`), singular schema names

## Deployment Notes

- Built with `mix phx.digest` for asset fingerprinting
- Uses Bandit web server (configured in `config/config.exs`)
- SQLite database path configured in `config/runtime.exs`
- Auth0 OAuth callback URL must match production domain
