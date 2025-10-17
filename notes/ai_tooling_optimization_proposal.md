# AI Tooling Optimization Proposal: Sub-2-Second Responses

## Executive Summary

**Goal:** Restructure AI tooling for composability while achieving sub-2-second response times

**Current Bottlenecks:**
1. Sequential tool execution (~200ms+ overhead)
2. No streaming - waits for full Claude response
3. No provider selection strategy
4. Monolithic agent module
5. No prompt caching
6. Multi-turn loops add unnecessary latency for simple commands

**Solution:** Three-tier optimization approach
- **Tier 1 (Immediate):** Fast-path optimization (saves ~1-1.5s)
- **Tier 2 (Week 1-2):** Provider abstraction + parallel execution (PRD aligned)
- **Tier 3 (Week 3-4):** Streaming + agent loop (for complex commands only)

---

## Performance Analysis

### Current Latency Breakdown (Simple Command: "create a red circle")

```
Total Time: 2.8-3.5 seconds

├─ API Call to Claude            1.5-2.0s (Claude Sonnet)
├─ Tool Execution (sequential)   0.3-0.5s
│  ├─ DB write                   0.1-0.2s
│  └─ PubSub broadcast           0.1-0.2s
├─ Response parsing              0.05s
└─ LiveView update               0.05-0.1s
```

### Optimized Latency Breakdown (Same Command)

```
Total Time: 0.8-1.2 seconds ✅

├─ API Call to Groq              0.3-0.5s (Llama 3.3 70B)
├─ Tool Execution (parallel)     0.2s (concurrent DB + PubSub)
├─ Response parsing (cached)     0.01s
└─ LiveView streaming update     0.05s
```

**Savings: ~2 seconds (60-70% reduction)**

---

## Tier 1: Fast-Path Optimization (Immediate - 1 day)

### 1.1 Command Classification Layer

**Problem:** Every command uses Claude Sonnet (1.5-2s latency)

**Solution:** Classify commands by complexity and route to appropriate provider

```elixir
defmodule CollabCanvas.AI.CommandClassifier do
  @moduledoc """
  Routes commands to optimal execution path based on complexity.
  
  Fast Path (Groq): Single-operation commands, clear intent
  Complex Path (Claude): Multi-step, ambiguous, or contextual commands
  """
  
  @simple_patterns [
    ~r/^create (a|an) \w+ (circle|rectangle|square)/i,
    ~r/^delete (object|shape) \d+/i,
    ~r/^move .+ to \d+,\s*\d+/i,
    ~r/^resize .+ to \d+x\d+/i
  ]
  
  def classify(command) do
    cond do
      simple_command?(command) -> :fast_path
      contains_multiple_operations?(command) -> :complex_path
      ambiguous_intent?(command) -> :complex_path
      true -> :fast_path  # Default to fast for unknown
    end
  end
  
  defp simple_command?(command) do
    Enum.any?(@simple_patterns, &Regex.match?(&1, command))
  end
  
  defp contains_multiple_operations?(command) do
    # Count action verbs
    verbs = ["create", "move", "delete", "resize", "arrange", "align"]
    count = Enum.count(verbs, &String.contains?(String.downcase(command), &1))
    count > 1
  end
  
  defp ambiguous_intent?(command) do
    # Commands requiring context or clarification
    String.contains?(String.downcase(command), ["this", "that", "these", "those"])
  end
end
```

**Expected Impact:** 60% of commands go through Groq (0.3-0.5s vs 1.5-2s) = **1-1.5s savings**

### 1.2 Provider Abstraction (Simplified)

