# CollabCanvas - Tool Execution & Error Handling Architecture

## Project Overview

CollabCanvas is a real-time collaborative canvas application built with:
- **Backend:** Elixir 1.15+, Phoenix 1.8, Phoenix LiveView 1.1
- **Frontend:** JavaScript/ES6+, PixiJS v8 (WebGL canvas rendering)
- **Database:** SQLite via Ecto 3.13
- **Real-time:** Phoenix PubSub (multi-user sync), Phoenix Presence (cursor tracking)
- **AI:** Claude 3.5 Sonnet API (natural language canvas commands)

---

## 1. WHERE AI TOOL CALLS ARE EXECUTED

### Entry Point: CanvasLive.execute_ai_command Event Handler
**File:** `/Users/reuben/gauntlet/figma-clone/ph-beam/collab_canvas/lib/collab_canvas_web/live/canvas_live.ex:1267-1343`

**Flow:**
1. User types command in AI assistant panel
2. `handle_event("execute_ai_command", params, socket)` is triggered
3. Check if command is a help request → return help directly without AI call
4. Prevent duplicate commands if AI is already processing
5. Spawn async Task using `Task.async/1`
6. Call `Agent.execute_command(command, canvas_id, selected_ids, opts)`
7. Set 30-second timeout via `Process.send_after(self(), {:ai_timeout, task.ref}, 30_000)`
8. Store task reference in socket: `ai_task_ref`

```elixir
task = Task.async(fn ->
  opts = [current_color: current_color]
  opts = if viewport, do: Keyword.put(opts, :viewport, viewport), else: opts
  Agent.execute_command(command, canvas_id, selected_ids, opts)
end)

Process.send_after(self(), {:ai_timeout, task.ref}, 30_000)

{:noreply,
 socket
 |> assign(:ai_loading, true)
 |> assign(:ai_task_ref, task.ref)
 |> assign(:ai_interaction_history, history)
 |> clear_flash()}
```

### AI Agent Module: Tool Call Processing
**File:** `/Users/reuben/gauntlet/figma-clone/ph-beam/collab_canvas/lib/collab_canvas/ai/agent.ex`

**Main Function:** `execute_command/4` (lines 127-176)

**Process:**
1. Verify canvas exists via `Canvases.get_canvas(canvas_id)`
2. Build enhanced command with context:
   - List all canvas objects with names ("Object 1", "Object 2", etc.)
   - Canvas statistics (colors, shape types, size distribution)
   - Selected object context if provided
   - Viewport position for semantic positioning (e.g., "at the top")
   - Current color preference
3. Call Claude API with function calling: `call_claude_api(enhanced_command, object_count)`
4. Parse response to extract tool calls
5. Normalize tool inputs (coerce string IDs to integers)
6. Process tool calls:
   - **Batch create operations** via `BatchProcessor.execute_batched_creates/4`
   - **Individual operations** via `execute_tool_call/3`
7. Return results as `{:ok, results}` or `{:error, reason}`

**Key Return Types:**
- `{:ok, [{tool: name, input: params, result: {:ok, object}}]}`
- `{:ok, {:text_response, "clarification message"}}`
- `{:error, :missing_api_key}`
- `{:error, {:api_error, status, body}}`
- `{:error, {:request_failed, reason}}`

### API Provider Selection
**File:** `/Users/reuben/gauntlet/figma-clone/ph-beam/collab_canvas/lib/collab_canvas/ai/agent.ex:213-223`

The system supports three AI providers (auto-detected or explicitly configured):

1. **Claude** (Default) - via `CLAUDE_API_KEY`
   - API: `https://api.anthropic.com/v1/messages`
   - Model: `claude-3-5-sonnet-20241022`
   - Tool format: Claude's native tool_use blocks

2. **OpenAI** - via `OPENAI_API_KEY` + `AI_PROVIDER=openai`
   - API: `https://api.openai.com/v1/chat/completions`
   - Model: `gpt-4o` (configurable via `OPENAI_MODEL`)
   - Tool format: OpenAI function calling

