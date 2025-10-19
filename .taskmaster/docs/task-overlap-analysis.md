# Task Overlap Analysis: "agent" vs "adv" Tags

**Date:** October 19, 2025
**Purpose:** Identify dependencies, overlaps, and potential conflicts between AI agent optimization tasks and advanced features tasks

---

## Executive Summary

**Finding:** Significant architectural overlap exists, but tasks are **complementary, not duplicate**. The "agent" tasks provide **infrastructure** that "adv" tasks **consume**.

**Recommendation:**
1. Complete agent tasks #4, #5, #8, #11 **before** starting adv tasks #4, #9, #14
2. Ensure adv task #15 follows patterns from agent task #2
3. No tasks need to be deleted or merged

---

## Task Set Overview

### Agent Tasks (Tag: "agent") - 15 tasks
**Focus:** AI agent performance, batching, caching, error handling
**Status:** 27% complete (4 done, 2 in-progress, 5 pending, 2 deferred, 2 cancelled)

### Advanced Features Tasks (Tag: "adv") - 15 tasks
**Focus:** Copy/paste, layer panel, auto-layout features
**Status:** 0% complete (all pending)

---

## Critical Dependencies & Overlaps

### 1. ⚠️ **Batched Object Creation** (HIGH PRIORITY)

**Agent Infrastructure:**
- ✅ **Agent #3** - `create_objects_batch` in canvases.ex (DONE)
  - Atomic multi-object insertion
  - Performance target: 500+ objects in <2s
  - Uses Ecto.Multi for transactions

**Adv Consumers:**
- ❌ **Adv #4** - Backend handling for paste objects (PENDING)
  - **MUST use** `create_objects_batch` for multi-object paste
  - Avoid creating duplicate batching logic

**Recommendation:**
```elixir
# Adv #4 should call existing infrastructure
def handle_event("paste_objects", %{"objects" => objects_attrs}, socket) do
  # Use agent's batched creation (task agent#3)
  case Canvases.create_objects_batch(canvas_id, objects_attrs) do
    {:ok, created_objects} ->
      # Broadcast using batched PubSub (task agent#4)
      broadcast_objects_created(socket, created_objects)
      {:noreply, socket}
    {:error, reason} ->
      {:noreply, put_flash(socket, :error, "Paste failed")}
  end
end
```

---

### 2. ⚠️ **Batched PubSub Broadcasting** (HIGH PRIORITY)

**Agent Infrastructure:**
- ▶️ **Agent #4** - Update PubSub for batched broadcasts (IN-PROGRESS)
  - New event: `{:objects_created, list_of_objects, user_id}`
  - Reduces network chatter
  - Single broadcast vs N individual broadcasts

- ❌ **Agent #5** - Update CanvasLive to handle batched events (PENDING)
  - `handle_info({:objects_created, objects, _user_id}, socket)`
  - Single re-render for all objects
  - Optimized for 600+ objects

- ❌ **Agent #11** - Update agent for batched PubSub (PENDING)
  - Broadcasts for all transformation types
  - Creation, resizing, rotation, color changes

**Adv Consumers:**
- ❌ **Adv #4** - Paste objects backend (PENDING)
  - Should broadcast `{:objects_created, pasted_objects, user_id}`

- ❌ **Adv #9** - Backend Z-index update (PENDING)
  - Should broadcast `{:layers_reordered, updates, user_id}`
  - Could use `{:objects_updated_batch, objects, user_id}` pattern

- ❌ **Adv #14** - Auto-layout LiveView integration (PENDING)
  - Should broadcast `{:auto_layout_updated, container, children, user_id}`

**Dependency Chain:**
```
Agent #4 (PubSub patterns) → Agent #5 (CanvasLive handler) → Agent #11 (agent integration)
    ↓
Adv #4, #9, #14 should follow these patterns
```

**Recommendation:**
- **Block adv #4, #9, #14** until agent #4, #5, #11 are complete
- Ensure consistent broadcast message format across all features

---

### 3. ✅ **AI Tool Registry System** (LOW OVERLAP)

**Agent Infrastructure:**
- ✅ **Agent #2** - Enhance tool definitions with few-shot examples (DONE)
  - Pattern established for adding new tools
  - Examples in tool descriptions

**Adv Consumer:**
- ❌ **Adv #15** - AI tool for auto-layout (PENDING)
  - Must follow agent #2 pattern
  - Add tool definition to `lib/collab_canvas/ai/tools/` directory
  - Register in tool_registry.ex

**Example Integration:**
```elixir
# File: lib/collab_canvas/ai/tools/apply_auto_layout.ex
defmodule CollabCanvas.AI.Tools.ApplyAutoLayout do
  @behaviour CollabCanvas.AI.Tool

  @impl true
  def definition do
    %{
      name: "apply_auto_layout",
      description: """
      Apply flexbox-like auto-layout to selected objects.

      Example: User says "arrange these buttons horizontally with 12px spacing",
      you call apply_auto_layout(object_ids: [1, 2, 3], direction: "horizontal", spacing: 12)
      """,
      input_schema: %{
        type: "object",
        properties: %{
          object_ids: %{type: "array", items: %{type: "integer"}},
          direction: %{type: "string", enum: ["horizontal", "vertical"]},
          spacing: %{type: "number"},
          padding: %{type: "number"}
        },
        required: ["object_ids", "direction"]
      }
    }
  end

  @impl true
  def execute(params, context) do
    # Implementation using adv #12's backend algorithm
  end
end
```

