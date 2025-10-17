# PRD 3.0: The Intelligent Design System

## Executive Summary

This PRD defines requirements to elevate the AI agent from a simple object creator to an intelligent design assistant. Additionally, it introduces a component system and style management to transform the tool from a drawing application into a comprehensive design system platform.

## Performance Requirements

- **AI Response Time:** AI commands must return visual results or feedback in under **2 seconds**
  - Note: Groq typically achieves 300-800ms response times vs OpenAI's 1-2s
- **Component Updates:** Changes to main components must propagate to all instances within **100ms**
- **Style Application:** Applying styles to selected objects must complete within **50ms**
- **AI Layout Calculations:** Layout arrangement commands must complete within **500ms** for up to 50 objects

## AI System Architecture

### Overview

The AI system supports **OpenAI-compatible API providers** for natural language command interpretation and tool-based execution. The architecture follows a request-response pattern with function calling (tools) capabilities.

**Default Provider:** OpenAI (GPT-4)
**Alternative Provider:** Groq (Llama 3.1 / Mixtral) - Ultra-fast inference for development and high-throughput scenarios

The system is provider-agnostic and can switch between compatible providers via environment configuration without code changes.

### AI Provider Configuration

**Provider Flexibility:** The system supports any OpenAI-compatible API provider. Configuration is environment-based for easy switching between providers.

**Supported Providers:**

1. **OpenAI (Default)**
   - API Base: `https://api.openai.com/v1`
   - Primary Model: `gpt-4-turbo-preview` or `gpt-4-1106-preview`
   - Fallback Model: `gpt-3.5-turbo-1106`
   - Best for: Reliability, broad model selection
   - Cost: Standard OpenAI pricing

2. **Groq (Recommended for Speed)**
   - API Base: `https://api.groq.com/openai/v1`
   - Primary Model: `llama-3.1-70b-versatile` or `mixtral-8x7b-32768`
   - Fallback Model: `llama-3.1-8b-instant`
   - Best for: Ultra-fast inference (10x-100x faster than OpenAI)
   - Cost: Lower cost per token
   - Note: Uses OpenAI-compatible API format

**Model Requirements:**
- Must support function calling (tools)
- Minimum 32k context window (128k preferred)
- JSON mode support preferred
- Streaming support for real-time feedback

**Configuration via Environment Variables:**
```bash
# Provider selection
AI_PROVIDER=groq                    # "openai" or "groq" (default: openai)

# OpenAI configuration
OPENAI_API_KEY=sk-...
OPENAI_API_BASE=https://api.openai.com/v1

# Groq configuration
GROQ_API_KEY=gsk_...
GROQ_API_BASE=https://api.groq.com/openai/v1

# Model selection (provider-specific)
AI_PRIMARY_MODEL=llama-3.1-70b-versatile
AI_FALLBACK_MODEL=llama-3.1-8b-instant
```

**Example: Switching from OpenAI to Groq**
```bash
# Development: Use Groq for fast iteration
AI_PROVIDER=groq
GROQ_API_KEY=gsk_your_key_here
AI_PRIMARY_MODEL=llama-3.1-70b-versatile
AI_FALLBACK_MODEL=llama-3.1-8b-instant

# Production: Use OpenAI for reliability
AI_PROVIDER=openai
OPENAI_API_KEY=sk_your_key_here
AI_PRIMARY_MODEL=gpt-4-turbo-preview
AI_FALLBACK_MODEL=gpt-3.5-turbo-1106
```

### System Architecture

```
User Input → Frontend → LiveView Handler → AI Agent → OpenAI API → Tool Execution → Response
                                              ↓
                                        Canvas Context
                                        (objects, selection, history)
```

### Request Flow

1. **User Input Processing**
   - User types command in AI chat input
   - Frontend captures command + current selection state
   - Send to LiveView via `handle_event("ai_command", %{"prompt" => prompt, "selection" => ids}, socket)`

2. **Context Building**
   - Gather canvas state (all objects)
   - Include selected object IDs and properties
   - Include recent command history (last 5 commands)
   - Build system prompt with available tools

3. **OpenAI Request**
   - **Model:** `gpt-4-turbo-preview`
   - **Temperature:** 0.1 (low randomness for consistency)
   - **Max tokens:** 2000
   - **Tools:** Function definitions for all available operations
   - **Messages:**
     ```json
     [
       {
         "role": "system",
         "content": "You are a design assistant. You help users manipulate objects on a canvas using the provided tools..."
       },
       {
         "role": "user",
         "content": "Arrange these in a horizontal row with 20px spacing"
       }
     ]
     ```

4. **Tool Calling Pattern**
   - OpenAI returns `tool_calls` array
   - Execute each tool call sequentially
   - Collect results
   - Send results back to OpenAI if needed for multi-step reasoning
   - Return final response to user

