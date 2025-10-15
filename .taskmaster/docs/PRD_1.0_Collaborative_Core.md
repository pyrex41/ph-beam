# PRD 1.0: Rock-Solid Collaborative Core

## Executive Summary

This PRD defines the requirements to achieve an "Excellent" rating on collaborative functionality. The goal is to make the core collaborative experience flawless, resilient, and capable of handling simultaneous edits by multiple users without data loss or corruption.

**IMPORTANT NOTE:** Many of these features are already implemented in the current codebase. This PRD serves as a comprehensive review checklist to verify, test, and ensure all collaborative features are working correctly. Each feature should be thoroughly reviewed and tested to confirm it meets the requirements specified below.

## Performance Requirements

- **Real-Time Sync:** All object manipulations (create, update, delete) must be reflected on all connected clients in under **100ms**
- **Cursor Sync:** Cursor movements must sync in under **50ms**
- **Rendering:** The PixiJS canvas must maintain a consistent **60 FPS** even with 500+ complex objects and 5+ concurrent users
- **Persistence:** Zero data loss during browser refreshes, network drops of 30+ seconds, or all users leaving a session

## Core Features

### 1.1 Atomic Operations & Locking

**User Story:** As a user, when I edit an object at the same time as a colleague, our changes are merged logically without creating duplicates or losing work.

**Requirements:**

1. Refactor the `update_object` event to send deltas instead of final state
   - Example delta: `%{op: "move", delta: %{x: 10, y: -5}}`
   - Support operations: move, resize, rotate, style_update

2. Enhance the existing `locked_by` field to create an atomic "check-out" system
   - When a user starts a drag, they acquire a lock on the object
   - Lock is released on `mouseup` event
   - Lock timeout: 5 seconds of inactivity to prevent orphaned locks

3. Implement lock and selection visualization
   - **CRITICAL:** Show a colored border around objects when selected/locked by another user
   - Each user should have a unique color assigned to them
   - Border color should match the user's cursor color for visual consistency
   - Display the locking user's name/avatar near the locked object
   - Prevent modification attempts on locked objects
   - Selection border should be clearly visible but not intrusive (2-3px stroke)

4. Handle lock conflicts gracefully
   - If a user tries to modify a locked object, show a non-intrusive notification
   - Queue the operation until the lock is released (optional)

**Technical Implementation:**

- Modify `lib/collab_canvas_web/live/canvas_live.ex` event handlers
- Update `lib/collab_canvas/canvases/object.ex` schema to include `locked_at` timestamp
- Add PubSub broadcast for lock acquisition and release events
- Update frontend `hooks/canvas_renderer.js` to handle lock events and render colored borders
- Assign each user a unique color on join (broadcast via presence)
- Render selection borders using PixiJS Graphics overlays

**Verification Checklist:**

- [ ] Review existing locking mechanism in `canvas_live.ex` and `canvas_renderer.js`
- [ ] Verify `locked_by` field is being set when user selects/drags an object
- [ ] Confirm lock is released on `mouseup` and on user disconnect
- [ ] Test colored border rendering: each user should see other users' selections in their assigned colors
- [ ] Verify border color matches cursor color for visual consistency
- [ ] Test lock timeout: orphaned locks should release after 5 seconds
- [ ] Confirm lock conflicts are handled gracefully (user sees notification)

**Acceptance Criteria:**

- Two users can simultaneously drag different objects without conflicts
- **CRITICAL:** When User A selects an object, User B sees a colored border around it (in User A's color)
- Border color is consistent with User A's cursor color
- Attempting to modify a locked object shows clear feedback
- Locks are automatically released after timeout or on user disconnect
- No duplicate objects are created during simultaneous operations
- Colored borders render at 60 FPS without performance degradation

---

### 1.2 Client-Side Operation Queuing

**User Story:** As a user, if my internet connection drops, I can continue working, and my changes will sync automatically once I'm back online.

**Requirements:**

1. Implement an operation queue in the frontend
   - Queue all canvas operations (create, update, delete) when disconnected
   - Store operations in browser localStorage for persistence across page refreshes
   - Display a clear "offline mode" indicator in the UI

2. Automatic reconnection and sync
   - On reconnection, send all queued operations to the server in order
   - Handle potential conflicts with operations that occurred on the server during disconnect
   - Show sync progress indicator during batch upload

3. Conflict resolution for offline operations
   - Server validates each queued operation against current state
   - If an object was deleted on the server, drop the update operation
   - If concurrent edits occurred, use last-write-wins with timestamp comparison
   - Notify user of any operations that couldn't be applied

**Technical Implementation:**

- Add operation queue to `hooks/canvas_renderer.js`
- Implement `localStorage` persistence for offline operations
- Enhance Phoenix Channel reconnection logic
- Create new server endpoint for batch operation processing: `handle_in("batch_operations", payload, socket)`

**Verification Checklist:**

- [ ] Review existing channel reconnection logic
- [ ] Verify operation queue exists and is being used during disconnections
- [ ] Test localStorage persistence: refresh browser while offline, confirm operations persist
- [ ] Simulate network disconnect (use browser DevTools) and test 10+ operations
- [ ] Verify sync occurs automatically on reconnection
- [ ] Test conflict resolution when server state has changed during disconnect

**Acceptance Criteria:**

- User can continue editing for 30+ seconds while offline
- All offline operations sync successfully upon reconnection
- UI clearly indicates connection status (connected, connecting, offline)
- Operations persist across browser refresh while offline

---

### 1.3 Enhanced Presence & Connection UI

**User Story:** As a user, I can always see my connection status and know who last edited an object.

**Requirements:**

1. Add comprehensive connection status indicator
   - States: Connected (green), Connecting (yellow), Offline (red)
   - Show connection status icon in top navigation bar
   - Display latency/ping time for connected users
   - Show reconnection attempts and countdown

2. Object edit attribution
   - Add `last_edited_by` and `last_edited_at` fields to Object schema
   - Update these fields on every modification
   - Broadcast edit attribution in real-time

3. Enhanced presence indicators
   - Show all active users in a presence panel
   - Display each user's current selection (what object they're editing)
   - Show user's cursor position and name tag in real-time
   - Color-code each user's cursor and selection highlights

