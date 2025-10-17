# Phase 1 Implementation Guide: Fast Path with Groq

## Goal
Add Groq provider for simple commands to achieve sub-2-second response times for 60% of use cases.

**Expected Outcome:** Simple commands like "create a red circle" complete in 0.6-0.8s (down from 2.8s)

---

## Prerequisites

1. **Get Groq API Key**
   ```bash
   # Sign up at https://console.groq.com/
   # Add to .env
   echo "GROQ_API_KEY=gsk_..." >> .env
   ```

2. **Install dependencies** (if needed)
   ```elixir
   # mix.exs - Req is already in deps
   {:req, "~> 0.4.0"}
   ```

---

## Step 1: Create Provider Behaviour (15 minutes)

**File:** `lib/collab_canvas/ai/provider.ex`

```elixir
defmodule CollabCanvas.AI.Provider do
  @moduledoc """
  Behaviour for LLM providers.
  
  Allows switching between different AI providers (Claude, Groq, etc.)
  based on command complexity and performance requirements.
  """
  
  @doc """
  Calls the LLM provider with a command and tool definitions.
  
  Returns {:ok, tool_calls} or {:error, reason}
  """
  @callback call(
    command :: String.t(),
    tools :: list(map()),
    opts :: keyword()
  ) :: {:ok, list(map())} | {:error, term()}
  
  @doc "Returns the model name used by this provider"
  @callback model_name() :: String.t()
  
  @doc "Returns average latency in milliseconds"
  @callback avg_latency() :: integer()
  
  @doc "Returns max tokens for this provider"
  @callback max_tokens() :: integer()
end
```

---

## Step 2: Create Groq Provider (30 minutes)

**File:** `lib/collab_canvas/ai/providers/groq.ex`

```elixir
defmodule CollabCanvas.AI.Providers.Groq do
  @moduledoc """
  Groq provider for fast inference with Llama 3.3 70B.
  
  Optimized for simple, single-turn commands with 300-500ms latency.
  Uses OpenAI-compatible API format.
  """
  
  @behaviour CollabCanvas.AI.Provider
  
  require Logger
  
  @api_url "https://api.groq.com/openai/v1/chat/completions"
  @model "llama-3.3-70b-versatile"
  
  @impl true
  def call(command, tools, _opts \\ []) do
    api_key = get_api_key()
    
    if is_nil(api_key) or api_key == "" do
      {:error, :missing_api_key}
    else
      body = build_request_body(command, tools)
      headers = build_headers(api_key)
      
      case Req.post(@api_url, json: body, headers: headers) do
        {:ok, %{status: 200, body: response}} ->
          parse_response(response)
          
        {:ok, %{status: status, body: error_body}} ->
          Logger.error("Groq API error: #{status} - #{inspect(error_body)}")
          {:error, {:api_error, status, error_body}}
          
        {:error, reason} ->
          Logger.error("Groq API request failed: #{inspect(reason)}")
          {:error, {:request_failed, reason}}
      end
    end
  end
  
  @impl true
  def model_name, do: @model
  
  @impl true
  def avg_latency, do: 400  # 400ms average
  
  @impl true
  def max_tokens, do: 1024
  
  # Private functions
  
  defp get_api_key do
    System.get_env("GROQ_API_KEY")
  end
  
  defp build_headers(api_key) do
    [
      {"authorization", "Bearer #{api_key}"},
      {"content-type", "application/json"}
    ]
  end
  
  defp build_request_body(command, tools) do
    %{
      model: @model,
      messages: [
        %{
          role: "system",
          content: "You are a canvas design assistant. Use the provided tools to execute user commands precisely. Always use exact coordinates and dimensions provided."
        },
        %{
          role: "user",
          content: command
        }
      ],
      tools: convert_tools_to_openai_format(tools),
      tool_choice: "auto",
      temperature: 0.1,  # Low temperature for consistency
      max_tokens: @max_tokens
    }
  end
  
  defp convert_tools_to_openai_format(tools) do
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
    tool_calls = Map.get(message, "tool_calls", [])
    
    if Enum.empty?(tool_calls) do
      # No tool calls - just text response
      {:ok, []}
    else
      parsed_calls = Enum.map(tool_calls, &parse_tool_call/1)
      {:ok, parsed_calls}
    end
  end
  
  defp parse_response(response) do
    Logger.error("Unexpected Groq response format: #{inspect(response)}")
    {:error, :invalid_response_format}
  end
  
  defp parse_tool_call(tool_call) do
    function = tool_call["function"]
    
    %{
      id: tool_call["id"],
      name: function["name"],
      input: Jason.decode!(function["arguments"])
    }
  end
end
```