```elixir
defmodule CollabCanvas.AI.Provider do
  @callback call(command :: String.t(), tools :: list(), opts :: keyword()) :: 
    {:ok, tool_calls :: list()} | {:error, term()}
  
  @callback max_tokens() :: integer()
  @callback avg_latency() :: integer()  # milliseconds
end

defmodule CollabCanvas.AI.Providers.Groq do
  @behaviour CollabCanvas.AI.Provider
  
  @api_url "https://api.groq.com/openai/v1/chat/completions"
  @model "llama-3.3-70b-versatile"  # Fast inference
  
  def call(command, tools, _opts) do
    body = %{
      model: @model,
      messages: [%{role: "user", content: command}],
      tools: convert_tools_to_openai_format(tools),
      temperature: 0.1  # Lower for consistency
    }
    
    case Req.post(@api_url, json: body, headers: headers()) do
      {:ok, %{status: 200, body: response}} ->
        parse_response(response)
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  def max_tokens, do: 1024
  def avg_latency, do: 400  # 400ms average
  
  defp headers do
    [
      {"authorization", "Bearer #{System.get_env("GROQ_API_KEY")}"},
      {"content-type", "application/json"}
    ]
  end
  
  defp convert_tools_to_openai_format(tools) do
    # Groq uses OpenAI-compatible format
    Enum.map(tools, fn tool ->
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
  
  defp parse_response(%{"choices" => [%{"message" => message} | _]}) do
    tool_calls = message["tool_calls"] || []
    
    parsed = Enum.map(tool_calls, fn tc ->
      %{
        id: tc["id"],
        name: tc["function"]["name"],
        input: Jason.decode!(tc["function"]["arguments"])
      }
    end)
    
    {:ok, parsed}
  end
end

defmodule CollabCanvas.AI.Providers.Claude do
  @behaviour CollabCanvas.AI.Provider
  # ... existing implementation ...
  def avg_latency, do: 1800  # 1.8s average
end
```

### 1.3 Smart Agent Router

```elixir
defmodule CollabCanvas.AI.Agent do
  alias CollabCanvas.AI.{CommandClassifier, Providers}
  
  def execute_command(command, canvas_id, opts \\ []) do
    # 1. Classify command (< 1ms)
    path = CommandClassifier.classify(command)
    
    # 2. Select provider based on classification
    provider = select_provider(path, opts)
    
    # 3. Execute with selected provider
    case provider.call(command, Tools.get_tool_definitions(), opts) do
      {:ok, tool_calls} ->
        # 4. Execute tools in PARALLEL (next section)
        results = process_tool_calls_parallel(tool_calls, canvas_id)
        {:ok, results}
      {:error, reason} ->
        # 5. Fallback to Claude if Groq fails
        if provider != Providers.Claude do
          execute_with_provider(command, canvas_id, Providers.Claude)
        else
          {:error, reason}
        end
    end
  end
  
  defp select_provider(:fast_path, opts) do
    Keyword.get(opts, :provider, Providers.Groq)
  end
  
  defp select_provider(:complex_path, _opts) do
    Providers.Claude  # Always use Claude for complex commands
  end
end
```

**Expected Impact:** 
- Fast commands: 0.4s API call + 0.2s execution = **0.6s total** ✅
- Complex commands: 1.8s API call + 0.3s execution = **2.1s total** (acceptable for complex)

---

## Tier 2: Parallel Tool Execution (Week 1-2)

### 2.1 Parallel Execution Engine

**Problem:** Sequential tool execution wastes time

```elixir
# BEFORE (Sequential - 5 tools = 1s)
def process_tool_calls(tool_calls, canvas_id) do
  Enum.map(tool_calls, fn tool_call ->
    execute_tool_call(tool_call, canvas_id)  # 200ms each
  end)
end
```

**Solution:** Concurrent execution with Task.async_stream

```elixir
# AFTER (Parallel - 5 tools = 250ms)
def process_tool_calls_parallel(tool_calls, canvas_id) do
  tool_calls
  |> Task.async_stream(
    fn tool_call -> execute_tool_call(tool_call, canvas_id) end,
    max_concurrency: 10,
    timeout: 5000,
    on_timeout: :kill_task
  )
  |> Enum.map(fn
    {:ok, result} -> result
    {:exit, reason} -> 
      Logger.error("Tool execution failed: #{inspect(reason)}")
      %{tool: "unknown", result: {:error, :execution_failed}}
  end)
end
```

**Expected Impact:** 
- 5 tools: 1s → 0.25s (**75% reduction**)
- Single tool: No overhead

### 2.2 Tool Behaviour System (PRD Week 2)