5. **Response Handling**
   - Apply tool changes to canvas
   - Broadcast updates via PubSub
   - Send confirmation message to user
   - Update command history

### Technical Implementation

#### Backend Structure

```elixir
# lib/collab_canvas/ai/
├── agent.ex                  # Main AI orchestration
├── openai_client.ex          # OpenAI API wrapper
├── context_builder.ex        # Build context from canvas state
├── tool_executor.ex          # Execute tool calls
├── tools/
│   ├── object_tools.ex       # create, move, resize, rotate, delete
│   ├── layout_tools.ex       # arrange, align, distribute
│   ├── style_tools.ex        # change_style, apply_style
│   ├── text_tools.ex         # update_text
│   ├── component_tools.ex    # create_component, instantiate
│   └── selection_tools.ex    # select, deselect, query objects
└── response_parser.ex        # Parse and validate AI responses
```

#### Core Module: Agent

```elixir
defmodule CollabCanvas.AI.Agent do
  alias CollabCanvas.AI.{OpenAIClient, ContextBuilder, ToolExecutor}

  @doc """
  Process a natural language command and execute it on the canvas
  """
  def handle_command(canvas_id, prompt, opts \\ []) do
    with {:ok, context} <- ContextBuilder.build(canvas_id, opts),
         {:ok, response} <- OpenAIClient.chat_completion(prompt, context),
         {:ok, results} <- execute_tool_calls(canvas_id, response.tool_calls),
         {:ok, _} <- broadcast_changes(canvas_id, results) do
      {:ok, %{
        message: response.message,
        operations: results,
        usage: response.usage
      }}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp execute_tool_calls(canvas_id, tool_calls) do
    Enum.reduce_while(tool_calls, {:ok, []}, fn tool_call, {:ok, acc} ->
      case ToolExecutor.execute(canvas_id, tool_call) do
        {:ok, result} -> {:cont, {:ok, [result | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, results} -> {:ok, Enum.reverse(results)}
      error -> error
    end
  end
end
```

#### OpenAI Client (Provider-Agnostic)

```elixir
defmodule CollabCanvas.AI.OpenAIClient do
  @moduledoc """
  OpenAI-compatible API client supporting multiple providers (OpenAI, Groq, etc.)
  Provider and model configuration is read from environment variables.
  """

  # Load configuration from environment
  defp config do
    provider = System.get_env("AI_PROVIDER", "openai")

    case provider do
      "groq" ->
        %{
          api_base: System.get_env("GROQ_API_BASE", "https://api.groq.com/openai/v1"),
          api_key: System.get_env("GROQ_API_KEY"),
          primary_model: System.get_env("AI_PRIMARY_MODEL", "llama-3.1-70b-versatile"),
          fallback_model: System.get_env("AI_FALLBACK_MODEL", "llama-3.1-8b-instant"),
          provider: :groq
        }

      "openai" ->
        %{
          api_base: System.get_env("OPENAI_API_BASE", "https://api.openai.com/v1"),
          api_key: System.get_env("OPENAI_API_KEY"),
          primary_model: System.get_env("AI_PRIMARY_MODEL", "gpt-4-turbo-preview"),
          fallback_model: System.get_env("AI_FALLBACK_MODEL", "gpt-3.5-turbo-1106"),
          provider: :openai
        }

      _ ->
        raise "Unsupported AI_PROVIDER: #{provider}. Must be 'openai' or 'groq'"
    end
  end

  def chat_completion(prompt, context, opts \\ []) do
    cfg = config()
    model = Keyword.get(opts, :model, cfg.primary_model)

    body = %{
      model: model,
      temperature: 0.1,
      max_tokens: 2000,
      messages: build_messages(prompt, context),
      tools: build_tools(context.available_tools),
      tool_choice: "auto"
    }

    case http_post(cfg.api_base, "/chat/completions", body, cfg.api_key) do
      {:ok, %{status: 200, body: response}} ->
        parse_response(response)

      {:ok, %{status: 429}} when model == cfg.primary_model ->
        # Rate limited, retry with fallback model
        Logger.warning("Rate limited on #{model}, falling back to #{cfg.fallback_model}")
        chat_completion(prompt, context, model: cfg.fallback_model)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp http_post(api_base, path, body, api_key) do
    url = api_base <> path
    headers = [
      {"Content-Type", "application/json"},
      {"Authorization", "Bearer #{api_key}"}
    ]

    HTTPoison.post(url, Jason.encode!(body), headers)
  end

  defp build_messages(prompt, context) do
    [
      %{
        role: "system",
        content: system_prompt(context)
      },
      %{
        role: "user",
        content: prompt
      }
    ]
  end

  defp system_prompt(context) do
    """
    You are an intelligent design assistant for a collaborative canvas application.

    Current Canvas State:
    - Total objects: #{length(context.objects)}
    - Selected objects: #{length(context.selected_objects)}
    - Available components: #{length(context.components)}
    - Available styles: #{length(context.styles)}

    Your role is to help users:
    1. Create and manipulate objects (rectangles, circles, text, images)
    2. Arrange objects in layouts (horizontal, vertical, grid, circular)
    3. Apply styles and maintain design consistency
    4. Create reusable components
    5. Perform batch operations on multiple objects

    IMPORTANT RULES:
    - Always use the provided tools to make changes
    - When the user says "these" or "selected", use the selected_object_ids: #{inspect(context.selected_object_ids)}
    - Be precise with measurements (use exact pixel values)
    - Confirm destructive operations (delete, major changes)
    - For layout operations, calculate positions mathematically
    - Preserve aspect ratios unless explicitly told to distort

    Use the available tools to execute commands. You have access to:
    #{Enum.map_join(context.available_tools, "\n", fn tool -> "- #{tool.name}: #{tool.description}" end)}
    """
  end

  defp build_tools(tool_definitions) do
    Enum.map(tool_definitions, fn tool ->
      %{
        type: "function",
        function: %{
          name: tool.name,
          description: tool.description,
          parameters: tool.input_schema
        }
      }
    end)
  end
end
```