3. **Groq** - via `GROQ_API_KEY` + `AI_PROVIDER=groq`
   - API: `https://api.groq.com/openai/v1/chat/completions`
   - Model: `llama-3.3-70b-versatile` (configurable via `GROQ_MODEL`)
   - Tool format: OpenAI-compatible function calling

### Tool Definitions
**File:** `/Users/reuben/gauntlet/figma-clone/ph-beam/collab_canvas/lib/collab_canvas/ai/tools.ex`

Available tools (~20+):
- **Creation:** `create_shape`, `create_text`, `create_component`
- **Manipulation:** `move_object`, `resize_object`, `rotate_object`
- **Styling:** `change_style`, `update_text`
- **Organization:** `arrange_objects`, `arrange_objects_with_pattern`, `define_object_relationships`, `group_objects`
- **Layout:** `arrange_in_star`, `arrange_along_path`, `align_objects`, `distribute_objects`
- **Selection:** `select_objects_by_description`, `select_objects_by_filter_criteria`
- **Deletion:** `delete_object`, `change_layer_order`
- **Utility:** `list_objects`, `show_object_labels`

### Batching: BatchProcessor Module
**File:** `/Users/reuben/gauntlet/figma-clone/ph-beam/collab_canvas/lib/collab_canvas/ai/batch_processor.ex`

**Purpose:** Optimize performance by batching multiple `create_*` operations

**How It Works:**
1. Separate create_* calls from other operations
2. Transform each create call into object attributes
3. Execute all creates in single atomic transaction: `Canvases.create_objects_batch/2`
4. Map results back to original tool calls in order
5. Process other operations individually

**Performance Target:** 10 objects in <2 seconds

**Example:**
```elixir
# Batch create 3 red rectangles
[
  %{name: "create_shape", input: %{"type" => "rectangle", "color" => "red", "count" => 3}},
  %{name: "move_object", input: %{"object_id" => 1, "x" => 100}},
]
↓
Batch creates 3 rectangles in single DB transaction (atomic)
Process individual move operation
↓
Return results in original order for AI
```

---

## 2. WHERE ERROR RESPONSES ARE RECEIVED AND DISPLAYED

### Task Completion Handlers
**File:** `/Users/reuben/gauntlet/figma-clone/ph-beam/collab_canvas/lib/collab_canvas_web/live/canvas_live.ex:1993-2073`

Three async completion paths:

#### A. Successful Completion
**Handler:** `handle_info({ref, result}, socket)` (lines 1994-2009)

```elixir
def handle_info({ref, result}, socket) when is_reference(ref) do
  if ref == socket.assigns.ai_task_ref do
    Process.demonitor(ref, [:flush])
    socket = process_ai_result(result, socket)
    {:noreply,
     socket
     |> assign(:ai_loading, false)
     |> assign(:ai_task_ref, nil)}
  else
    {:noreply, socket}
  end
end
```

Calls `process_ai_result/2` which handles:
- `{:ok, results}` - Process tool results
- `{:ok, {:text_response, text}}` - Display AI's text response
- `{:ok, {:toggle_labels, show}}` - Show/hide object labels
- All error cases

#### B. Task Crash/Failure
**Handler:** `handle_info({:DOWN, ref, :process, _pid, reason}, socket)` (lines 2028-2041)

```elixir
def handle_info({:DOWN, ref, :process, _pid, reason}, socket) when is_reference(ref) do
  if ref == socket.assigns.ai_task_ref do
    Logger.error("AI task crashed: #{inspect(reason)}")
    {:noreply,
     socket
     |> assign(:ai_loading, false)
     |> assign(:ai_task_ref, nil)
     |> put_flash(:error, "AI processing failed unexpectedly")}
  else
    {:noreply, socket}
  end
end
```

#### C. 30-Second Timeout
**Handler:** `handle_info({:ai_timeout, ref}, socket)` (lines 2059-2073)

```elixir
def handle_info({:ai_timeout, ref}, socket) when is_reference(ref) do
  if ref == socket.assigns.ai_task_ref do
    Logger.warning("AI task timed out after 30 seconds")
    {:noreply,
     socket
     |> assign(:ai_loading, false)
     |> assign(:ai_task_ref, nil)
     |> put_flash(:error, "AI request timed out after 30 seconds. Please try again.")}
  else
    {:noreply, socket}
  end
end
```