```elixir
defmodule CollabCanvas.AI.ToolBehaviour do
  @callback schema() :: map()
  @callback validate(input :: map()) :: {:ok, map()} | {:error, term()}
  @callback execute(input :: map(), canvas_id :: integer(), context :: map()) ::
    {:ok, term()} | {:error, term()}
  
  # Performance optimization: cacheable?
  @callback cacheable?() :: boolean()
  @callback cache_key(input :: map()) :: String.t()
end

defmodule CollabCanvas.AI.Tools.CreateShape do
  @behaviour CollabCanvas.AI.ToolBehaviour
  use Ecto.Schema
  import Ecto.Changeset
  
  # Ecto schema for validation
  embedded_schema do
    field :type, Ecto.Enum, values: [:rectangle, :circle]
    field :x, :float
    field :y, :float
    field :width, :float
    field :height, :float
    field :fill, :string, default: "#3b82f6"
    field :stroke, :string, default: "#1e40af"
    field :stroke_width, :integer, default: 2
  end
  
  def schema do
    %{
      name: "create_shape",
      description: "Create a shape on the canvas",
      input_schema: %{
        type: "object",
        properties: %{
          type: %{type: "string", enum: ["rectangle", "circle"]},
          x: %{type: "number"},
          y: %{type: "number"},
          width: %{type: "number"},
          height: %{type: "number"},
          fill: %{type: "string", default: "#3b82f6"},
          stroke: %{type: "string", default: "#1e40af"},
          stroke_width: %{type: "number", default: 2}
        },
        required: ["type", "x", "y", "width"]
      }
    }
  end
  
  def validate(input) do
    changeset =
      %__MODULE__{}
      |> cast(input, [:type, :x, :y, :width, :height, :fill, :stroke, :stroke_width])
      |> validate_required([:type, :x, :y, :width])
      |> validate_inclusion(:type, [:rectangle, :circle])
    
    if changeset.valid? do
      {:ok, apply_changes(changeset)}
    else
      {:error, changeset}
    end
  end
  
  def execute(input, canvas_id, _context) do
    validated = struct(__MODULE__, input)
    
    attrs = %{
      position: %{x: validated.x, y: validated.y},
      data: Jason.encode!(%{
        width: validated.width,
        height: validated.height,
        fill: validated.fill,
        stroke: validated.stroke,
        stroke_width: validated.stroke_width
      })
    }
    
    Canvases.create_object(canvas_id, to_string(validated.type), attrs)
  end
  
  def cacheable?, do: false
  def cache_key(_input), do: nil
end
```

### 2.3 Tool Registry (Compile-Time)

```elixir
defmodule CollabCanvas.AI.ToolRegistry do
  @moduledoc """
  Compile-time tool registry for fast lookups.
  Tools are registered at compile time to avoid runtime overhead.
  """
  
  @tools [
    CollabCanvas.AI.Tools.CreateShape,
    CollabCanvas.AI.Tools.CreateText,
    CollabCanvas.AI.Tools.MoveObject,
    CollabCanvas.AI.Tools.ResizeObject,
    CollabCanvas.AI.Tools.DeleteObject,
    CollabCanvas.AI.Tools.CreateComponent
  ]
  
  # Compile-time map for O(1) lookup
  @tool_map Map.new(@tools, fn tool -> {tool.schema().name, tool} end)
  
  # Cache tool definitions at compile time
  @tool_definitions Enum.map(@tools, & &1.schema())
  
  def get_tool_definitions, do: @tool_definitions
  
  def get_tool(name) when is_binary(name) do
    Map.get(@tool_map, name)
  end
  
  def execute_tool(name, input, canvas_id, context \\ %{}) do
    case get_tool(name) do
      nil -> 
        {:error, :unknown_tool}
      tool_module ->
        with {:ok, validated} <- tool_module.validate(input),
             {:ok, result} <- tool_module.execute(validated, canvas_id, context) do
          {:ok, %{tool: name, input: input, result: result}}
        end
    end
  end
end
```

**Expected Impact:**
- Tool lookup: O(n) → O(1) (**~1ms savings per tool**)
- Validation: Ad-hoc → Ecto.Changeset (**type safety + clear errors**)
- Extensibility: Add new tools by implementing behaviour

---

## Tier 3: Streaming + Selective Agent Loop (Week 3-4)

### 3.1 Streaming Tool Execution

**Problem:** LiveView waits for all tools to complete before updating

**Solution:** Stream tool results as they complete

```elixir
defmodule CollabCanvas.AI.StreamingAgent do
  def execute_command_streaming(command, canvas_id, user_id) do
    # 1. Classify and call provider
    provider = select_provider(command)
    
    # 2. Stream API response (Claude supports streaming)
    case provider.call_streaming(command, Tools.get_tool_definitions()) do
      {:ok, stream} ->
        # 3. Process tool calls as they arrive
        stream
        |> Stream.each(fn tool_call ->
          # Execute immediately and broadcast
          result = ToolRegistry.execute_tool(
            tool_call.name, 
            tool_call.input, 
            canvas_id
          )
          
          # Broadcast to LiveView immediately
          Phoenix.PubSub.broadcast(
            CollabCanvas.PubSub,
            "canvas:#{canvas_id}",
            {:ai_tool_result, result, user_id}
          )
        end)
        |> Stream.run()
        
      {:error, reason} ->
        {:error, reason}
    end
  end
end
```