#### Tool Definitions

```elixir
defmodule CollabCanvas.AI.Tools do
  @tools [
    %{
      name: "create_object",
      description: "Create a new object on the canvas (rectangle, circle, text, image)",
      input_schema: %{
        type: "object",
        properties: %{
          type: %{
            type: "string",
            enum: ["rectangle", "circle", "text", "image"],
            description: "Type of object to create"
          },
          x: %{type: "number", description: "X position in pixels"},
          y: %{type: "number", description: "Y position in pixels"},
          width: %{type: "number", description: "Width in pixels"},
          height: %{type: "number", description: "Height in pixels"},
          properties: %{
            type: "object",
            description: "Additional properties (fill, stroke, text content, etc.)"
          }
        },
        required: ["type", "x", "y", "width", "height"]
      }
    },
    %{
      name: "move_object",
      description: "Move an object to a new position or by a delta",
      input_schema: %{
        type: "object",
        properties: %{
          object_id: %{type: "string", description: "ID of object to move"},
          x: %{type: "number", description: "X position or delta"},
          y: %{type: "number", description: "Y position or delta"},
          relative: %{type: "boolean", default: false, description: "If true, x/y are deltas"}
        },
        required: ["object_id", "x", "y"]
      }
    },
    %{
      name: "resize_object",
      description: "Resize an object to specific dimensions",
      input_schema: %{
        type: "object",
        properties: %{
          object_id: %{type: "string"},
          width: %{type: "number", description: "New width in pixels"},
          height: %{type: "number", description: "New height in pixels"},
          maintain_aspect_ratio: %{type: "boolean", default: false}
        },
        required: ["object_id"]
      }
    },
    %{
      name: "rotate_object",
      description: "Rotate an object by specified degrees",
      input_schema: %{
        type: "object",
        properties: %{
          object_id: %{type: "string"},
          rotation: %{type: "number", description: "Rotation in degrees (0-360)"},
          relative: %{type: "boolean", default: false}
        },
        required: ["object_id", "rotation"]
      }
    },
    %{
      name: "change_style",
      description: "Change visual style properties of an object",
      input_schema: %{
        type: "object",
        properties: %{
          object_id: %{type: "string"},
          fill: %{type: "string", description: "Fill color (hex, rgb, or color name)"},
          stroke: %{type: "string", description: "Stroke color"},
          stroke_width: %{type: "number", description: "Stroke width in pixels"},
          opacity: %{type: "number", description: "Opacity (0-1)"}
        },
        required: ["object_id"]
      }
    },
    %{
      name: "update_text",
      description: "Update text content and styling",
      input_schema: %{
        type: "object",
        properties: %{
          object_id: %{type: "string"},
          text: %{type: "string", description: "New text content"},
          font_size: %{type: "number"},
          font_family: %{type: "string"},
          font_weight: %{type: "string", enum: ["normal", "bold", "light"]},
          color: %{type: "string"}
        },
        required: ["object_id"]
      }
    },
    %{
      name: "arrange_objects",
      description: "Arrange multiple objects in a layout pattern",
      input_schema: %{
        type: "object",
        properties: %{
          object_ids: %{
            type: "array",
            items: %{type: "string"},
            description: "IDs of objects to arrange"
          },
          layout_type: %{
            type: "string",
            enum: ["horizontal", "vertical", "grid", "circular", "stack"],
            description: "Type of layout to apply"
          },
          spacing: %{type: "number", description: "Spacing between objects in pixels"},
          alignment: %{
            type: "string",
            enum: ["left", "center", "right", "top", "middle", "bottom"]
          },
          grid_columns: %{type: "number", description: "For grid layout: number of columns"}
        },
        required: ["object_ids", "layout_type"]
      }
    },
    %{
      name: "align_objects",
      description: "Align multiple objects relative to each other or canvas",
      input_schema: %{
        type: "object",
        properties: %{
          object_ids: %{type: "array", items: %{type: "string"}},
          alignment: %{
            type: "string",
            enum: ["left", "center", "right", "top", "middle", "bottom", "canvas_center"]
          }
        },
        required: ["object_ids", "alignment"]
      }
    },
    %{
      name: "delete_objects",
      description: "Delete one or more objects from the canvas",
      input_schema: %{
        type: "object",
        properties: %{
          object_ids: %{type: "array", items: %{type: "string"}}
        },
        required: ["object_ids"]
      }
    },
    %{
      name: "create_component",
      description: "Create a reusable component from selected objects",
      input_schema: %{
        type: "object",
        properties: %{
          object_ids: %{type: "array", items: %{type: "string"}},
          name: %{type: "string", description: "Component name"},
          category: %{type: "string", description: "Optional category (buttons, cards, etc.)"}
        },
        required: ["object_ids", "name"]
      }
    },
    %{
      name: "instantiate_component",
      description: "Create an instance of a component",
      input_schema: %{
        type: "object",
        properties: %{
          component_id: %{type: "string"},
          x: %{type: "number", description: "X position for instance"},
          y: %{type: "number", description: "Y position for instance"}
        },
        required: ["component_id", "x", "y"]
      }
    },
    %{
      name: "apply_style",
      description: "Apply a saved style to an object",
      input_schema: %{
        type: "object",
        properties: %{
          object_id: %{type: "string"},
          style_id: %{type: "string"}
        },
        required: ["object_id", "style_id"]
      }
    },
    %{
      name: "query_objects",
      description: "Query objects by properties (useful for finding objects to manipulate)",
      input_schema: %{
        type: "object",
        properties: %{
          type: %{type: "string", description: "Filter by object type"},
          color: %{type: "string", description: "Filter by fill color"},
          min_width: %{type: "number"},
          max_width: %{type: "number"}
        }
      }
    }
  ]

  def get_all, do: @tools

  def get_by_name(name) do
    Enum.find(@tools, fn tool -> tool.name == name end)
  end
end
```

