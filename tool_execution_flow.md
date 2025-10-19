# CollabCanvas Tool Execution Flow Diagram

## 1. AI COMMAND EXECUTION FLOW

```
User Types AI Command
       ↓
┌─────────────────────────────────────────────────────────────┐
│ handle_event("execute_ai_command", params, socket)          │
│ File: canvas_live.ex:1267-1343                              │
│                                                               │
│ 1. Check if help command → return help directly             │
│ 2. Check if AI already loading → warn user                  │
│ 3. Spawn Task.async with command execution                  │
│ 4. Set 30s timeout via Process.send_after                   │
│ 5. Set ai_loading=true, store task ref                      │
│ 6. Clear previous flash messages                            │
└─────────────────────────────────────────────────────────────┘
       ↓ (async)
┌─────────────────────────────────────────────────────────────┐
│ Agent.execute_command(command, canvas_id, selected_ids)     │
│ File: agent.ex:127-176                                      │
│                                                               │
│ 1. Verify canvas exists                                     │
│ 2. Build enhanced command with:                             │
│    - List of all objects with names                         │
│    - Canvas statistics (colors, types)                      │
│    - Selected object context                                │
│    - Viewport position                                      │
│    - Current color preference                               │
│ 3. Call Claude/OpenAI/Groq API with tools                   │
│ 4. Parse response → extract tool calls                      │
│ 5. Normalize tool inputs (string→int IDs)                   │
│ 6. Process tool calls:                                      │
│    ├─ Batch create calls via BatchProcessor                 │
│    └─ Individual calls via execute_tool_call                │
│ 7. Return results or error                                  │
└─────────────────────────────────────────────────────────────┘
       ↓ (async result)
┌─────────────────────────────────────────────────────────────┐
│ handle_info({ref, result}, socket)                          │
│ File: canvas_live.ex:1994-2009                              │
│                                                               │
│ 1. Check if ref matches ai_task_ref (deduplication)         │
│ 2. Demonitor the task                                       │
│ 3. Call process_ai_result(result, socket)                   │
│ 4. Set ai_loading=false, clear task ref                     │
└─────────────────────────────────────────────────────────────┘
       ↓
    Success or Error Path
```

## 2. TOOL CALL EXECUTION PATHS

### Path A: API Success
```
Claude API Returns Tool Calls
       ↓
parse_claude_response()
       ↓
Normalize Tool Inputs
       ↓
┌──────────────────────────────────────────────────────┐
│ Separate Tool Calls                                  │
│ - create_shape, create_text → Batch                 │
│ - Other tools → Individual                          │
└──────────────────────────────────────────────────────┘
       ↓
       ├─ BATCH PATH                    INDIVIDUAL PATH ─┐
       ↓                                                 ↓
BatchProcessor.execute_batched_creates    execute_tool_call(tool_call)
       ↓                                                 ↓
Canvases.create_objects_batch            Tool Registry Lookup
(atomic transaction)                           ↓
       ↓                                  If found: execute via registry
Return batch results                     If not found: legacy pattern match
       ↓                                       ↓
       └─────────────┬──────────────────────────┘
                     ↓
          Combine Results in Original Order
          (via BatchProcessor.combine_results_in_order)
                     ↓
          Return [{tool, input, result}, ...]
```

### Path B: API Error
```
Claude API Returns Error
       ↓
handle_info({:DOWN, ...}) OR handle_info({:ai_timeout, ...})
       ↓
Log Error & Store Error Type
       ↓
{:error, reason}
  ├─ :missing_api_key
  ├─ {:api_error, status, body}
  ├─ {:request_failed, reason}
  ├─ :invalid_response_format
  └─ :canvas_not_found
       ↓
process_ai_result/2 Error Handler
```

## 3. ERROR HANDLING FLOW

```
┌──────────────────────────────────────────────────────────┐
│ process_ai_result(result, socket)                        │
│ File: canvas_live.ex:2363-2665                           │
└──────────────────────────────────────────────────────────┘
       ↓
       ├─ {:ok, results} → Process & Broadcast
       │
       ├─ {:ok, {:text_response, text}}
       │  └─ put_flash(:info, text)
       │
       ├─ {:error, :missing_api_key}
       │  └─ generate_clarifying_question(:missing_api_key)
       │     └─ put_flash(:error, "API key not configured...")
       │
       ├─ {:error, {:api_error, status, body}}
       │  ├─ if status == 429 → rate_limit_message
       │  ├─ if status == 529 → overload_message
       │  ├─ if "Invalid" in error → validation_message
       │  └─ put_flash(:error, ...)
       │
       ├─ {:error, {:request_failed, reason}}
       │  └─ put_flash(:error, "Network error...")
       │
       ├─ {:error, :invalid_response_format}
       │  └─ put_flash(:error, "Invalid response...")
       │
       └─ {:error, reason}
          └─ put_flash(:error, "AI command failed...")
```

## 4. SUCCESSFUL RESULT PROCESSING

```
{:ok, results} (list of tool results)
       ↓
Process each result to extract:
├─ created_objects (from create_* tools)
├─ updated_objects (from move/resize/etc)
└─ special results (label toggle, selections)
       ↓
Broadcast to PubSub Topic "canvas:#{canvas_id}"
├─ Each created object: {:object_created, object}
└─ Each updated object: {:object_updated, object, user_id}
       ↓
Update Local Socket State
├─ Merge created_objects with existing
├─ Replace updated_objects in list
└─ Update :objects assign
       ↓
Push Events to JavaScript
├─ push_event("object_created", %{object: ...})
└─ push_event("object_updated", %{object: ...})
       ↓
Display Success Flash Message
└─ put_flash(:info, "AI created X and updated Y objects successfully")
```