### Result Processing: process_ai_result/2
**File:** `/Users/reuben/gauntlet/figma-clone/ph-beam/collab_canvas/lib/collab_canvas_web/live/canvas_live.ex:2363-2665`

**Comprehensive Error Handling:**

```elixir
case result do
  # Text responses (clarifications)
  {:ok, {:text_response, text}} ->
    # Display AI's text asking for clarification
    |> put_flash(:info, text)

  # Label toggling
  {:ok, {:toggle_labels, show}} ->
    # Show/hide object labels

  # Empty results
  {:ok, results} when is_list(results) and length(results) == 0 ->
    # AI couldn't perform action
    |> put_flash(:warning, "I couldn't perform that action...")

  # Successful operations
  {:ok, results} when is_list(results) ->
    # Extract created/updated objects
    # Broadcast to PubSub
    # Update local state
    # Display success message

  # API Configuration Errors
  {:error, :missing_api_key} ->
    clarifying_question = generate_clarifying_question(:missing_api_key, ...)
    |> put_flash(:error, "AI API key not configured...")

  # HTTP API Errors
  {:error, {:api_error, status, body}} ->
    # Extract error message from API response
    # Handle specific cases: validation, rate limiting, overload
    # Generate context-aware clarifying question

  # Network/Connection Errors
  {:error, {:request_failed, reason}} ->
    |> put_flash(:error, "I couldn't connect to the AI service...")

  # Response Parsing Errors
  {:error, :invalid_response_format} ->
    |> put_flash(:error, "AI returned invalid response format")

  # Canvas Not Found
  {:error, :canvas_not_found} ->
    |> put_flash(:error, "Canvas not found or you must be logged in")

  # Generic Errors
  {:error, reason} ->
    |> put_flash(:error, "AI command failed: #{inspect(reason)}")
end
```

### Error Context Generation
**Function:** `generate_clarifying_question/3` (lines 2262-2351)

Generates user-friendly error messages with suggestions:

```elixir
:missing_api_key →
  "I couldn't process your command because the AI service isn't configured yet..."

{:api_error, 429, _} →
  "The AI service is currently rate limited. Please wait a moment and try again."

{:api_error, 529, _} →
  "The AI service is currently overloaded. Please try again in a few seconds."

{:api_error, _, "Invalid..."} →
  "Your command couldn't be processed because of a validation error...
   Try being more specific. For example: 'create a blue rectangle at x:100 y:100'"

{:request_failed, _} →
  "I couldn't connect to the AI service. This might be a network issue..."

:canvas_not_found →
  "I couldn't find the canvas to work with..."
```

### UI Flash Messages
**File:** `/Users/reuben/gauntlet/figma-clone/ph-beam/collab_canvas/lib/collab_canvas_web/live/canvas_live.ex:2680-2686`

Phoenix flash messages display at top of UI:

```elixir
<.flash kind={:info} flash={@flash} />
<.flash kind={:error} flash={@flash} />
<.flash kind={:warning} flash={@flash} />
```

Flash types used:
- `:info` - Success messages, clarifications (green/blue)
- `:error` - Error messages (red)
- `:warning` - Warnings like "AI already in progress" (yellow)

### Logging
**Logger Calls Throughout:**

```elixir
Logger.info("AI returned #{length(tool_calls)} tool call(s)")
Logger.warning("AI returned no tool calls for command: #{command}")
Logger.error("AI API call failed: #{inspect(reason)}")
Logger.debug("Executing tool via registry: #{name}")
Logger.info("Batch created #{length(create_calls)} objects in #{duration_ms}ms")
Logger.warning("Batch create exceeded 2s target: #{duration_ms}ms...")
Logger.error("AI task crashed: #{inspect(reason)}")
Logger.warning("AI task timed out after 30 seconds")
```

---

## 3. WHERE THE CHAT UI DISPLAYS MESSAGES

### Chat History Storage
**Location:** Socket assign `ai_interaction_history` (list of maps)

**Structure:**
```elixir
%{
  type: :user,           # :user or :ai
  content: "command...",
  timestamp: DateTime.utc_now()
}
```