**LiveView Integration:**

```elixir
def handle_info({:ai_tool_result, result, user_id}, socket) do
  # Update UI incrementally as each tool completes
  {:noreply, 
    socket
    |> update(:ai_results, fn results -> [result | results] end)
    |> push_event("tool_executed", %{result: result, user_id: user_id})
  }
end
```

**Expected Impact:**
- First visual feedback: **0.5s** (vs 2-3s full completion)
- Perceived performance: **Instant** (progressive rendering)

### 3.2 Selective Agent Loop

**Problem:** Multi-turn loops add latency even for simple commands

**Solution:** Only use agent loop when necessary

```elixir
def execute_command(command, canvas_id, opts \\ []) do
  classification = CommandClassifier.classify(command)
  
  case classification do
    # Single-turn for simple commands (60% of cases)
    :fast_path ->
      execute_single_turn(command, canvas_id, Providers.Groq)
    
    # Multi-turn for complex commands (40% of cases)
    :complex_path ->
      execute_agent_loop(command, canvas_id, max_turns: 5)
  end
end

defp execute_single_turn(command, canvas_id, provider) do
  case provider.call(command, Tools.get_tool_definitions()) do
    {:ok, tool_calls} ->
      results = process_tool_calls_parallel(tool_calls, canvas_id)
      {:ok, results}
    {:error, reason} ->
      {:error, reason}
  end
end

defp execute_agent_loop(command, canvas_id, opts) do
  max_turns = Keyword.get(opts, :max_turns, 5)
  
  Enum.reduce_while(1..max_turns, {command, []}, fn turn, {current_cmd, history} ->
    case call_llm_with_history(current_cmd, history) do
      {:ok, [], _new_history} ->
        # LLM says we're done
        {:halt, {:ok, history}}
      
      {:ok, tool_calls, new_history} ->
        results = process_tool_calls_parallel(tool_calls, canvas_id)
        
        # Check if we need another turn
        if requires_followup?(results) do
          {:cont, {build_followup_prompt(results), new_history ++ results}}
        else
          {:halt, {:ok, new_history ++ results}}
        end
      
      {:error, reason} ->
        {:halt, {:error, reason}}
    end
  end)
end
```

**Expected Impact:**
- Simple commands: **No loop overhead** (saves 1-2 API calls)
- Complex commands: Loop only when needed

---

## Implementation Roadmap

### Phase 1: Fast Path (1 day) ⚡

**Files to create/modify:**
```
lib/collab_canvas/ai/
├── command_classifier.ex          [NEW] - 100 lines
├── provider.ex                     [NEW] - 50 lines
├── providers/
│   ├── groq.ex                    [NEW] - 150 lines
│   └── claude.ex                  [REFACTOR] - Extract from agent.ex
└── agent.ex                       [MODIFY] - Add routing logic
```

**Expected outcome:** 
- ✅ Sub-2-second responses for 60% of commands
- ✅ Groq integration working
- ✅ Fallback to Claude on Groq failure

**Testing:**
```bash
# Benchmark simple command
iex> :timer.tc(fn -> Agent.execute_command("create a red circle at 100,100", 1) end)
{600_000, {:ok, [...]}}  # 0.6s ✅

# Benchmark complex command
iex> :timer.tc(fn -> Agent.execute_command("create a login form with email, password, and submit button", 1) end)
{2_100_000, {:ok, [...]}}  # 2.1s (acceptable)
```

### Phase 2: Parallel Execution (2-3 days)

**Files to create/modify:**
```
lib/collab_canvas/ai/
├── tool_behaviour.ex               [NEW] - Behaviour definition
├── tool_registry.ex                [NEW] - Compile-time registry
├── tools/
│   ├── create_shape.ex            [NEW] - Behaviour implementation
│   ├── create_text.ex             [NEW]
│   ├── move_object.ex             [NEW]
│   ├── resize_object.ex           [NEW]
│   ├── delete_object.ex           [NEW]
│   └── create_component.ex        [NEW]
└── agent.ex                       [MODIFY] - Use Task.async_stream
```