4. Edit history breadcrumbs
   - Show a brief popup near an object after edit showing "Edited by [User]"
   - Fade out after 3 seconds
   - Include user avatar and timestamp

**Technical Implementation:**

- Add connection status component to `lib/collab_canvas_web/live/canvas_live.html.heex`
- Modify `lib/collab_canvas/canvases/object.ex` schema
- Update presence tracking in `lib/collab_canvas_web/channels/canvas_channel.ex`
- Enhance frontend cursor rendering in `hooks/canvas_renderer.js`

**Verification Checklist:**

- [ ] Review existing connection status indicator in UI
- [ ] Verify `last_edited_by` and `last_edited_at` fields exist and are being updated
- [ ] Test presence tracking: join with multiple users, verify all appear in presence panel
- [ ] Test cursor rendering: verify all users' cursors are visible with unique colors
- [ ] Verify cursor movements sync within 50ms (test with network throttling)
- [ ] Test edit attribution popup: modify object, verify other users see "Edited by [Name]"
- [ ] Confirm presence panel shows accurate connection states

**Acceptance Criteria:**

- Connection status is always visible and accurate
- Users can see who edited each object and when
- All users' cursors and selections are visible in real-time
- Presence panel shows all active collaborators with accurate status

---

### 1.4 High-Frequency Event Handling

**User Story:** As a team, we can rapidly edit multiple objects without any lag, dropped events, or state corruption.

**Requirements:**

1. Optimize event handling for high-frequency operations
   - Implement throttling for drag events (send updates every 16ms max for 60 FPS)
   - Debounce final position updates (persist to DB only on mouseup)
   - Broadcast intermediate states via PubSub without DB writes

2. Batch operation processing
   - Allow multiple operations in a single event payload
   - Process batch updates in a single database transaction
   - Broadcast batch changes as a single PubSub message

3. Event priority system
   - Prioritize critical events (create, delete) over updates
   - Process cursor movements with lower priority than object operations
   - Implement event queue with priority lanes

4. Performance monitoring
   - Add metrics for event processing time
   - Log slow operations (>50ms) for debugging
   - Implement circuit breaker for overload protection

**Technical Implementation:**

- Refactor `handle_event` callbacks in `lib/collab_canvas_web/live/canvas_live.ex`
- Add throttling/debouncing in `hooks/canvas_renderer.js`
- Implement batch processing in `lib/collab_canvas/canvases.ex` context
- Add Telemetry instrumentation for performance monitoring

**Verification Checklist:**

- [ ] Review event handlers in `canvas_live.ex`: verify throttling/debouncing is implemented
- [ ] Check database writes: confirm no writes during drag, only on mouseup
- [ ] Test with 5 concurrent users performing rapid drag operations
- [ ] Monitor database query logs during test to verify minimal writes
- [ ] Use browser DevTools Performance tab to verify 60 FPS during heavy load
- [ ] Review existing Telemetry instrumentation for event processing times
- [ ] Test batch operation processing if implemented

**Acceptance Criteria:**

- No perceptible lag when dragging objects with 5+ concurrent users
- Database writes are minimized during rapid drag operations
- All operations complete within performance SLA (100ms for sync)
- System remains stable under load (100 operations/second)

---

### 1.5 Real-Time Dragging and Object Movement Visualization

**User Story:** As a user, when another collaborator drags an object, I can see it moving smoothly in real-time, not just snapping to its final position.

**Requirements:**