**Management:**
- Added to on command execution (line 1330)
- Added to on AI response (line 2366)
- Keep only last 20 interactions (10 pairs)
- Cleared when user clears command

### Display Components
**File:** The render/1 template in canvas_live.ex includes the AI panel

**Notable:** Interaction history is displayed in the AI assistant panel (right sidebar)
- User commands shown with user styling
- AI responses shown with AI styling
- Timestamp tracking for ordering
- Scrollable history

### Command Input
**File:** Canvas Live template

**Features:**
- Textarea for command input
- Live preview as user types (`ai_command_change` event)
- Enter key submit → `execute_ai_command` event
- Command displayed in history after submission
- Interaction history maintained across commands

---

## 4. WHERE USER PREFERENCES/SETTINGS ARE STORED

### Color Preferences
**Module:** `CollabCanvas.ColorPalettes`
**File:** `/Users/reuben/gauntlet/figma-clone/ph-beam/collab_canvas/lib/collab_canvas/color_palettes.ex`

**Database Tables:**

1. **user_color_preferences** - Main preferences storage
   ```elixir
   %UserColorPreference{
     user_id: integer,
     default_color: string,        # Current color picker color
     recent_colors: string,        # JSON array (LIFO, max 8)
     favorite_colors: string,      # JSON array (max 20)
     inserted_at: datetime,
     updated_at: datetime
   }
   ```

2. **palettes** - User-created color palettes
   ```elixir
   %Palette{
     user_id: integer,
     name: string,
     inserted_at: datetime,
     updated_at: datetime
   }
   ```

3. **palette_colors** - Colors within a palette
   ```elixir
   %PaletteColor{
     palette_id: integer,
     color_hex: string,
     position: integer,
     inserted_at: datetime,
     updated_at: datetime
   }
   ```

### Color Preference Functions
**File:** `/Users/reuben/gauntlet/figma-clone/ph-beam/collab_canvas/lib/collab_canvas/color_palettes.ex`

```elixir
# Get or create default preferences
get_or_create_preferences(user_id)

# Get specific preferences
get_preferences(user_id)

# Color management
get_default_color(user_id) → "#000000"
set_default_color(user_id, color) → {:ok, prefs}
add_recent_color(user_id, color) → {:ok, prefs}
get_recent_colors(user_id) → ["#FF0000", ...]
add_favorite_color(user_id, color) → {:ok, prefs}
remove_favorite_color(user_id, color) → {:ok, prefs}
get_favorite_colors(user_id) → ["#FF0000", ...]

# Palette management
create_palette(user_id, name, colors)
list_user_palettes(user_id)
add_color_to_palette(palette_id, color_hex)
remove_color_from_palette(color_id)
delete_palette(palette_id)
```

### How Color Preference Is Used in AI
**File:** `/Users/reuben/gauntlet/figma-clone/ph-beam/collab_canvas/lib/collab_canvas_web/live/canvas_live.ex:1307-1320`

```elixir
# On AI command execution:
current_color = socket.assigns.current_color

task = Task.async(fn ->
  opts = [current_color: current_color]
  Agent.execute_command(command, canvas_id, selected_ids, opts)
end)
```

**File:** `/Users/reuben/gauntlet/figma-clone/ph-beam/collab_canvas/lib/collab_canvas/ai/agent.ex:129-130`

```elixir
# Current color is passed to AI in enhanced command context:
current_color = Keyword.get(opts, :current_color, "#000000")

context = """
CURRENT COLOR PICKER: #{current_color}
- Use this color when creating new shapes/text UNLESS the user specifies a different color
- If user says "create a rectangle" (without color), use #{current_color}
...
"""
```

### On Mount: Load Current Color
**File:** `/Users/reuben/gauntlet/figma-clone/ph-beam/collab_canvas_web/live/canvas_live.ex:173`

```elixir
|> assign(:current_color, ColorPalettes.get_default_color(user.id))
```

### Viewport Position Saving
**Related Setting:**

**Storage:** `canvas_user_viewports` table
```elixir
%CanvasUserViewport{
  user_id: integer,
  canvas_id: integer,
  viewport_x: float,
  viewport_y: float,
  zoom: float,
  inserted_at: datetime,
  updated_at: datetime
}
```

