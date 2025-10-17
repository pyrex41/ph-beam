# AI Tooling Architecture Diagrams

## Current Architecture (Monolithic)

```
┌─────────────────────────────────────────────────────────────┐
│                         LiveView                             │
│  User: "create a red circle"                                 │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                    CollabCanvas.AI.Agent                     │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  execute_command/2                                    │   │
│  │  - Validate canvas                                    │   │
│  │  - call_claude_api/1 ────────► Claude API            │   │
│  │  - parse_response/1          (1.5-2.0s)              │   │
│  │  - process_tool_calls/2                              │   │
│  │    └─► Enum.map (SEQUENTIAL)                         │   │
│  │         ├─► execute_tool_call/2 (200ms)              │   │
│  │         ├─► execute_tool_call/2 (200ms)              │   │
│  │         └─► execute_tool_call/2 (200ms)              │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                  Canvases.create_object/3                    │
│                  + PubSub.broadcast/3                        │
└─────────────────────────────────────────────────────────────┘

Total Latency: 2.8-3.5s ❌
```

---

## Optimized Architecture (Phase 1: Fast Path)

```
┌─────────────────────────────────────────────────────────────┐
│                         LiveView                             │
│  User: "create a red circle"                                 │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│              CollabCanvas.AI.CommandClassifier               │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  classify/1                                           │   │
│  │  - Pattern matching (< 1ms)                          │   │
│  │  - Complexity analysis                                │   │
│  │  Returns: :fast_path | :complex_path                 │   │
│  └──────────────────────────────────────────────────────┘   │
└───────────────┬────────────────────────┬────────────────────┘
                │                        │
    :fast_path  │                        │ :complex_path
                ▼                        ▼
    ┌───────────────────┐    ┌──────────────────────┐
    │   Groq Provider   │    │   Claude Provider    │
    │   (0.3-0.5s) ✅   │    │    (1.5-2.0s)        │
    └─────────┬─────────┘    └──────────┬───────────┘
              │                         │
              └────────┬────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│              CollabCanvas.AI.ToolRegistry                    │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  execute_tool/4 (O(1) lookup)                        │   │
│  │  - Get tool module from compile-time map             │   │
│  │  - Validate with Ecto.Changeset                      │   │
│  │  - Execute tool behaviour                            │   │
│  └──────────────────────────────────────────────────────┘   │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                  Canvases.create_object/3                    │
│                  + PubSub.broadcast/3                        │
└─────────────────────────────────────────────────────────────┘

Total Latency (Simple): 0.6-0.8s ✅
Total Latency (Complex): 2.0-2.5s
```

---

## Optimized Architecture (Phase 2: Parallel Execution)

```
┌─────────────────────────────────────────────────────────────┐
│                         LiveView                             │
│  User: "create a red circle, blue square, and green text"   │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│          CommandClassifier → Groq Provider (0.4s)            │
│  Returns: [tool_call_1, tool_call_2, tool_call_3]           │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│           process_tool_calls_parallel/2                      │
│  Task.async_stream (max_concurrency: 10)                    │
│                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │ Task 1       │  │ Task 2       │  │ Task 3       │      │
│  │ CreateShape  │  │ CreateShape  │  │ CreateText   │      │
│  │ (0.2s)       │  │ (0.2s)       │  │ (0.2s)       │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
│         │                  │                  │              │
│         └──────────────────┴──────────────────┘              │
│                            │                                 │
│                   All complete in 0.25s ✅                   │
└────────────────────────────┬────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────┐
│                  PubSub.broadcast/3 (batch)                  │
└─────────────────────────────────────────────────────────────┘

Total Latency (3 tools): 0.4s + 0.25s = 0.65s ✅
(vs 2.8s + 0.6s = 3.4s sequential)
```

---

## Optimized Architecture (Phase 3: Streaming)