**Test it:**

```elixir
# In IEx
iex> alias CollabCanvas.AI.Providers.Groq
iex> alias CollabCanvas.AI.Tools
iex> Groq.call("create a red circle at 100,100", Tools.get_tool_definitions())
{:ok, [%{id: "call_...", name: "create_shape", input: %{"type" => "circle", ...}}]}
```

---

## Step 3: Refactor Claude Provider (20 minutes)

**File:** `lib/collab_canvas/ai/providers/claude.ex`

```elixir
defmodule CollabCanvas.AI.Providers.Claude do
  @moduledoc """
  Anthropic Claude provider for complex reasoning tasks.
  
  Used for multi-step commands, component creation, and ambiguous requests.
  """
  
  @behaviour CollabCanvas.AI.Provider
  
  require Logger
  
  @api_url "https://api.anthropic.com/v1/messages"
  @model "claude-3-5-sonnet-20241022"
  @api_version "2023-06-01"
  
  @impl true
  def call(command, tools, _opts \\ []) do
    api_key = get_api_key()
    
    if is_nil(api_key) or api_key == "" do
      {:error, :missing_api_key}
    else
      headers = [
        {"x-api-key", api_key},
        {"anthropic-version", @api_version},
        {"content-type", "application/json"}
      ]
      
      body = %{
        model: @model,
        max_tokens: 1024,
        tools: tools,
        messages: [
          %{
            role: "user",
            content: command
          }
        ]
      }
      
      case Req.post(@api_url, json: body, headers: headers) do
        {:ok, %{status: 200, body: response}} ->
          parse_response(response)
          
        {:ok, %{status: status, body: error_body}} ->
          Logger.error("Claude API error: #{status} - #{inspect(error_body)}")
          {:error, {:api_error, status, error_body}}
          
        {:error, reason} ->
          Logger.error("Claude API request failed: #{inspect(reason)}")
          {:error, {:request_failed, reason}}
      end
    end
  end
  
  @impl true
  def model_name, do: @model
  
  @impl true
  def avg_latency, do: 1800  # 1.8s average
  
  @impl true
  def max_tokens, do: 1024
  
  # Private functions
  
  defp get_api_key do
    System.get_env("CLAUDE_API_KEY")
  end
  
  defp parse_response(%{"content" => content, "stop_reason" => stop_reason}) do
    case stop_reason do
      "tool_use" ->
        tool_calls =
          content
          |> Enum.filter(fn item -> item["type"] == "tool_use" end)
          |> Enum.map(fn tool_use ->
            %{
              id: tool_use["id"],
              name: tool_use["name"],
              input: tool_use["input"]
            }
          end)
        
        {:ok, tool_calls}
      
      "end_turn" ->
        {:ok, []}
      
      other ->
        Logger.warning("Unexpected stop_reason: #{other}")
        {:ok, []}
    end
  end
  
  defp parse_response(response) do
    Logger.error("Unexpected Claude response format: #{inspect(response)}")
    {:error, :invalid_response_format}
  end
end
```

---

## Step 4: Create Command Classifier (25 minutes)

**File:** `lib/collab_canvas/ai/command_classifier.ex`