1. **Smooth Movement Visualization**
   - **CRITICAL:** Objects being dragged by other users MUST update their position continuously during the drag
   - Updates should occur at minimum 20 times per second (every 50ms) during drag operations
   - Objects should NOT snap to final position only - intermediate positions must be visible
   - Movement should appear smooth and fluid, not choppy or jumpy

2. **Real-Time Position Broadcasting**
   - Broadcast position updates during drag via PubSub (not just on mouseup)
   - Use throttling to limit updates to ~60 FPS (every 16ms) to balance smoothness with network load
   - Send lightweight position-only updates during drag (don't persist to DB until mouseup)
   - Final position is persisted to database only on mouseup

3. **Visual Feedback During Remote Drag**
   - Show the object moving in real-time on all connected clients
   - Maintain the colored selection border (from section 1.1) during the entire drag
   - Display user's name/avatar that follows the object during drag
   - Optional: Show a subtle "ghost" outline at the original position

4. **Performance Optimization**
   - Throttle position updates to prevent network flooding
   - Use requestAnimationFrame for smooth local rendering of remote updates
   - Interpolate between received position updates if updates arrive slower than 60 FPS
   - Separate broadcast channel for high-frequency drag updates vs. database persistence

**Technical Implementation:**

- **Frontend (`hooks/canvas_renderer.js`):**
  - On `mousemove` during drag, throttle and broadcast position via channel
  - Listen for `object:dragging` events from other users
  - Update PixiJS object position immediately when receiving remote drag events
  - Use linear interpolation if needed to smooth out network jitter

- **Backend:**
  - Add new channel event: `handle_in("object_dragging", %{"id" => id, "x" => x, "y" => y}, socket)`
  - Broadcast to other users via PubSub without database write
  - Existing `update_object` event continues to handle final position persistence

- **Channel Events:**

```elixir
# New event for real-time dragging (no DB write)
handle_in("object_dragging", %{
  "object_id" => id,
  "position" => %{"x" => x, "y" => y}
}, socket) do
  # Broadcast to other users immediately
  broadcast_from(socket, "object:dragging", %{
    object_id: id,
    position: %{x: x, y: y},
    user_id: socket.assigns.user_id
  })
  {:noreply, socket}
end

# Existing event for final position (with DB write)
handle_event("update_object", %{"id" => id, ...}, socket) do
  # This persists to database on mouseup
  # ...existing implementation
end
```

**Verification Checklist:**

- [ ] Review existing drag event handlers to confirm real-time broadcasting is implemented
- [ ] Verify throttling is set appropriately (16-50ms between updates)
- [ ] Test with 2+ users: drag an object and confirm others see smooth movement
- [ ] Confirm database writes only occur on mouseup, not during drag
- [ ] Verify colored selection border is visible during entire drag operation
- [ ] Test with slow network: confirm interpolation provides smooth appearance

**Acceptance Criteria:**

- Objects dragged by remote users update position at least 20 times per second
- Movement appears smooth and continuous, not choppy
- No visible "snapping" to final position - all intermediate positions are shown
- Network bandwidth is not overwhelmed (throttling is effective)
- Database is not hit during drag, only on mouseup
- All connected users see the same smooth dragging behavior
- Performance remains at 60 FPS during multi-user dragging

---

## Database Schema Changes

```elixir
# Add to Object schema
field :locked_by, :string  # Existing field
field :locked_at, :utc_datetime
field :last_edited_by, :string
field :last_edited_at, :utc_datetime
```

## API Changes

### New Events

```elixir
# Batch operations
handle_in("batch_operations", %{"operations" => operations}, socket)

# Lock management
handle_in("acquire_lock", %{"object_id" => id}, socket)
handle_in("release_lock", %{"object_id" => id}, socket)

# Delta-based updates
handle_event("update_object_delta", %{
  "id" => id,
  "delta" => %{"op" => "move", "x" => 10, "y" => -5}
}, socket)
```

## Testing Requirements

1. **Concurrent Edit Tests**
   - Test simultaneous edits by 2+ users on different objects
   - Test simultaneous edits by 2+ users on the same object
   - Verify lock acquisition and release

2. **Offline Functionality Tests**
   - Test offline mode with 10+ operations
   - Test reconnection and sync after 30s+ disconnect
   - Verify localStorage persistence across refresh

3. **Performance Tests**
   - Load test with 5 concurrent users performing 100 operations/min
   - Measure latency for all operation types
   - Verify 60 FPS rendering under load

4. **Presence Tests**
   - Verify cursor sync with 5+ users
   - Test presence panel accuracy
   - Verify edit attribution displays correctly

## Success Metrics

- 99.9% of operations complete within 100ms
- Zero data loss during any disconnect/reconnect scenario
- Zero conflict-related duplicates or corruption
- 60 FPS maintained with 500+ objects and 5+ users
- User satisfaction rating of 4.5+/5 for collaboration features
