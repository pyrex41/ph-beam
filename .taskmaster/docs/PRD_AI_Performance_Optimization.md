# PRD: AI Agent Performance Optimization

## Executive Summary

Optimize the AI agent system to achieve sub-2-second response times for most commands by using Groq's fast inference as the primary LLM provider, with intelligent command routing and parallel execution.

**Current State:** 2.8-3.5 seconds average response time (Claude-only)
**Target State:** 0.6-0.8 seconds for simple commands (70% of use cases)

---

## Performance Requirements

### Critical Targets (Must-Have)

- **Simple Commands:** < 1 second end-to-end (create shapes, move, delete)
- **Multi-Tool Commands:** < 1.5 seconds (create multiple objects in one command)
- **Layout Commands:** < 2 seconds (arrange objects, alignment)
- **Complex Components:** < 2.5 seconds (login forms, navbars, dashboards)

### Performance Breakdown

| Command Type | Current | Target | Provider |
|-------------|---------|--------|----------|
| Single shape | 2.8s | **0.6s** | Groq |
| 3-5 shapes | 3.5s | **1.2s** | Groq |
| Layout/arrange | 4.0s | **1.8s** | Groq |
| Complex component | 4.5s | **2.3s** | Claude (fallback) |

### Success Metrics

- 70% of commands complete in < 1 second
- 90% of commands complete in < 2 seconds
- 100% of commands complete in < 3 seconds
- Zero increase in error rate
- 50%+ cost reduction (Groq vs Claude pricing)

---

## Architecture Changes

### 1. Command Classification System

**Purpose:** Route commands to the optimal LLM provider based on complexity

**Classification Types:**

```
:fast_path
- Single-operation commands
- Clear, unambiguous intent
- No context required
- Pattern-matchable
→ Route to Groq (300-500ms latency)

:complex_path (rare)
- Multi-step reasoning required
- Ambiguous or contextual
- Component creation with many parts
→ Route to Claude (only if needed)
```

**Implementation:**

```elixir
defmodule CollabCanvas.AI.CommandClassifier do
  # Pattern-based classification using regex
  @simple_patterns [
    ~r/^create (a|an) \w+ (circle|rectangle|square)/i,
    ~r/^move .+ to \d+,\s*\d+/i,
    ~r/^delete (object|shape) \w+/i,
    # ... more patterns
  ]
  
  def classify(command) do
    cond do
      simple_pattern_match?(command) -> :fast_path
      contains_multiple_operations?(command) -> :complex_path
      requires_context?(command) -> :complex_path
      true -> :fast_path  # Default to fast
    end
  end
end
```

**Expected Distribution:**
- 70% → :fast_path (Groq)
- 30% → :complex_path (Groq, Claude fallback if needed)

---

### 2. Provider Abstraction Layer

**Purpose:** Support multiple LLM providers with consistent interface

**Providers:**

1. **Groq (Primary)**
   - Model: `llama-3.3-70b-versatile`
   - Latency: 300-500ms
   - Use case: All simple commands (70%+)
   - API: OpenAI-compatible

2. **Claude (Fallback Only)**
   - Model: `claude-3-5-sonnet-20241022`
   - Latency: 1.5-2.0s
   - Use case: Only if Groq fails or extremely complex
   - API: Anthropic format

**Implementation:**

```elixir
defmodule CollabCanvas.AI.Provider do
  @callback call(command :: String.t(), tools :: list(), opts :: keyword()) ::
    {:ok, list()} | {:error, term()}
  
  @callback model_name() :: String.t()
  @callback avg_latency() :: integer()
end

# Groq provider using OpenAI-compatible API
defmodule CollabCanvas.AI.Providers.Groq do
  @behaviour CollabCanvas.AI.Provider
  @model "llama-3.3-70b-versatile"
  
  def call(command, tools, _opts) do
    # Convert tools to OpenAI format
    # Call Groq API
    # Parse response
  end
  
  def avg_latency, do: 400
end
```

**Provider Selection Strategy:**

```
Command → Classify → Select Provider
                    ↓
              :fast_path → Groq
              :complex_path → Groq (with Claude fallback)
                            ↓
                     If Groq fails → Claude
```

---

### 3. Parallel Tool Execution

**Purpose:** Execute multiple tool calls concurrently instead of sequentially

**Current Problem:**

```elixir
# Sequential execution (SLOW)
Enum.map(tool_calls, fn tool -> 
  execute_tool(tool)  # 200ms each
end)
# 5 tools = 1000ms total
```

**Solution:**

```elixir
# Parallel execution (FAST)
Task.async_stream(tool_calls, fn tool ->
  execute_tool(tool)  # All run concurrently
end, max_concurrency: 10)
# 5 tools = 250ms total (4x faster)
```