```elixir
defmodule CollabCanvas.AI.CommandClassifier do
  @moduledoc """
  Classifies commands to route them to the optimal execution path.
  
  - Fast Path: Simple, single-operation commands → Groq (300-500ms)
  - Complex Path: Multi-step, ambiguous commands → Claude (1.5-2s)
  """
  
  require Logger
  
  @type classification :: :fast_path | :complex_path
  
  # Pattern-based classification
  @simple_patterns [
    # Single shape creation
    ~r/^create (a|an) \w+ (circle|rectangle|square|triangle)/i,
    ~r/^make (a|an) \w+ (circle|rectangle|square|triangle)/i,
    ~r/^add (a|an) (circle|rectangle|square|triangle)/i,
    
    # Simple text
    ~r/^(create|add|make) (a|an) ?\w* text/i,
    
    # Move operations
    ~r/^move .+ to \d+,\s*\d+/i,
    ~r/^move .+ by \d+,\s*\d+/i,
    
    # Resize operations
    ~r/^resize .+ to \d+x\d+/i,
    ~r/^make .+ \d+x\d+ (pixels|px)?/i,
    
    # Delete operations
    ~r/^delete (object|shape|item) \w+/i,
    ~r/^remove (object|shape|item) \w+/i
  ]
  
  @doc """
  Classifies a command as :fast_path or :complex_path.
  
  ## Examples
  
      iex> classify("create a red circle at 100,100")
      :fast_path
      
      iex> classify("create a login form with email and password")
      :complex_path
      
      iex> classify("arrange these objects in a grid")
      :complex_path
  """
  @spec classify(String.t()) :: classification()
  def classify(command) when is_binary(command) do
    cond do
      simple_pattern_match?(command) ->
        log_classification(command, :fast_path, "pattern_match")
        :fast_path
      
      contains_multiple_operations?(command) ->
        log_classification(command, :complex_path, "multiple_ops")
        :complex_path
      
      requires_context?(command) ->
        log_classification(command, :complex_path, "requires_context")
        :complex_path
      
      is_component_request?(command) ->
        log_classification(command, :complex_path, "component")
        :complex_path
      
      is_layout_request?(command) ->
        log_classification(command, :complex_path, "layout")
        :complex_path
      
      true ->
        # Default to fast path for unknown patterns
        log_classification(command, :fast_path, "default")
        :fast_path
    end
  end
  
  # Check if command matches simple patterns
  defp simple_pattern_match?(command) do
    Enum.any?(@simple_patterns, &Regex.match?(&1, command))
  end
  
  # Detect multiple operations in a single command
  defp contains_multiple_operations?(command) do
    command_lower = String.downcase(command)
    
    # Count action verbs
    verbs = ["create", "move", "delete", "resize", "add", "make", "remove"]
    verb_count = Enum.count(verbs, &String.contains?(command_lower, &1))
    
    # Count conjunctions
    has_conjunction = 
      String.contains?(command_lower, " and ") ||
      String.contains?(command_lower, " then ") ||
      String.contains?(command_lower, " with ")
    
    verb_count > 1 || (verb_count >= 1 && has_conjunction)
  end
  
  # Check if command references context (selected objects, "this", "that")
  defp requires_context?(command) do
    command_lower = String.downcase(command)
    
    context_words = ["this", "that", "these", "those", "selected", "them"]
    Enum.any?(context_words, &String.contains?(command_lower, &1))
  end
  
  # Detect component creation requests
  defp is_component_request?(command) do
    command_lower = String.downcase(command)
    
    components = [
      "login form", "signup form", "form",
      "navbar", "nav bar", "navigation",
      "sidebar", "side bar",
      "card", "button group",
      "dashboard", "layout"
    ]
    
    Enum.any?(components, &String.contains?(command_lower, &1))
  end
  
  # Detect layout/arrangement requests
  defp is_layout_request?(command) do
    command_lower = String.downcase(command)
    
    layout_keywords = [
      "arrange", "align", "distribute", "space",
      "grid", "row", "column", "stack",
      "center", "organize"
    ]
    
    Enum.any?(layout_keywords, &String.contains?(command_lower, &1))
  end
  
  # Log classification for monitoring
  defp log_classification(command, classification, reason) do
    Logger.debug("""
    Command Classification:
    - Command: #{String.slice(command, 0..50)}...
    - Classification: #{classification}
    - Reason: #{reason}
    """)
  end
end
```