```
┌─────────────────────────────────────────────────────────────┐
│                         LiveView                             │
│  User: "create a complete dashboard layout"                 │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│     CommandClassifier → :complex_path → Claude Provider      │
│     call_streaming/2 (returns Stream)                        │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                 StreamingAgent.execute/3                     │
│                                                              │
│  Stream                                                      │
│  |> Stream.each(fn tool_call ->                             │
│       # Execute immediately                                 │
│       result = ToolRegistry.execute_tool(...)               │
│                                                              │
│       # Broadcast immediately (don't wait for others)       │
│       PubSub.broadcast("canvas:#{id}", result)              │
│     end)                                                     │
│  |> Stream.run()                                            │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                        LiveView                              │
│  handle_info({:ai_tool_result, result}, socket)             │
│  - Update UI incrementally                                  │
│  - Push JS event for visual feedback                        │
└─────────────────────────────────────────────────────────────┘

Timeline:
t=0.0s:  Request sent
t=0.5s:  First tool result received ✅ (user sees progress)
t=0.7s:  Second tool result received ✅
t=0.9s:  Third tool result received ✅
t=1.2s:  All tools complete ✅

Perceived latency: 0.5s (time to first visual feedback) ✅
```

---

## Component Architecture (Tool Behaviour System)

```
┌─────────────────────────────────────────────────────────────┐
│              CollabCanvas.AI.ToolBehaviour                   │
│  @callback schema() :: map()                                 │
│  @callback validate(input) :: {:ok, term()} | {:error, ...} │
│  @callback execute(input, canvas_id, ctx) :: {:ok, term()}  │
│  @callback cacheable?() :: boolean()                         │
└────────────────────────┬────────────────────────────────────┘
                         │
                         │ implements
                         │
         ┌───────────────┼───────────────┬─────────────────┐
         │               │               │                 │
         ▼               ▼               ▼                 ▼
┌────────────────┐ ┌────────────┐ ┌────────────┐ ┌────────────────┐
│ CreateShape    │ │ MoveObject │ │ ResizeObject│ │ CreateComponent│
│                │ │            │ │            │ │                │
│ - schema/0     │ │ - schema/0 │ │ - schema/0 │ │ - schema/0     │
│ - validate/1   │ │ - validate/1│ │ - validate/1│ │ - validate/1   │
│ - execute/3    │ │ - execute/3│ │ - execute/3│ │ - execute/3    │
│ - cacheable?/0 │ │ - cacheable?/0│ │ - cacheable?/0│ │ - cacheable?/0│
└────────────────┘ └────────────┘ └────────────┘ └────────────────┘
         │               │               │                 │
         └───────────────┴───────────────┴─────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│              CollabCanvas.AI.ToolRegistry                    │
│  @tools [CreateShape, MoveObject, ResizeObject, ...]        │
│                                                              │
│  Compile-time map:                                          │
│  @tool_map %{                                               │
│    "create_shape" => CreateShape,                           │
│    "move_object" => MoveObject,                             │
│    ...                                                       │
│  }                                                           │
│                                                              │
│  get_tool/1: O(1) lookup ✅                                  │
│  execute_tool/4: validate + execute                         │
└─────────────────────────────────────────────────────────────┘
```

---

## Provider Selection Decision Tree

```
                    ┌──────────────────┐
                    │  User Command    │
                    └────────┬─────────┘
                             │
                             ▼
                   ┌──────────────────┐
                   │  Classify        │
                   │  Command         │
                   └────────┬─────────┘
                            │
          ┌─────────────────┴─────────────────┐
          │                                   │
          ▼                                   ▼
┌──────────────────────┐          ┌──────────────────────┐
│ Simple?              │          │ Multiple Operations? │
│ - Single operation   │          │ - Count action verbs │
│ - Clear intent       │          │ - "and", "then"      │
│ - No context needed  │          └──────────┬───────────┘
└──────────┬───────────┘                     │
           │ YES                             │ YES
           ▼                                 ▼
  ┌─────────────────┐               ┌─────────────────┐
  │   FAST PATH     │               │  COMPLEX PATH   │
  │   Groq          │               │  Claude         │
  │   0.3-0.5s ✅   │               │  1.5-2.0s       │
  └─────────┬───────┘               └─────────┬───────┘
            │                                 │
            ▼                                 ▼
  ┌─────────────────┐               ┌─────────────────┐
  │ Single Turn     │               │ Agent Loop      │
  │ No history      │               │ With history    │
  │ Fast response   │               │ Max 5 turns     │
  └─────────────────┘               └─────────────────┘

Examples:
  FAST PATH:
  - "create a red circle"
  - "move object 123 to 100,200"
  - "delete shape 456"
  
  COMPLEX PATH:
  - "create a login form with email and password"
  - "arrange these objects in a grid"
  - "make a navbar with logo and 5 menu items"
```