**Expected Impact:**
- 5 tools: 1000ms → 250ms (75% reduction)
- 10 tools: 2000ms → 300ms (85% reduction)

---

### 4. Tool Behaviour System

**Purpose:** Modular, extensible, type-safe tool system

**Benefits:**
- O(1) tool lookup via compile-time map
- Ecto.Changeset validation
- Easy to add new tools
- Type safety

**Implementation:**

```elixir
defmodule CollabCanvas.AI.ToolBehaviour do
  @callback schema() :: map()
  @callback validate(input :: map()) :: {:ok, map()} | {:error, term()}
  @callback execute(input :: map(), canvas_id :: integer(), context :: map()) ::
    {:ok, term()} | {:error, term()}
end

# Each tool implements the behaviour
defmodule CollabCanvas.AI.Tools.CreateShape do
  @behaviour CollabCanvas.AI.ToolBehaviour
  use Ecto.Schema
  
  embedded_schema do
    field :type, Ecto.Enum, values: [:rectangle, :circle]
    field :x, :float
    field :y, :float
    field :width, :float
    # ...
  end
  
  def validate(input), do: # Ecto validation
  def execute(input, canvas_id, _ctx), do: # Create object
end

# Registry with compile-time map
defmodule CollabCanvas.AI.ToolRegistry do
  @tools [CreateShape, MoveObject, DeleteObject, ...]
  @tool_map Map.new(@tools, fn t -> {t.schema().name, t} end)
  
  def get_tool(name), do: Map.get(@tool_map, name)  # O(1)
  def execute_tool(name, input, canvas_id) do
    get_tool(name).execute(input, canvas_id, %{})
  end
end
```

---

## Implementation Phases

### Phase 1: Fast Path with Groq (1-2 days) 🚀

**Goal:** Get 70% of commands under 1 second

**Tasks:**
1. Create `CommandClassifier` module
2. Create `Provider` behaviour and `Groq` provider
3. Update `Agent` to route commands
4. Add Groq API key configuration
5. Test and validate performance

**Files:**
- `lib/collab_canvas/ai/command_classifier.ex` (NEW)
- `lib/collab_canvas/ai/provider.ex` (NEW)
- `lib/collab_canvas/ai/providers/groq.ex` (NEW)
- `lib/collab_canvas/ai/agent.ex` (MODIFY)

**Expected Outcome:**
- Simple commands: 2.8s → **0.6-0.8s** ✅
- 70% of commands meet target
- Cost reduction: 50%+

**Validation:**
```bash
# Benchmark simple command
iex> :timer.tc(fn -> Agent.execute_command("create a red circle", canvas_id) end)
{650_000, {:ok, [...]}}  # 0.65s ✅
```

---

### Phase 2: Parallel Execution (2-3 days)

**Goal:** Speed up multi-tool commands by 4-5x

**Tasks:**
1. Create `ToolBehaviour` with callbacks
2. Create `ToolRegistry` with compile-time map
3. Refactor existing tools to behaviours:
   - CreateShape
   - CreateText
   - MoveObject
   - ResizeObject
   - DeleteObject
   - CreateComponent
4. Update `Agent` to use `Task.async_stream`
5. Add Ecto validation to all tools

**Files:**
- `lib/collab_canvas/ai/tool_behaviour.ex` (NEW)
- `lib/collab_canvas/ai/tool_registry.ex` (NEW)
- `lib/collab_canvas/ai/tools/*.ex` (REFACTOR into separate modules)
- `lib/collab_canvas/ai/agent.ex` (MODIFY for parallel execution)

**Expected Outcome:**
- Multi-tool commands: 3.5s → **0.9-1.2s** ✅
- 90% of commands meet target
- Extensible tool system

**Validation:**
```bash
# Benchmark 5-tool command
iex> cmd = "create a red circle, blue square, green text, yellow triangle, and purple rectangle"
iex> :timer.tc(fn -> Agent.execute_command(cmd, canvas_id) end)
{1_100_000, {:ok, [...]}}  # 1.1s for 5 tools ✅
```

---

### Phase 3: Streaming Responses (Optional - 3-4 days)

**Goal:** Show first visual feedback in < 0.5s

**Tasks:**
1. Add streaming support to Groq provider
2. Create `StreamingAgent` module
3. Update LiveView to handle incremental updates
4. Add progress indicators in UI

**Files:**
- `lib/collab_canvas/ai/streaming_agent.ex` (NEW)
- `lib/collab_canvas/ai/providers/groq.ex` (MODIFY for streaming)
- `lib/collab_canvas_web/live/canvas_live.ex` (MODIFY)

**Expected Outcome:**
- Time to first feedback: **< 0.5s**
- Perceived performance greatly improved
- Better UX for complex commands