#### Context Builder

```elixir
defmodule CollabCanvas.AI.ContextBuilder do
  alias CollabCanvas.{Canvas, Components, Styles}

  def build(canvas_id, opts) do
    selected_ids = Keyword.get(opts, :selected_ids, [])

    with {:ok, canvas} <- Canvas.get(canvas_id),
         {:ok, objects} <- Canvas.list_objects(canvas_id),
         {:ok, components} <- Components.list_components(canvas_id),
         {:ok, styles} <- Styles.list_styles(canvas_id) do

      selected_objects = Enum.filter(objects, fn obj -> obj.id in selected_ids end)

      {:ok, %{
        canvas_id: canvas_id,
        canvas: canvas,
        objects: objects,
        selected_objects: selected_objects,
        selected_object_ids: selected_ids,
        components: components,
        styles: styles,
        available_tools: CollabCanvas.AI.Tools.get_all()
      }}
    end
  end
end
```

### Security & Rate Limiting

**API Key Management:**
- Store API keys in environment variables (`OPENAI_API_KEY`, `GROQ_API_KEY`)
- Never expose API keys to frontend
- Rotate keys quarterly
- Use separate keys for development/staging/production

**Rate Limiting:**
- Per-user limit: 30 AI commands per minute
- Per-canvas limit: 100 AI commands per minute
- Graceful degradation to fallback model on 429 errors
- Provider-specific: Groq has higher rate limits (14,400 requests/minute on paid plans)

**Input Validation:**
- Sanitize all user prompts
- Validate tool parameters before execution
- Prevent prompt injection attacks
- Max prompt length: 2000 characters

**Cost Management:**
- Track token usage per request
- Alert when daily usage exceeds threshold
- Cache common command patterns
- Use cheaper model for simple commands

**Provider-Specific Considerations:**

*OpenAI:*
- Tier-based rate limits (increase with usage history)
- More expensive but highest reliability
- Best for production with high-stakes operations