**Loading on Mount:** (line 155)
```elixir
viewport = Canvases.get_viewport(user.id, canvas_id)

if viewport do
  push_event(socket, "restore_viewport", %{
    x: viewport.viewport_x,
    y: viewport.viewport_y,
    zoom: viewport.zoom
  })
end
```

**Saving on Change:**
```elixir
handle_event("save_viewport", %{"x" => x, "y" => y, "zoom" => zoom}, socket) do
  Task.start(fn ->
    Canvases.save_viewport(user.id, canvas_id, %{
      viewport_x: x,
      viewport_y: y,
      zoom: zoom
    })
  end)
end
```

---

## 5. PubSub BROADCAST ARCHITECTURE

### Topic Structure
Each canvas has a dedicated PubSub topic:
```
"canvas:#{canvas_id}"
```

### Message Types Broadcast

```elixir
# Object lifecycle
{:object_created, object}
{:object_updated, object, originating_user_id}
{:object_deleted, object_id}

# Batch operations
{:objects_updated_batch, updated_objects, originating_user_id}
{:objects_grouped, group_id, updated_objects}
{:objects_ungrouped, updated_objects}
{:objects_reordered, updated_objects}

# Object locking
{:object_locked, locked_object, user_info}
{:object_unlocked, unlocked_object}

# Color changes
{:color_changed, color, user_id}

# AI results
(Same messages as above - objects_created, etc.)
```

### Deduplication
Originating client skips `push_event` when receiving own update:
```elixir
if originating_user_id == socket.assigns.user_id do
  # Skip push_event - client already has optimistic update
  {:noreply, socket}
else
  {:noreply, push_event(socket, "object_updated", ...)}
end
```

---

## 6. KEY FILES SUMMARY

| File | Purpose |
|------|---------|
| `canvas_live.ex` | LiveView orchestration (2800+ lines) |
| `agent.ex` | AI command execution, tool processing |
| `batch_processor.ex` | Batch create operations |
| `tools.ex` | Tool definitions (15+ tools) |
| `tool_registry.ex` | Plugin system for tools |
| `layout.ex` | Layout algorithms (grid, circular, etc.) |
| `component_builder.ex` | Complex UI component creation |
| `color_palettes.ex` | Color preference management |
| `canvases.ex` | Database context (CRUD operations) |
| `batch_processor.ex` | Atomic batch creation |

---

## 7. ERROR HANDLING BEST PRACTICES

### Pattern: Result Tuples
All operations return `{:ok, data}` or `{:error, reason}`:
```elixir
case Canvases.create_object(canvas_id, type, attrs) do
  {:ok, object} → # success path
  {:error, reason} → # error path
end
```

### Pattern: Async with Timeout
AI commands use:
```elixir
task = Task.async(fn → ... end)
Process.send_after(self(), {:ai_timeout, task.ref}, 30_000)
```

### Pattern: Process Monitoring
Automatic crash detection via `:DOWN` handler:
```elixir
def handle_info({:DOWN, ref, :process, _pid, reason}, socket)
```

### Pattern: Flash Messages for UI
User-facing errors via Phoenix flash:
```elixir
put_flash(socket, :error, "User-friendly error message")
```

### Pattern: Logging for Debugging
Strategic Logger calls for troubleshooting:
```elixir
Logger.info(...)   # Important operations
Logger.debug(...)  # Detailed info (dev mode)
Logger.warning(...) # Potential issues
Logger.error(...)  # Errors that need attention
```

---

## 8. PERFORMANCE CONSIDERATIONS

### Batch Performance Target
- 10 objects in <2 seconds (via BatchProcessor)
- Layout operations <500ms for up to 50 objects

### Optimization Techniques
1. **Batch database writes** - Atomic transactions
2. **Deduplication** - Skip push_event for originating client
3. **Selective fields** - Only update changed attributes
4. **Preloading** - Avoid N+1 queries (`get_canvas_with_preloads`)

### Monitoring
- Performance timing logged: `duration_ms`
- Warnings when targets exceeded
- FPS tracking on frontend via `performance_monitor.js`