**Note:** This is a nice-to-have. Phase 1-2 already meet all performance targets.

---

### Phase 4: Layout Tools (2-3 days)

**Goal:** Add AI-powered layout commands

**Tasks:**
1. Create `Layout` module with algorithms
2. Add `ArrangeObjects` tool
3. Add layout-specific patterns to classifier
4. Test with various layouts

**Files:**
- `lib/collab_canvas/ai/layout.ex` (NEW)
- `lib/collab_canvas/ai/tools/arrange_objects.ex` (NEW)

**Expected Outcome:**
- "arrange in grid", "align left", etc. work
- Layout commands: **< 2s**
- Groq handles most layouts

---

## Tool Definitions (Updated)

### Core Tools (Phase 1-2)

1. **create_shape**
   - Creates rectangles, circles, triangles
   - Params: type, x, y, width, height, fill, stroke
   - Latency: ~150ms

2. **create_text**
   - Adds text to canvas
   - Params: text, x, y, font_size, color
   - Latency: ~120ms

3. **move_object**
   - Moves existing object
   - Params: object_id, x, y
   - Latency: ~100ms

4. **resize_object**
   - Resizes existing object
   - Params: object_id, width, height
   - Latency: ~100ms

5. **delete_object**
   - Removes object
   - Params: object_id
   - Latency: ~80ms

6. **create_component**
   - Creates UI components (login, navbar, etc.)
   - Params: type, x, y, width, height, theme, content
   - Latency: ~300ms (creates multiple objects)

### Layout Tools (Phase 4)

7. **arrange_objects**
   - Arranges multiple objects in layouts
   - Params: object_ids, layout_type, spacing, alignment
   - Layouts: horizontal, vertical, grid, circular, stack
   - Latency: ~200ms

8. **align_objects**
   - Aligns objects to each other or canvas
   - Params: object_ids, alignment (left, center, right, top, middle, bottom)
   - Latency: ~150ms

---

## Configuration

### Environment Variables

```bash
# Primary LLM (Groq)
GROQ_API_KEY=gsk_...

# Fallback LLM (Claude - optional)
CLAUDE_API_KEY=sk-ant-...  # Only if needed for fallback
```

### Application Config

```elixir
# config/config.exs
config :collab_canvas, :ai,
  # Primary provider
  default_provider: CollabCanvas.AI.Providers.Groq,
  
  # Fallback provider (optional)
  fallback_provider: CollabCanvas.AI.Providers.Claude,
  
  # Enable/disable fast path
  fast_path_enabled: true,
  
  # API timeouts
  groq_timeout: 5_000,
  claude_timeout: 10_000
```

---

## Testing Strategy

### Unit Tests

```elixir
# CommandClassifier tests
test "classifies simple commands as fast_path"
test "classifies complex commands as complex_path"

# Groq provider tests
test "calls Groq API successfully"
test "converts tools to OpenAI format"
test "parses Groq response correctly"

# Tool behaviour tests
test "validates input with Ecto"
test "executes tool successfully"
test "returns error for invalid input"
```

### Integration Tests

```elixir
# Performance tests
test "simple command completes in < 1s" do
  {time, result} = :timer.tc(fn -> 
    Agent.execute_command("create a circle", canvas_id)
  end)
  assert time < 1_000_000  # microseconds
end

# Fallback tests
test "falls back to Claude when Groq fails"

# Parallel execution tests
test "executes 5 tools in parallel under 500ms"
```

### Manual Testing

**Simple Commands (Target: < 1s)**
- [ ] "create a red circle at 100,100"
- [ ] "create a blue rectangle at 200,200"
- [ ] "move object 123 to 50,50"
- [ ] "delete shape abc"
- [ ] "resize object 456 to 200x300"

**Multi-Tool Commands (Target: < 1.5s)**
- [ ] "create a red circle and a blue square"
- [ ] "create 5 different colored circles"

**Layout Commands (Target: < 2s)**
- [ ] "arrange these in a horizontal row"
- [ ] "align these to the left"

**Complex Commands (Target: < 2.5s)**
- [ ] "create a login form"
- [ ] "create a navbar with 5 menu items"

---

## Performance Monitoring

### Telemetry Events

```elixir
# Emit events for monitoring
:telemetry.execute(
  [:collab_canvas, :ai, :command, :executed],
  %{duration: duration_ms},
  %{
    classification: :fast_path,
    provider: "groq",
    tool_count: 3,
    success: true
  }
)
```

### Metrics to Track

- **Average latency by command type**
- **Provider usage distribution** (Groq vs Claude)
- **Fallback rate** (how often Groq fails)
- **Classification accuracy** (manual review)
- **Cost per 1000 commands**
- **Error rate by provider**

### Dashboards