**Recommendation:**
- Adv #15 is **independent** - can start anytime after adv #14
- Follow agent #2 few-shot example pattern

---

### 4. 🔄 **Event Processing & Tool Execution** (MEDIUM OVERLAP)

**Agent Infrastructure:**
- ✅ **Agent #6 & #7** - Short-circuit command matching (DONE)
  - Bypass LLM for simple commands like "delete selected", "group"
  - <300ms latency target

- ❌ **Agent #8** - Refactor process_tool_calls for batching (PENDING)
  - Groups all `create_*` calls into batched operations
  - Atomicity for multi-tool AI commands

**Adv Impact:**
- Adv features don't directly depend on agent #6-8
- But they benefit from the performance improvements
- Auto-layout AI tool (adv #15) will benefit from batching

**Recommendation:**
- No blocking dependency
- Nice-to-have: Complete agent #8 before deploying adv #15 to production

---

## Detailed Overlap Matrix

| Agent Task | Status | Adv Dependencies | Impact |
|------------|--------|------------------|--------|
| **#1** ETS cache | Cancelled | None | ❌ No impact |
| **#2** Tool definitions | ✅ Done | Adv #15 | ✅ Pattern established |
| **#3** create_objects_batch | ✅ Done | Adv #4 | ⚠️ **CRITICAL** - Must use |
| **#4** PubSub batching | ▶️ In-progress | Adv #4, #9, #14 | ⚠️ **CRITICAL** - Blocks adv |
| **#5** CanvasLive batching | ❌ Pending | Adv #4, #9, #14 | ⚠️ **CRITICAL** - Blocks adv |
| **#6** Short-circuit | ✅ Done | None | ✅ Performance boost |
| **#7** Short-circuit integration | ✅ Done | None | ✅ Performance boost |
| **#8** Batch tool calls | ❌ Pending | Adv #15 | 🔄 Nice-to-have |
| **#9** Parallel processing | Deferred | None | ❌ No impact |
| **#10** Caching | Cancelled | None | ❌ No impact |
| **#11** Agent PubSub | ❌ Pending | Adv #4, #9, #14 | ⚠️ **CRITICAL** - Blocks adv |
| **#12** Error handling | ▶️ In-progress | Adv #15 | 🔄 Nice-to-have |
| **#13** Performance opt | Deferred | None | ❌ No impact |
| **#14** E2E testing | ❌ Pending | None | ✅ Will test both |
| **#15** Documentation | ❌ Pending | None | ✅ Should include adv |

**Legend:**
- ⚠️ **CRITICAL** = Blocking dependency - must complete first
- 🔄 **Nice-to-have** = Beneficial but not blocking
- ✅ **Done/Established** = Ready to use
- ❌ **No impact** = Independent

---

## Recommended Implementation Order

### Phase 1: Complete Agent Infrastructure (Unblock Adv)
**Priority:** Complete ASAP before starting adv tasks

1. ✅ **Agent #3** - create_objects_batch (DONE)
2. ▶️ **Agent #4** - PubSub batched broadcasts (IN-PROGRESS)
3. **Agent #5** - CanvasLive batched events
4. **Agent #11** - Agent batched PubSub integration

**Estimated time:** 2-3 days
**Impact:** Unblocks adv #4, #9, #14

---

### Phase 2A: Copy/Paste (Independent Path)
**Can start immediately** - no agent dependencies

1. **Adv #1** - Keyboard shortcuts
2. **Adv #2** - Clipboard storage
3. **Adv #3** - Paste offset calculation
4. ⚠️ **Adv #4** - Backend paste (WAIT for agent #4, #5)
5. **Adv #5** - UI feedback

**Estimated time:** 2-3 days (blocked 1 day waiting for agent tasks)

---

### Phase 2B: Layer Panel (Independent Path)
**Can start immediately** - no agent dependencies

1. **Adv #6** - LayerPanel structure
2. **Adv #7** - Thumbnails
3. **Adv #8** - Drag-and-drop
4. ⚠️ **Adv #9** - Z-index backend (WAIT for agent #4, #5)
5. **Adv #10** - Real-time sync

**Estimated time:** 3-4 days (blocked 1 day waiting for agent tasks)

---

### Phase 3: Auto-Layout (Sequential Path)
**Must wait for agent infrastructure**

1. **Adv #11** - Database migration (can start anytime)
2. **Adv #12** - Backend algorithm
3. **Adv #13** - Frontend manager
4. ⚠️ **Adv #14** - LiveView integration (WAIT for agent #4, #5)
5. **Adv #15** - AI tool (benefits from agent #8)

**Estimated time:** 5-7 days (includes agent wait time)

---

### Phase 4: Testing & Documentation
**After all features complete**

1. **Agent #14** - E2E integration testing (covers both tags)
2. **Agent #15** - Documentation (covers both tags)

**Estimated time:** 2-3 days

---

## Potential Conflicts & Resolutions

### Conflict 1: Duplicate Batching Logic
**Risk:** Adv #4 might implement its own batching instead of using agent #3

**Resolution:**
- Document clearly in adv #4 that it MUST call `Canvases.create_objects_batch/2`
- Add validation test to ensure no duplicate batching code

---

### Conflict 2: Inconsistent Broadcast Patterns
**Risk:** Adv tasks might use different broadcast message formats

**Resolution:**
- Create shared documentation for broadcast patterns:
  ```elixir
  # Standard pattern
  {:objects_created, list_of_objects, originating_user_id}
  {:objects_updated_batch, list_of_objects, originating_user_id}
  {:layers_reordered, list_of_updates, originating_user_id}
  ```
- Add linter or test to enforce pattern

---

### Conflict 3: AI Tool Registration
**Risk:** Adv #15 might not follow agent #2 conventions

**Resolution:**
- Add checklist to adv #15:
  - [ ] Create tool module in `lib/collab_canvas/ai/tools/`
  - [ ] Implement `CollabCanvas.AI.Tool` behaviour
  - [ ] Add few-shot examples in description
  - [ ] Register in tool_registry.ex potential_tools list

---

## Testing Strategy

### Integration Test Coverage
**Ensure both task sets work together**

```elixir
# File: test/collab_canvas_web/live/canvas_live_integration_test.exs

describe "Copy/Paste with AI Agent (agent + adv integration)" do
  test "paste 100 objects uses batched creation and broadcasting" do
    # Setup: Select objects
    # Adv #1-3: Copy/paste triggers
    # Agent #3: Uses create_objects_batch
    # Agent #4-5: Uses batched PubSub
    # Adv #4: Backend handles paste

    assert_received {:objects_created, objects, _user_id}
    assert length(objects) == 100
    assert page_has_css?(".canvas-object", count: 100)
  end
end

describe "Auto-Layout AI Command (agent + adv integration)" do
  test "AI command creates auto-layout with batched tools" do
    # Adv #15: AI tool definition
    # Agent #8: Batches multiple create calls
    # Adv #14: LiveView integration
    # Agent #11: Broadcasts batch

    execute_ai_command("create 5 buttons in horizontal auto-layout")
    assert_received {:objects_created, buttons, _user_id}
    assert_received {:auto_layout_applied, container, _user_id}
  end
end
```

---

## Risk Assessment

### High Risk
- ⚠️ **Agent #4, #5, #11 delay** → Blocks 40% of adv tasks (6/15)
- ⚠️ **Inconsistent broadcast patterns** → Real-time sync bugs across features

### Medium Risk
- 🔄 **Agent #8 delay** → AI auto-layout less performant (not broken)
- 🔄 **Missing few-shot examples in adv #15** → Lower AI accuracy

### Low Risk
- ✅ **Agent #3 already done** → Copy/paste backend ready
- ✅ **Agent #6-7 done** → AI performance improvements available

---

## Action Items

### Immediate (Before Starting Adv Work)
1. [ ] Complete agent #4 (PubSub batching) - **IN-PROGRESS**
2. [ ] Complete agent #5 (CanvasLive batching)
3. [ ] Complete agent #11 (Agent PubSub integration)
4. [ ] Document broadcast pattern standards
5. [ ] Add integration test template

### During Adv Implementation
1. [ ] Verify adv #4 uses `create_objects_batch` (agent #3)
2. [ ] Verify adv #4, #9, #14 use batched broadcasts (agent #4-5)
3. [ ] Verify adv #15 follows tool definition pattern (agent #2)
4. [ ] Run cross-tag integration tests

### After Adv Complete
1. [ ] Run agent #14 E2E tests covering both tags
2. [ ] Update agent #15 documentation to include adv features
3. [ ] Performance benchmark all batched operations

---

## Conclusion

**Summary:**
- ✅ **No duplicate work** - Tasks are complementary
- ⚠️ **Critical dependencies** - Agent infrastructure must complete first
- 🚀 **Parallel opportunities** - Can work on adv #1-3, #6-8, #11-13 while agent completes
- 📈 **Rubric impact** - Both tags contribute to different rubric sections

**Recommended Approach:**
1. Finish agent #4, #5, #11 (~2-3 days)
2. Start adv work in parallel tracks:
   - Track A: Copy/paste (#1-5)
   - Track B: Layer panel (#6-10)
   - Track C: Auto-layout (#11-15)
3. Integrate and test together
4. Deploy as cohesive feature set

**Total estimated time:** 10-14 days (as per original PRD estimate)

---

**Last Updated:** October 19, 2025
**Status:** Ready for implementation - dependencies identified and documented