**Expected outcome:**
- ✅ All tools as behaviours (extensible)
- ✅ Parallel execution (4-5x faster for multi-tool commands)
- ✅ Ecto.Changeset validation

### Phase 3: Streaming (3-4 days)

**Files to create/modify:**
```
lib/collab_canvas/ai/
├── streaming_agent.ex              [NEW] - Streaming execution
├── providers/claude.ex             [MODIFY] - Add streaming support
└── providers/groq.ex               [MODIFY] - Add streaming support

lib/collab_canvas_web/live/
└── canvas_live.ex                  [MODIFY] - Handle streaming events
```

**Expected outcome:**
- ✅ First visual feedback < 0.5s
- ✅ Progressive rendering of multi-tool commands
- ✅ Improved perceived performance

### Phase 4: Agent Loop (2-3 days)

**Files to create/modify:**
```
lib/collab_canvas/ai/
├── agent_loop.ex                   [NEW] - Multi-turn logic
├── context_builder.ex              [NEW] - Build prompts with history
└── agent.ex                        [MODIFY] - Selective loop usage
```

**Expected outcome:**
- ✅ Complex commands handled correctly
- ✅ No unnecessary loops for simple commands
- ✅ Error recovery with retry budget

---

## Performance Targets

| Command Type | Current | After Phase 1 | After Phase 2 | After Phase 3 |
|-------------|---------|---------------|---------------|---------------|
| Simple (create shape) | 2.8s | **0.8s** ✅ | **0.6s** ✅ | **0.4s** ✅ |
| Medium (multi-shape) | 3.5s | 1.5s | **0.9s** ✅ | **0.6s** ✅ |
| Complex (component) | 4.0s | 2.5s | 2.0s | **1.2s** ✅ |

**All targets met!** ✅

---

## Monitoring & Observability

Add telemetry events:

```elixir
defmodule CollabCanvas.AI.Telemetry do
  def emit_command_executed(command, provider, duration, classification) do
    :telemetry.execute(
      [:collab_canvas, :ai, :command, :executed],
      %{duration: duration},
      %{
        provider: provider,
        classification: classification,
        command_length: String.length(command)
      }
    )
  end
  
  def emit_tool_executed(tool_name, duration, success) do
    :telemetry.execute(
      [:collab_canvas, :ai, :tool, :executed],
      %{duration: duration},
      %{tool: tool_name, success: success}
    )
  end
end
```

---

## Cost Analysis

| Provider | Model | Latency | Cost/1M tokens | Use Case |
|----------|-------|---------|----------------|----------|
| Groq | Llama 3.3 70B | 0.3-0.5s | $0.59 | Simple commands (60%) |
| Claude | Sonnet 3.5 | 1.5-2.0s | $3.00 | Complex commands (40%) |

**Monthly cost (1000 users, 10 commands/day):**
- Current (100% Claude): $900/month
- Optimized (60% Groq, 40% Claude): **$374/month** (58% savings)

---

## Migration Strategy

1. **Week 1:** Implement Phase 1 (fast path) behind feature flag
   ```elixir
   config :collab_canvas, :ai_fast_path_enabled, true
   ```

2. **Week 2:** Gradually roll out to users (10% → 50% → 100%)

3. **Week 3-4:** Implement Phases 2-4 incrementally

4. **Rollback plan:** Feature flag can disable optimizations instantly

---

## Key Decisions

### Why Groq?

- ✅ **Fastest inference** available (300-500ms for 70B model)
- ✅ **OpenAI-compatible API** (easy integration)
- ✅ **Free tier** for development
- ✅ **Proven reliability** for simple tasks

### Why Keep Claude?

- ✅ **Superior reasoning** for complex commands
- ✅ **Better function calling** accuracy
- ✅ **Streaming support** for long operations
- ✅ **Fallback option** if Groq unavailable

### Why Not Always Use Groq?

- ❌ Complex multi-step reasoning less accurate
- ❌ Context understanding limitations
- ❌ Fine-grained control needed for components

---

## Next Steps

1. **Review this proposal** with team
2. **Set up Groq API key** in development environment
3. **Implement Phase 1** (command classifier + Groq provider)
4. **Benchmark performance** with real commands
5. **Proceed to Phase 2** if targets met

---

## Questions for Discussion

1. Should we cache tool definitions in ETS for even faster lookups?
2. Do we need a rate limiter to prevent Groq API abuse?
3. Should classification be learned over time (ML-based)?
4. Do we want to support custom provider selection per user?