Create simple dashboard to track:
1. Response time percentiles (p50, p90, p99)
2. Provider selection breakdown
3. Cost tracking
4. Error rates

---

## Rollout Strategy

### Week 1: Phase 1 Implementation
- Implement command classifier
- Add Groq provider
- Test with 10% of traffic
- Monitor performance and errors

### Week 2: Phase 1 Full Rollout
- Roll out to 100% of users
- Validate performance targets met
- Collect usage data

### Week 3: Phase 2 Implementation
- Refactor tools to behaviours
- Implement parallel execution
- Test with 10% of traffic

### Week 4: Phase 2 Full Rollout
- Roll out to 100% of users
- Validate multi-tool performance
- Collect feedback

### Week 5+: Phase 3-4 (Optional)
- Implement streaming if needed
- Add layout tools
- Continuous optimization

---

## Risk Mitigation

### Risk: Groq API Unreliable

**Mitigation:**
- Automatic fallback to Claude
- Retry logic with exponential backoff
- Feature flag to disable Groq entirely

### Risk: Classification Inaccuracy

**Mitigation:**
- Conservative classification (default to fast_path)
- Easy to add new patterns
- Manual override in debug mode
- Telemetry to track misclassifications

### Risk: Groq Can't Handle Some Commands

**Mitigation:**
- Automatic fallback to Claude on Groq failure
- Track failure patterns
- Update classifier to route known failures to Claude

### Risk: Parallel Execution Bugs

**Mitigation:**
- Comprehensive tests
- Timeout handling (5s per tool)
- Error isolation (one tool failure doesn't break others)
- Easy rollback to sequential execution

---

## Success Criteria

### Must Have (Phase 1-2)

- ✅ 70% of commands complete in < 1 second
- ✅ 90% of commands complete in < 2 seconds
- ✅ No increase in error rate
- ✅ 50%+ cost reduction
- ✅ All existing functionality preserved

### Nice to Have (Phase 3-4)

- Time to first visual feedback < 0.5s
- Layout commands working
- Streaming responses
- Classification accuracy > 90%

---

## Cost Analysis

### Current State (100% Claude)

```
Model: Claude 3.5 Sonnet
Input: $3.00 / 1M tokens
Output: $15.00 / 1M tokens

Assumptions:
- 1000 users
- 10 commands/day each
- 300 tokens/command average
- 30 days/month

Monthly cost:
1000 users × 10 cmd/day × 30 days × 300 tokens × $3.00/1M
= 10,000 commands/day × 30 days × 300 tokens × $3.00/1M
= 300,000 commands × 300 tokens × $3.00/1M
= 90M tokens × $3.00/1M
= $270/month (input only)
```

### Optimized State (70% Groq, 30% Claude)

```
Groq:
- Model: Llama 3.3 70B
- Cost: $0.59/1M input, $0.79/1M output

Claude (fallback):
- Same as above

70% Groq: 210,000 commands
- 210,000 × 300 tokens × $0.59/1M = $37/month

30% Claude: 90,000 commands  
- 90,000 × 300 tokens × $3.00/1M = $81/month

Total: $37 + $81 = $118/month
Savings: $270 - $118 = $152/month (56% reduction)
```

### At Scale (10,000 users)

```
Current: $2,700/month
Optimized: $1,180/month
Savings: $1,520/month (56% reduction)
```

---

## Appendix: Command Examples by Classification

### Fast Path (Groq)

**Single Operations:**
- "create a red circle at 100,100"
- "create a blue rectangle at 200,200 with width 150 and height 100"
- "create text saying 'Hello World' at 50,50"
- "move object abc123 to 300,400"
- "resize shape xyz789 to 200x200"
- "delete object def456"

**Clear Multi-Operations:**
- "create a red circle and a blue square"
- "create 3 rectangles at 100,100, 200,200, and 300,300"
- "create text saying 'Title' and 'Subtitle'"

### Complex Path (Groq → Claude Fallback if Needed)

**Components:**
- "create a login form with email and password"
- "create a navbar with logo and 5 menu items"
- "create a dashboard with sidebar and main content"

**Contextual:**
- "arrange these objects in a grid"
- "move this shape to the right"
- "align these to the center"

**Ambiguous:**
- "make it look better"
- "organize this nicely"
- "create a nice layout"

---

## Timeline

**Total: 6-8 days for Phases 1-2 (core performance goals met)**

- Phase 1: 1-2 days → 70% of commands < 1s ✅
- Phase 2: 2-3 days → 90% of commands < 2s ✅
- Phase 3: 3-4 days → Streaming (optional)
- Phase 4: 2-3 days → Layouts (optional)

**Recommended Approach:**
1. Start with Phase 1 immediately
2. Validate performance gains
3. Proceed to Phase 2
4. Evaluate need for Phases 3-4 based on user feedback