**Test it:**

```elixir
iex> alias CollabCanvas.AI.CommandClassifier
iex> CommandClassifier.classify("create a red circle at 100,100")
:fast_path

iex> CommandClassifier.classify("create a login form")
:complex_path

iex> CommandClassifier.classify("arrange these in a grid")
:complex_path
```

---

## Step 5: Update Agent Module (30 minutes)

**File:** `lib/collab_canvas/ai/agent.ex` (modifications)

```elixir
defmodule CollabCanvas.AI.Agent do
  require Logger
  alias CollabCanvas.Canvases
  alias CollabCanvas.AI.{Tools, CommandClassifier, ComponentBuilder}
  alias CollabCanvas.AI.Providers.{Groq, Claude}
  
  # ... keep existing module docs ...
  
  @doc """
  Executes a natural language command with optimal provider selection.
  
  Routes simple commands to Groq (fast) and complex commands to Claude (accurate).
  """
  def execute_command(command, canvas_id, opts \\ []) do
    # Verify canvas exists
    case Canvases.get_canvas(canvas_id) do
      nil ->
        {:error, :canvas_not_found}
      
      _canvas ->
        # Classify command and select provider
        classification = CommandClassifier.classify(command)
        provider = select_provider(classification, opts)
        
        Logger.info("""
        Executing AI command:
        - Classification: #{classification}
        - Provider: #{inspect(provider)}
        - Command: #{command}
        """)
        
        # Call LLM provider
        start_time = System.monotonic_time(:millisecond)
        
        case provider.call(command, Tools.get_tool_definitions(), opts) do
          {:ok, tool_calls} ->
            api_latency = System.monotonic_time(:millisecond) - start_time
            Logger.info("API latency: #{api_latency}ms")
            
            # Process tool calls
            results = process_tool_calls(tool_calls, canvas_id)
            
            total_latency = System.monotonic_time(:millisecond) - start_time
            Logger.info("Total latency: #{total_latency}ms")
            
            {:ok, results}
          
          {:error, reason} ->
            # Fallback to Claude if Groq fails
            if provider == Groq do
              Logger.warning("Groq failed (#{inspect(reason)}), falling back to Claude")
              execute_with_provider(command, canvas_id, Claude, opts)
            else
              {:error, reason}
            end
        end
    end
  end
  
  # Select provider based on classification
  defp select_provider(:fast_path, opts) do
    # Allow override via opts
    Keyword.get(opts, :provider, Groq)
  end
  
  defp select_provider(:complex_path, _opts) do
    # Always use Claude for complex commands
    Claude
  end
  
  # Execute with specific provider (for fallback)
  defp execute_with_provider(command, canvas_id, provider, opts) do
    case provider.call(command, Tools.get_tool_definitions(), opts) do
      {:ok, tool_calls} ->
        results = process_tool_calls(tool_calls, canvas_id)
        {:ok, results}
      
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  # ... keep existing process_tool_calls, execute_tool_call, etc. ...
end
```

---

## Step 6: Add Configuration (5 minutes)

**File:** `config/config.exs`

```elixir
# AI Provider Configuration
config :collab_canvas, :ai,
  # Default provider for simple commands
  default_provider: CollabCanvas.AI.Providers.Groq,
  
  # Fallback provider if default fails
  fallback_provider: CollabCanvas.AI.Providers.Claude,
  
  # Feature flag to enable/disable fast path
  fast_path_enabled: true,
  
  # Timeout for API calls (milliseconds)
  api_timeout: 10_000
```