---

## Data Flow: Simple Command (Optimized)

```
User Input: "create a red circle at 100,100"
│
├─> CommandClassifier.classify/1 (< 1ms)
│   └─> :fast_path
│
├─> Agent.select_provider(:fast_path)
│   └─> Providers.Groq
│
├─> Groq.call/3 (300-500ms)
│   ├─> POST https://api.groq.com/openai/v1/chat/completions
│   └─> Returns: [%{name: "create_shape", input: %{...}}]
│
├─> ToolRegistry.execute_tool/4 (< 1ms lookup)
│   ├─> Get tool: CreateShape
│   ├─> Validate: CreateShape.validate/1
│   │   └─> Ecto.Changeset (type-safe)
│   └─> Execute: CreateShape.execute/3
│       ├─> Canvases.create_object/3 (100-150ms)
│       └─> PubSub.broadcast/3 (< 10ms)
│
└─> LiveView receives broadcast
    └─> Updates UI via hook

Total: 300-500ms (API) + 150ms (execution) = 450-650ms ✅
```

---

## Data Flow: Complex Command (Optimized)

```
User Input: "create a login form with email, password, and submit button"
│
├─> CommandClassifier.classify/1
│   └─> :complex_path (detected "with", "and")
│
├─> Agent.select_provider(:complex_path)
│   └─> Providers.Claude
│
├─> Claude.call/3 (1500-2000ms)
│   ├─> POST https://api.anthropic.com/v1/messages
│   └─> Returns: [
│       %{name: "create_component", input: %{type: "login_form", ...}}
│     ]
│
├─> ToolRegistry.execute_tool/4
│   ├─> Get tool: CreateComponent
│   ├─> Validate: CreateComponent.validate/1
│   └─> Execute: CreateComponent.execute/3
│       ├─> ComponentBuilder.create_login_form/7
│       │   ├─> Create background rectangle
│       │   ├─> Create email input
│       │   ├─> Create password input
│       │   └─> Create submit button
│       │       └─> All in PARALLEL (Task.async_stream)
│       │           Total: 250ms (vs 800ms sequential)
│       │
│       └─> PubSub.broadcast/3 (< 10ms)
│
└─> LiveView receives broadcast
    └─> Updates UI

Total: 1500-2000ms (API) + 250ms (execution) = 1.75-2.25s
```

---

## Comparison Table

| Metric | Current | Phase 1 | Phase 2 | Phase 3 |
|--------|---------|---------|---------|---------|
| **Simple Command** | 2.8s | 0.8s ⚡ | 0.6s ⚡ | 0.4s ⚡ |
| **Multi-Tool (5 tools)** | 3.5s | 2.0s | 0.9s ⚡ | 0.6s ⚡ |
| **Complex Component** | 4.0s | 2.5s | 2.0s | 1.2s ⚡ |
| **Time to First Feedback** | 2.8s | 0.8s | 0.6s | 0.5s ⚡ |
| **Provider Options** | 1 | 2 | 2 | 2 |
| **Tool Execution** | Sequential | Sequential | Parallel ⚡ | Streaming ⚡ |
| **Extensibility** | Low | Medium | High ⚡ | High ⚡ |
| **Type Safety** | Low | Low | High ⚡ | High ⚡ |
| **Cost per 1000 cmds** | $0.90 | $0.37 ⚡ | $0.37 ⚡ | $0.37 ⚡ |

⚡ = Significant improvement