## 5. ASYNC TASK LIFECYCLE

```
Time: T0
Task.async spawned
↓ ai_loading = true
↓ ai_task_ref = task.ref
↓ Process.send_after(..., 30_000)
│
├─ NORMAL COMPLETION (T0 + few seconds)
│  └─ handle_info({task.ref, result}, socket)
│     ├─ Process result
│     └─ ai_loading = false
│
├─ TIMEOUT (T0 + 30 seconds)
│  └─ handle_info({:ai_timeout, task.ref}, socket)
│     ├─ If ref == ai_task_ref (first timeout handler)
│     │  └─ flash(:error, "timed out")
│     └─ Ignore if task already completed
│
└─ CRASH (any time)
   └─ handle_info({:DOWN, task.ref, :process, _pid, reason}, socket)
      ├─ If ref == ai_task_ref
      │  └─ flash(:error, "processing failed unexpectedly")
      └─ ai_loading = false
```

## 6. BATCH CREATION OPTIMIZATION

```
Original Tool Calls
├─ create_shape (count=1)
├─ create_text (count=1)
├─ create_shape (count=3)  ← Multi-object creation
└─ move_object

       ↓ Separate into:

Batch Create Calls         Individual Calls
├─ create_shape (1)        └─ move_object
├─ create_text (1)
└─ create_shape (3)

       ↓ Transform to attrs

All attrs for 5 creates:
[
  {type: rectangle, ...},
  {type: text, ...},
  {type: rectangle, ...},   ← 3x from count=3
  {type: rectangle, ...},
  {type: rectangle, ...},
]

       ↓ Execute

Canvases.create_objects_batch(canvas_id, all_attrs)
  → Single atomic transaction
  → [object1, object2, object3, object4, object5]

       ↓ Map back to tool calls

Result 1: {:ok, object1}
Result 2: {:ok, object2}
Result 3: {:ok, {objects: [object3, object4, object5]}}
Result 4: {:ok, updated_object}

       ↓ Combine in order (for AI feedback)
```

## 7. RESPONSE BROADCAST TO CLIENTS

```
Process AI Results
       ↓
Created & Updated Objects List
       ↓
For Each Created Object:
┌─────────────────────────────────────────────┐
│ Phoenix.PubSub.broadcast(                   │
│   PubSub,                                   │
│   "canvas:#{canvas_id}",                    │
│   {:object_created, object}                 │
│ )                                           │
└─────────────────────────────────────────────┘
       ↓ → All connected LiveViews receive
       ├─ Originating client (AI command executor)
       ├─ Other clients viewing same canvas
       └─ Each calls handle_info
             ↓
             ├─ Originating: skip push_event (already have optimistic)
             └─ Others: push_event to PixiJS
                       → render object on canvas
```

## 8. COLOR PREFERENCE FLOW

```
User Selects Color in Color Picker
       ↓
ColorPicker Component Updates
       ↓
set_default_color(user.id, new_color)
       ↓
Update user_color_preferences.default_color in DB
       ↓
Next AI Command Uses New Color:

   Agent.execute_command(
     command,
     canvas_id,
     selected_ids,
     current_color: "#FF00FF"  ← Current preference
   )
       ↓
   Build Enhanced Command:
   "CURRENT COLOR PICKER: #FF00FF
    - Use this color when creating new shapes/text
    UNLESS the user specifies a different color"
       ↓
   Claude Sees Color Context
   └─ If user says "create rectangle" → use #FF00FF
   └─ If user says "blue rectangle" → use #0000FF
```

## 9. KEY STATE MANAGEMENT

```
Socket Assigns for AI Processing:
┌──────────────────────────────────┐
│ ai_command: string               │ ← Current input text
│ ai_loading: boolean              │ ← true while task running
│ ai_task_ref: reference | nil     │ ← Task reference for dedup
│ ai_interaction_history: list     │ ← Last 20 messages
│ current_color: string            │ ← From user_color_preferences
│ selected_objects: [ids]          │ ← For context-aware commands
└──────────────────────────────────┘

Flash Message State:
├─ :info    → Success/clarification (green)
├─ :error   → Errors (red)
└─ :warning → Cautions (yellow)

Result Types:
├─ {:ok, results}
├─ {:ok, {:text_response, text}}
├─ {:ok, {:toggle_labels, boolean}}
├─ {:error, :missing_api_key}
├─ {:error, {:api_error, status, body}}
├─ {:error, {:request_failed, reason}}
├─ {:error, :invalid_response_format}
└─ {:error, :canvas_not_found}
```

## 10. QUICK REFERENCE: ERROR CODES

```
Error Type                      Flash Kind    UI Display
─────────────────────────────────────────────────────────────
missing_api_key                 :error        Red banner
api_error (429)                 :error        Red + "rate limited"
api_error (529)                 :error        Red + "overloaded"
api_error (other)               :error        Red + status code
request_failed                  :error        Red + network message
invalid_response_format         :error        Red + parse error
canvas_not_found                :error        Red + canvas not found
Task timeout (30s)              :error        Red + timeout message
Task crash                      :error        Red + "failed unexpectedly"
ai_loading already true         :warning      Yellow + "already in progress"
empty results                   :warning      Yellow + "couldn't perform"
successful operation            :info         Green + object count
text_response from AI           :info         Green + AI's message
```