*Groq:*
- Ultra-fast inference (300-800 tokens/sec vs OpenAI's 30-100)
- Lower cost per token
- Higher rate limits
- Excellent for development and high-throughput scenarios
- Note: Smaller model selection vs OpenAI

**Recommended Strategy:**
- Use Groq for development and testing (fast iteration, low cost)
- Use OpenAI for production if reliability is critical
- Switch providers via environment variable without code changes

### Error Handling

```elixir
defmodule CollabCanvas.AI.ErrorHandler do
  def handle_error({:error, :rate_limit}), do:
    {:error, "AI service is busy. Please try again in a moment."}

  def handle_error({:error, :invalid_tool_call}), do:
    {:error, "I couldn't execute that command. Could you rephrase it?"}

  def handle_error({:error, :object_not_found}), do:
    {:error, "I couldn't find the object you're referring to. Please select it first."}

  def handle_error({:error, :api_error, message}), do:
    {:error, "AI service error: #{message}"}
end
```

### Monitoring & Logging

**Metrics to Track:**
- AI request latency (p50, p95, p99) by provider
- Token usage per request
- Tool call success rate
- Error rate by type
- Cost per command by provider
- Provider availability and failover rate

**Logging:**
```elixir
Logger.info("AI command executed", %{
  canvas_id: canvas_id,
  user_id: user_id,
  provider: provider,        # "openai" or "groq"
  model: model,              # actual model used
  prompt: prompt,
  tools_called: length(tool_calls),
  duration_ms: duration,
  tokens_used: tokens,
  cost_usd: cost
})
```

**Provider Comparison Dashboard:**
Track and compare metrics across providers to inform configuration decisions:
- Average latency: OpenAI vs Groq
- Success rate by provider
- Cost comparison
- Failover frequency

### Frontend Integration

**Chat Interface:**
```javascript
// AI command input component
const AIChat = () => {
  const sendCommand = (prompt) => {
    pushEvent("ai_command", {
      prompt: prompt,
      selection: getSelectedObjectIds(),
      canvas_bounds: getCanvasBounds()
    })
  }

  // Show streaming response
  handleEvent("ai_response_chunk", (chunk) => {
    appendToChat(chunk)
  })

  // Handle completion
  handleEvent("ai_command_complete", (result) => {
    showSuccessMessage(result.message)
    // Canvas automatically updates via PubSub
  })
}
```

**LiveView Handler:**
```elixir
def handle_event("ai_command", %{"prompt" => prompt, "selection" => selection}, socket) do
  canvas_id = socket.assigns.canvas_id

  # Show loading state
  send(self(), {:ai_processing, prompt})

  # Process in async task
  Task.Supervisor.start_child(CollabCanvas.TaskSupervisor, fn ->
    case AI.Agent.handle_command(canvas_id, prompt, selected_ids: selection) do
      {:ok, result} ->
        send_update(CollabCanvasWeb.AIChat, id: "ai-chat", result: result)
      {:error, reason} ->
        send_update(CollabCanvasWeb.AIChat, id: "ai-chat", error: reason)
    end
  end)

  {:noreply, assign(socket, ai_processing: true)}
end
```

### Testing Strategy

**Unit Tests:**
- Test each tool execution independently
- Mock OpenAI API responses
- Test context building with various canvas states
- Test error handling for all failure modes

**Integration Tests:**
- Test full command flow (input → execution → response)
- Test multi-step tool calls
- Test concurrent AI commands
- Test rate limiting behavior

**E2E Tests:**
- Test natural language commands
- Verify canvas updates correctly
- Test with real OpenAI API (staging environment only)
- Test collaborative scenarios with AI

### Future Extensibility

**Architecture Decision:** The current implementation uses a provider-agnostic OpenAI-compatible API client for simplicity, performance, and alignment with the Elixir/Phoenix stack. This is optimal for the single-turn command pattern required in this PRD.

**Adding New Providers:**
Any OpenAI-compatible provider can be added by:
1. Adding a new case in the `config/0` function
2. Setting provider-specific environment variables
3. No code changes needed beyond configuration

Compatible providers include: Together AI, Anyscale, Perplexity, Fireworks AI, and others that implement the OpenAI API spec.

**When to Consider Microservice Expansion:**

If future requirements include complex AI workflows such as:
- Multi-step reasoning chains (e.g., "Design a complete landing page" requiring planning → creation → review → refinement)
- Advanced conversation memory with summarization
- Multi-modal inputs (image analysis → design suggestions)
- Complex agent orchestration (multiple AI agents collaborating)

Then implement these capabilities as a **separate microservice** (Python-based with LangChain or similar frameworks) that the Phoenix application calls via HTTP API. This approach:
- Keeps the core application simple and performant
- Allows using specialized AI frameworks in their native language
- Enables independent scaling of AI-intensive operations
- Maintains clear separation of concerns

**Current Decision:** Direct OpenAI integration is sufficient for PRD 3.0 requirements. Microservice expansion should be evaluated in future PRDs if advanced AI patterns are needed.

## Core Features

### 3.1 Reusable Component System

**User Story:** As a designer, I can create a "main component" from a set of objects, and then create multiple "instances" of it. When I edit the main component, all instances update automatically.

**Requirements:**

1. **Component Creation**
   - Select one or more objects and convert to main component
   - Keyboard shortcut: Cmd+Alt+K (Create Component)
   - Assign a unique name to the component
   - Component appears in a dedicated Components panel
   - Main component is marked with a special icon (purple diamond)

2. **Component Structure**
   - Store component definition as a template of objects
   - Include all properties: geometry, styles, relationships
   - Support nested components (components within components)
   - Version each component change
   - Tag components by category (buttons, cards, layouts, etc.)

3. **Instance Creation**
   - Drag component from Components panel to canvas
   - Keyboard shortcut: Cmd+Alt+V (Paste as Instance)
   - Each instance maintains a link to the main component
   - Instances marked with purple outline in layers panel

4. **Instance Overrides**
   - Allow specific properties to be overridden per instance:
     - Text content
     - Images
     - Colors (within defined style slots)
     - Visibility of nested elements
   - Overrides persist when main component updates
   - Visual indicator showing which properties are overridden
   - Right-click option: "Reset to Main Component"

5. **Component Propagation**
   - Editing main component updates all instances in real-time
   - Changes apply to all canvases where component is used
   - Preserve instance overrides during updates
   - Show notification: "Updating 12 instances..."
   - Undo entire component update as single operation

6. **Component Organization**
   - Components library shared across all canvases in workspace
   - Folder organization in Components panel
   - Search and filter components by name/tag
   - Publish/unpublish components for team use
   - Version history for each component

**Technical Implementation:**

- **Database Schema:**

```elixir
# New table: components
create table(:components) do
  add :name, :string, null: false
  add :description, :text
  add :category, :string
  add :canvas_id, references(:canvases, on_delete: :cascade)
  add :created_by, :string
  add :is_published, :boolean, default: false
  add :template_data, :map  # Stores the object structure

  timestamps()
end

# Modify objects table
field :component_id, references(:components, on_delete: :nilify)
field :is_main_component, :boolean, default: false
field :instance_overrides, :map, default: %{}
```

- **Backend:**
  - Context: `lib/collab_canvas/components.ex`
  - Functions: `create_component/3`, `instantiate_component/3`, `update_component/2`
  - PubSub broadcasts on component changes
  - Batch update all instances when main component changes

- **Frontend:**
  - New LiveComponent: `ComponentsPanelLive`
  - Display component library with preview thumbnails
  - Drag-and-drop to instantiate components
  - Override panel for selected instances

**API Changes:**

```elixir
# New events
handle_event("create_component", %{
  "object_ids" => ids,
  "name" => name,
  "category" => category
}, socket)

handle_event("instantiate_component", %{
  "component_id" => id,
  "position" => %{"x" => x, "y" => y}
}, socket)

handle_event("update_component", %{
  "component_id" => id,
  "changes" => changes
}, socket)

handle_event("override_instance_property", %{
  "instance_id" => id,
  "property" => property,
  "value" => value
}, socket)
```

**Acceptance Criteria:**

- Users can create components from selected objects
- Instances can be created by dragging from Components panel
- Editing main component updates all instances in real-time
- Instance overrides persist through component updates
- Component system works across multiple canvases
- All operations sync correctly in collaborative sessions

---

### 3.2 AI-Powered Layouts

**User Story:** As an AI user, I can select several objects and issue commands like "Arrange these in a horizontal row" or "Space these evenly."

**Requirements:**

1. **Selection-Based AI Commands**
   - AI recognizes when objects are selected
   - Commands reference "selected objects" or "these objects"
   - Examples:
     - "Arrange these in a horizontal row"
     - "Space these evenly vertically"
     - "Create a grid with these objects"
     - "Center these objects on the canvas"
     - "Align these to the left"

2. **Layout Algorithms**
   - **Distribute Horizontally:** Even spacing along X-axis
   - **Distribute Vertically:** Even spacing along Y-axis
   - **Grid Layout:** Arrange objects in rows and columns
   - **Circular Layout:** Arrange objects in a circle
   - **Stack:** Align objects vertically/horizontally with minimal spacing
   - **Auto Layout:** Intelligently arrange based on object sizes

3. **Alignment Commands**
   - Align left/right/center (horizontal)
   - Align top/bottom/middle (vertical)
   - Align to canvas center
   - Align to artboard bounds
   - Relative alignment: "Put the circle above the square"

4. **Spacing and Distribution**
   - Even spacing between objects
   - Specific spacing: "Space these 20 pixels apart"
   - Smart padding: "Add padding around these objects"
   - Tidy up: "Organize this mess" (AI decides best layout)

**Technical Implementation:**

- **Backend (`lib/collab_canvas/ai/`):**
  - Create new module: `Layout.ex`
  - Implement layout algorithms:

```elixir
defmodule CollabCanvas.AI.Layout do
  def distribute_horizontally(objects, spacing \\ :even)
  def distribute_vertically(objects, spacing \\ :even)
  def arrange_grid(objects, columns, spacing)
  def align_objects(objects, alignment)
  def circular_layout(objects, radius)
end
```

- **AI Tools:**
  - Add new tool: `arrange_objects`
  - Input schema:

```json
{
  "name": "arrange_objects",
  "description": "Arranges selected objects in specified layout",
  "input_schema": {
    "type": "object",
    "properties": {
      "object_ids": {
        "type": "array",
        "items": {"type": "string"},
        "description": "IDs of objects to arrange"
      },
      "layout_type": {
        "type": "string",
        "enum": ["horizontal", "vertical", "grid", "circular", "stack"],
        "description": "Type of layout to apply"
      },
      "spacing": {
        "type": "number",
        "description": "Spacing between objects in pixels"
      },
      "alignment": {
        "type": "string",
        "enum": ["left", "center", "right", "top", "middle", "bottom"]
      }
    },
    "required": ["object_ids", "layout_type"]
  }
}
```

- **Agent Enhancement:**
  - Modify `Agent.handle_command/2` to detect selected objects
  - Pass selection context to AI
  - Return batch update operations
  - Apply updates atomically

**Acceptance Criteria:**

- AI correctly interprets layout commands
- All standard layout types work correctly
- Spacing and alignment are precise
- Commands work with 2-50 selected objects
- Layout operations can be undone as single unit
- Real-time sync with collaborators

---

### 3.3 Expanded AI Command Vocabulary

**User Story:** As an AI user, I can manipulate objects with more detail, using commands like "resize the circle to 150px wide," "rotate the text 30 degrees," or "change the color of the selected square to #FF0000."

**Requirements:**

1. **Resize Commands**
   - Absolute size: "Make the rectangle 200px wide"
   - Relative size: "Make the circle 50% larger"
   - Proportional: "Scale the image to 150px width"
   - Specific dimensions: "Resize to 300x200"

2. **Rotation Commands**
   - Absolute angle: "Rotate 45 degrees"
   - Relative rotation: "Rotate clockwise 30 degrees"
   - Reset rotation: "Make it upright"
   - Rotate to match: "Rotate to match the other rectangle"

3. **Style Manipulation**
   - Color changes: "Change color to red" or "#FF0000"
   - Transparency: "Make it 50% transparent"
   - Border/stroke: "Add a 2px black border"
   - Shadow: "Add a drop shadow"
   - Gradients: "Apply a gradient from blue to green"

4. **Text Commands**
   - Font changes: "Change font to Arial"
   - Size: "Make the text 24px"
   - Weight: "Make it bold"
   - Color: "Change text color to white"
   - Alignment: "Center align the text"

5. **Position Commands**
   - Absolute position: "Move to coordinates (100, 200)"
   - Relative position: "Move 50px to the right"
   - Position relative to others: "Put it above the blue square"

6. **Layer Commands**
   - Z-order: "Bring to front" or "Send to back"
   - Visibility: "Hide this object"
   - Locking: "Lock this layer"
   - Grouping: "Group these together"

**Technical Implementation:**

- **New AI Tools:**

```elixir
# lib/collab_canvas/ai/tools.ex

@tools [
  # ... existing tools ...
  %{
    "name" => "resize_object",
    "description" => "Resize an object to specific dimensions",
    "input_schema" => %{
      "type" => "object",
      "properties" => %{
        "object_id" => %{"type" => "string"},
        "width" => %{"type" => "number"},
        "height" => %{"type" => "number"},
        "maintain_aspect_ratio" => %{"type" => "boolean", "default" => false}
      },
      "required" => ["object_id"]
    }
  },
  %{
    "name" => "rotate_object",
    "description" => "Rotate an object by specified degrees",
    "input_schema" => %{
      "type" => "object",
      "properties" => %{
        "object_id" => %{"type" => "string"},
        "rotation" => %{"type" => "number", "description" => "Rotation in degrees"},
        "relative" => %{"type" => "boolean", "default" => false}
      },
      "required" => ["object_id", "rotation"]
    }
  },
  %{
    "name" => "change_style",
    "description" => "Change visual style properties of an object",
    "input_schema" => %{
      "type" => "object",
      "properties" => %{
        "object_id" => %{"type" => "string"},
        "fill" => %{"type" => "string"},
        "stroke" => %{"type" => "string"},
        "stroke_width" => %{"type" => "number"},
        "opacity" => %{"type" => "number"}
      },
      "required" => ["object_id"]
    }
  },
  %{
    "name" => "update_text",
    "description" => "Update text content and styling",
    "input_schema" => %{
      "type" => "object",
      "properties" => %{
        "object_id" => %{"type" => "string"},
        "text" => %{"type" => "string"},
        "font_size" => %{"type" => "number"},
        "font_family" => %{"type" => "string"},
        "font_weight" => %{"type" => "string"},
        "color" => %{"type" => "string"}
      },
      "required" => ["object_id"]
    }
  },
  %{
    "name" => "move_object",
    "description" => "Move object to specific position or by delta",
    "input_schema" => %{
      "type" => "object",
      "properties" => %{
        "object_id" => %{"type" => "string"},
        "x" => %{"type" => "number"},
        "y" => %{"type" => "number"},
        "relative" => %{"type" => "boolean", "default" => false}
      },
      "required" => ["object_id"]
    }
  }
]
```

- **Tool Implementation:**
  - Each tool maps to a context function
  - Tools modify object properties
  - Changes flow through standard update pipeline
  - All changes broadcast to collaborators

**Acceptance Criteria:**

- All command types work accurately
- AI correctly parses measurements and units
- Color names and hex codes both work
- Relative and absolute commands differentiated
- Commands work on both single and multi-select
- Undo/redo works for all AI commands

---

### 3.4 Styles & Design Tokens

**User Story:** As a designer, I can save colors and text styles to a palette and re-apply them to any object, ensuring consistency across my design.

**Requirements:**

1. **Color Palette**
   - Save frequently used colors
   - Organize colors by category (primary, secondary, neutral)
   - Name each color (e.g., "Brand Blue", "Error Red")
   - Hex, RGB, HSL support
   - Color picker with saved palette integration
   - Apply saved color with one click

2. **Text Styles**
   - Save complete text formatting as a style
   - Include: font family, size, weight, color, line height, letter spacing
   - Name styles (e.g., "Heading 1", "Body Text", "Caption")
   - Preview each style in the panel
   - Apply to selected text with one click
   - Update all instances when style definition changes

3. **Effect Styles**
   - Shadow styles (drop shadow, inner shadow)
   - Blur effects
   - Gradient definitions
   - Border/stroke styles
   - Save and reuse combinations

4. **Style Management**
   - Create style from selected object
   - Edit style definition (updates all instances)
   - Delete styles (with warning if in use)
   - Import/export style libraries
   - Share styles across team

5. **Design Tokens**
   - Export styles as design tokens (JSON)
   - Integration with design systems
   - Semantic naming (e.g., `color.primary.500`)
   - Generate code for developers (CSS variables, Tailwind config)

**Technical Implementation:**

- **Database Schema:**

```elixir
# New table: styles
create table(:styles) do
  add :name, :string, null: false
  add :type, :string  # "color", "text", "effect"
  add :category, :string
  add :definition, :map
  add :canvas_id, references(:canvases, on_delete: :cascade)
  add :created_by, :string

  timestamps()
end

# New table: text_styles
create table(:text_styles) do
  add :name, :string, null: false
  add :font_family, :string
  add :font_size, :integer
  add :font_weight, :string
  add :line_height, :float
  add :letter_spacing, :float
  add :color, :string
  add :canvas_id, references(:canvases, on_delete: :cascade)

  timestamps()
end
```

- **Backend:**
  - Context: `lib/collab_canvas/styles.ex`
  - Functions: `create_style/2`, `apply_style/2`, `update_style/2`
  - PubSub for style changes

- **Frontend:**
  - New LiveComponent: `StylesPanelLive`
  - Color palette grid
  - Text styles list with previews
  - Style creation modal
  - Apply style button

**API Changes:**

```elixir
# New events
handle_event("create_style", %{
  "name" => name,
  "type" => type,
  "definition" => definition
}, socket)

handle_event("apply_style", %{
  "object_id" => id,
  "style_id" => style_id
}, socket)

handle_event("update_style", %{
  "style_id" => id,
  "definition" => definition
}, socket)

handle_event("export_design_tokens", %{"format" => format}, socket)
```

**Acceptance Criteria:**

- Users can create and save color/text/effect styles
- Styles can be applied to objects with one click
- Updating a style updates all instances
- Styles panel shows clear organization and previews
- Export to design tokens works for multiple formats
- All style operations sync across collaborators

---

## Testing Requirements

1. **Component System Tests**
   - Test component creation and instantiation
   - Test instance overrides and propagation
   - Test nested components
   - Test collaborative component editing

2. **AI Layout Tests**
   - Test all layout algorithms with various object counts
   - Test alignment accuracy (±1px tolerance)
   - Test with different object sizes and types
   - Performance test with 50 objects

3. **AI Command Tests**
   - Test each command type (resize, rotate, style, text)
   - Test command parsing accuracy
   - Test multi-object commands
   - Test undo/redo for AI operations

4. **Styles Tests**
   - Test style creation and application
   - Test style propagation on update
   - Test design token export
   - Test style sharing across canvases

## Success Metrics

- AI command success rate >95%
- Component updates propagate within 100ms
- Style application completes within 50ms
- AI layout calculations complete within 500ms
- User efficiency increases by 40% with components
- User satisfaction rating of 4.7+/5 for AI features