**File:** `config/test.exs`

```elixir
# Use Claude by default in tests for deterministic results
config :collab_canvas, :ai,
  default_provider: CollabCanvas.AI.Providers.Claude,
  fast_path_enabled: false
```

---

## Step 7: Add Tests (30 minutes)

**File:** `test/collab_canvas/ai/command_classifier_test.exs`

```elixir
defmodule CollabCanvas.AI.CommandClassifierTest do
  use ExUnit.Case, async: true
  
  alias CollabCanvas.AI.CommandClassifier
  
  describe "classify/1 - fast path" do
    test "simple shape creation" do
      assert :fast_path == CommandClassifier.classify("create a red circle")
      assert :fast_path == CommandClassifier.classify("make a blue rectangle")
      assert :fast_path == CommandClassifier.classify("add a green square")
    end
    
    test "simple text creation" do
      assert :fast_path == CommandClassifier.classify("create text saying Hello")
      assert :fast_path == CommandClassifier.classify("add text")
    end
    
    test "move operations" do
      assert :fast_path == CommandClassifier.classify("move object 123 to 100,200")
    end
    
    test "resize operations" do
      assert :fast_path == CommandClassifier.classify("resize shape to 200x300")
    end
    
    test "delete operations" do
      assert :fast_path == CommandClassifier.classify("delete object abc")
    end
  end
  
  describe "classify/1 - complex path" do
    test "component creation" do
      assert :complex_path == CommandClassifier.classify("create a login form")
      assert :complex_path == CommandClassifier.classify("make a navbar with 5 items")
    end
    
    test "multiple operations" do
      assert :complex_path == CommandClassifier.classify("create a circle and a square")
      assert :complex_path == CommandClassifier.classify("create a button then move it")
    end
    
    test "layout operations" do
      assert :complex_path == CommandClassifier.classify("arrange these in a grid")
      assert :complex_path == CommandClassifier.classify("align these to the left")
    end
    
    test "context-dependent" do
      assert :complex_path == CommandClassifier.classify("move these objects")
      assert :complex_path == CommandClassifier.classify("delete this shape")
    end
  end
end
```

**File:** `test/collab_canvas/ai/providers/groq_test.exs`

```elixir
defmodule CollabCanvas.AI.Providers.GroqTest do
  use CollabCanvas.DataCase, async: true
  
  alias CollabCanvas.AI.Providers.Groq
  alias CollabCanvas.AI.Tools
  
  @moduletag :external_api
  
  describe "call/3" do
    @tag :skip  # Only run when GROQ_API_KEY is set
    test "creates a shape with valid command" do
      command = "create a red circle at 100,100 with width 50"
      tools = Tools.get_tool_definitions()
      
      assert {:ok, tool_calls} = Groq.call(command, tools)
      assert [%{name: "create_shape", input: input}] = tool_calls
      assert input["type"] == "circle"
      assert input["x"] == 100
      assert input["y"] == 100
    end
    
    test "returns error when API key missing" do
      System.delete_env("GROQ_API_KEY")
      
      assert {:error, :missing_api_key} = 
        Groq.call("create shape", Tools.get_tool_definitions())
    end
  end
  
  describe "model_name/0" do
    test "returns the correct model" do
      assert "llama-3.3-70b-versatile" == Groq.model_name()
    end
  end
  
  describe "avg_latency/0" do
    test "returns expected latency" do
      assert 400 == Groq.avg_latency()
    end
  end
end
```

---

## Step 8: Integration Test (15 minutes)

**File:** `test/collab_canvas/ai/agent_integration_test.exs`

```elixir
defmodule CollabCanvas.AI.AgentIntegrationTest do
  use CollabCanvas.DataCase
  
  alias CollabCanvas.AI.Agent
  alias CollabCanvas.{Canvases, Repo}
  
  setup do
    # Create test canvas
    {:ok, canvas} = Canvases.create_canvas(%{name: "Test Canvas"})
    %{canvas: canvas}
  end
  
  @tag :external_api
  @tag :skip
  describe "execute_command/3 - fast path" do
    test "creates shape with Groq in under 1 second", %{canvas: canvas} do
      command = "create a red circle at 100,100"
      
      {time, {:ok, results}} = 
        :timer.tc(fn -> Agent.execute_command(command, canvas.id) end)
      
      # Should be under 1 second (1_000_000 microseconds)
      assert time < 1_000_000, "Expected < 1s, got #{time / 1000}ms"
      
      assert [%{tool: "create_shape", result: {:ok, object}}] = results
      assert object.type == "circle"
    end
  end
  
  @tag :external_api
  @tag :skip
  describe "execute_command/3 - complex path" do
    test "creates component with Claude", %{canvas: canvas} do
      command = "create a login form"
      
      {time, {:ok, results}} = 
        :timer.tc(fn -> Agent.execute_command(command, canvas.id) end)
      
      # May take longer but should complete
      assert time < 5_000_000, "Expected < 5s, got #{time / 1000}ms"
      
      assert [%{tool: "create_component"}] = results
    end
  end
end
```

---

## Step 9: Deploy & Monitor (10 minutes)

1. **Add environment variables:**

```bash
# In production
fly secrets set GROQ_API_KEY="gsk_..."
```

2. **Enable feature flag:**

```elixir
# config/prod.exs
config :collab_canvas, :ai,
  fast_path_enabled: true,
  default_provider: CollabCanvas.AI.Providers.Groq
```

3. **Add Telemetry (optional but recommended):**

```elixir
# In Agent.execute_command/3, after completion:
:telemetry.execute(
  [:collab_canvas, :ai, :command],
  %{duration: total_latency},
  %{
    classification: classification,
    provider: inspect(provider),
    success: true
  }
)
```

---

## Verification Checklist

- [ ] Groq API key configured in `.env`
- [ ] All files created and code compiles
- [ ] Unit tests pass: `mix test test/collab_canvas/ai/command_classifier_test.exs`
- [ ] Provider tests pass (with API keys): `mix test --only external_api`
- [ ] Simple command in IEx: `Agent.execute_command("create a red circle at 100,100", canvas_id)` completes in < 1s
- [ ] Complex command still works: `Agent.execute_command("create a login form", canvas_id)`
- [ ] Fallback works: Disable Groq key, verify Claude fallback
- [ ] LiveView integration works: Test in browser

---

## Expected Performance Improvements

**Before Phase 1:**
```
Simple command: 2.8-3.5s
Complex command: 3.5-4.0s
```

**After Phase 1:**
```
Simple command: 0.6-0.8s ⚡ (75% improvement)
Complex command: 2.0-2.5s (minor improvement from refactoring)
```

---

## Troubleshooting

**Issue: Groq returns errors**
```elixir
# Check API key
System.get_env("GROQ_API_KEY")

# Enable debug logging
config :logger, level: :debug
```

**Issue: Classification wrong**
```elixir
# Test classifier directly
CommandClassifier.classify("your command here")

# Add pattern to @simple_patterns if needed
```

**Issue: Groq doesn't understand tools**
```elixir
# Verify tool format conversion
Groq.convert_tools_to_openai_format(Tools.get_tool_definitions())
|> IO.inspect()
```

---

## Next Steps

After Phase 1 is complete and verified:

1. **Collect metrics** on classification accuracy
2. **Tune patterns** in CommandClassifier based on real usage
3. **Proceed to Phase 2:** Parallel tool execution
4. **Measure cost savings:** Track Groq vs Claude usage

---

## Time Estimate

Total implementation time: **2-3 hours**

- File creation: 1.5 hours
- Testing: 45 minutes
- Integration & debugging: 30 minutes
