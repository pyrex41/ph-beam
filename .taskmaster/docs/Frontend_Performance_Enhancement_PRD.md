# Frontend Performance Enhancement PRD
## Porting Advanced Canvas Features from Common Lisp Reference

**Version:** 1.0
**Date:** October 2025
**Project:** CollabCanvas - Phoenix LiveView Performance Optimization
**Priority:** High
**Estimated Duration:** 3-5 days

---

## Executive Summary

This PRD outlines the plan to enhance the CollabCanvas frontend by porting high-performance patterns and advanced interaction features from a proven Common Lisp reference implementation. The current Phoenix LiveView implementation is functional but lacks critical performance optimizations needed for smooth rendering with 1000+ objects and rich multi-user interactions.

### Current State
- Basic PixiJS canvas with simple object rendering
- Individual event listeners per object (high memory overhead)
- No viewport culling (renders all objects even when off-screen)
- Simple cursor rendering using PIXI.Graphics per user
- Single object selection only

### Target State
- Advanced viewport culling for 10x performance improvement
- Centralized drag handler (90% reduction in event listeners)
- Shared texture rendering for remote cursors (70% GPU memory reduction)
- Multi-object selection with Shift+Click
- Modular, maintainable architecture with CanvasManager class

### Performance Goals
- **FPS:** Maintain 60 FPS with 1000+ objects on screen
- **Memory:** Reduce GPU memory usage by 70% for cursor rendering
- **Latency:** <16ms per frame for all canvas operations
- **Scale:** Support 50+ concurrent users with visible cursors

---

## Technical Context

### Files to Modify
1. **Primary Target:** `collab_canvas/assets/js/hooks/canvas_manager.js`
   - Current: ~1019 lines, basic implementation
   - Post-refactor: ~1500 lines with advanced features

### Reference Implementation
- **Source:** Common Lisp project `frontend/src/canvas.js`
- **Location:** `repomix-output-cl.xml` (provided context)
- **Features to Port:**
  - PerformanceMonitor class for FPS tracking
  - Viewport culling with configurable padding
  - Centralized event handling architecture
  - Shared texture pattern for repeated graphics
  - Multi-selection state management

### Technology Stack
- **PixiJS:** v7.x (WebGL 2D rendering)
- **Phoenix LiveView:** Real-time state synchronization
- **Alpine.js:** Lightweight UI state management

---

## Feature Requirements

## Phase 1: Modular Architecture Refactoring

### 1.1 Extract CanvasManager Class

**Objective:** Improve code organization and testability by separating PixiJS logic from LiveView hook concerns.

**Requirements:**
- Create new `CanvasManager` class in separate module
- Move all PixiJS-specific logic from hook to manager
- Hook becomes thin adapter between LiveView and CanvasManager
- Maintain 100% backward compatibility

**Acceptance Criteria:**
- [ ] CanvasManager can be instantiated independently
- [ ] All existing functionality works unchanged
- [ ] Clear separation: Hook = LiveView bridge, Manager = Canvas logic
- [ ] No global state - all state encapsulated in manager instance

**Implementation Notes:**
```javascript
// New structure:
// canvas_manager.js (hook) - 200 lines
// core/canvas_manager_class.js - 1000 lines
// core/performance_monitor.js - 100 lines
```

### 1.2 Implement PerformanceMonitor

**Objective:** Track and display FPS for debugging and optimization validation.

**Requirements:**
- Port PerformanceMonitor class from reference implementation
- Track average FPS over 1-second windows
- Expose metrics via console and optional on-screen display
- Minimal performance overhead (<0.1ms per frame)

**Acceptance Criteria:**
- [ ] FPS accurately measured and logged
- [ ] Console output: `[PerformanceMonitor] FPS: 60.2, Frame time: 16.6ms`
- [ ] Metrics available for LiveView to display in UI
- [ ] No performance degradation from monitoring itself

---

## Phase 2: High-Performance Viewport Culling

### 2.1 Implement Visibility Calculation

**Objective:** Stop rendering objects outside the visible viewport to dramatically improve performance.

**Requirements:**
- Calculate visible bounds in world coordinates
- Add configurable padding (default: 200px) to prevent pop-in
- Update object `visible` property based on bounds intersection
- Trigger on: viewport pan, zoom, initial load

**Technical Details:**
```javascript
// Pseudo-code structure:
updateVisibleObjects() {
  const viewport = calculateVisibleBounds(padding: 200);
  for (const [id, object] of this.objects) {
    const bounds = object.getBounds();
    object.visible = boundsIntersect(viewport, bounds);
  }
}
```

**Acceptance Criteria:**
- [ ] Off-screen objects have `visible: false`
- [ ] Objects become visible ~200px before entering viewport
- [ ] Performance improvement: 60 FPS with 5000 objects (90% off-screen)
- [ ] No visible pop-in during fast panning

### 2.2 Integrate with Pan/Zoom

**Objective:** Automatically trigger culling updates during viewport changes.

**Requirements:**
- Call `updateVisibleObjects()` after pan operations
- Call `updateVisibleObjects()` after zoom operations
- Debounce during continuous pan/zoom (max 60Hz)
- Initial culling pass on canvas load

**Acceptance Criteria:**
- [ ] Smooth panning with culling enabled
- [ ] Zoom in/out correctly updates visibility
- [ ] No jank or stuttering during viewport manipulation
- [ ] Initial load renders only visible objects

---

## Phase 3: Centralized Drag Handler

### 3.1 Implement Global Event Architecture

**Objective:** Replace per-object event listeners with single global handlers to reduce memory overhead.

**Current Problem:**
- Every object has mousedown, mousemove, mouseup listeners
- 1000 objects = 3000+ event listener registrations
- High memory usage and GC pressure

**Requirements:**
- Single mousemove listener on `app.stage`
- Single mouseup listener on `app.stage`
- Keep mousedown/pointerdown on individual objects (for hit detection)
- State variable: `this.draggedObject` to track current drag target

**Technical Design:**
```javascript
// Pseudo-code:
onObjectPointerDown(event) {
  this.draggedObject = event.currentTarget;
  this.dragStartOffset = calculateOffset();
}

// Global handler (single registration):
onGlobalPointerMove(event) {
  if (this.draggedObject) {
    updatePosition(this.draggedObject, event.data.global);
  }
}

onGlobalPointerUp(event) {
  if (this.draggedObject) {
    finalizePosition(this.draggedObject);
    this.draggedObject = null;
  }
}
```

**Acceptance Criteria:**
- [ ] Only 2 global event listeners (move + up) on stage
- [ ] Drag functionality identical to current implementation
- [ ] Memory usage reduced by ~66% (measured in Chrome DevTools)
- [ ] No performance regression

### 3.2 Maintain LiveView Integration

**Objective:** Ensure drag events still sync to backend correctly.

**Requirements:**
- Send `update_object` event during drag (throttled to 50ms)
- Send final `update_object` event on drag end
- Support optimistic updates
- Handle conflicts gracefully

**Acceptance Criteria:**
- [ ] Real-time position updates visible to other users
- [ ] Final position persisted to database
- [ ] No race conditions or lost updates
- [ ] Graceful handling of concurrent edits

---

## Phase 4: Optimized Remote Cursor Rendering

### 4.1 Shared Cursor Texture System

**Objective:** Reduce GPU memory usage by 70% when rendering multiple user cursors.

**Current Problem:**
- Each cursor creates new PIXI.Graphics object
- 50 users = 50 separate draw calls and GPU textures
- Significant memory waste for identical shapes

**Requirements:**
- Create single shared cursor texture on initialization
- Use `PIXI.Sprite` instances referencing shared texture
- Apply user color via `sprite.tint` property
- Generate texture once using `renderer.generateTexture()`

**Technical Implementation:**
```javascript
// One-time texture creation:
createSharedCursorTexture() {
  const graphics = new PIXI.Graphics();
  // Draw white cursor arrow
  graphics.beginFill(0xFFFFFF);
  graphics.moveTo(0, 0);
  graphics.lineTo(0, 20);
  graphics.lineTo(6, 15);
  // ... complete cursor shape
  graphics.endFill();

  const texture = this.app.renderer.generateTexture(graphics);
  graphics.destroy(); // Clean up source
  return texture;
}

// Per-user sprite creation:
createUserCursor(userId, color) {
  const sprite = new PIXI.Sprite(this.sharedCursorTexture);
  sprite.tint = color; // Apply user-specific color
  return sprite;
}
```

**Acceptance Criteria:**
- [ ] Single texture created on canvas initialization
- [ ] All user cursors use sprite instances with tint
- [ ] GPU memory usage reduced by 70% (measurable)
- [ ] Visual appearance identical to current implementation
- [ ] Supports 100+ concurrent user cursors at 60 FPS

### 4.2 Cursor Label Optimization

**Objective:** Efficiently render user name labels next to cursors.

**Requirements:**
- Reuse text style objects where possible
- Cache label backgrounds per user
- Update position only (not regenerate graphics)
- Use texture atlas for label backgrounds if >20 users

**Acceptance Criteria:**
- [ ] Name labels render correctly for all users
- [ ] No text rendering on every frame
- [ ] Label backgrounds share common styling
- [ ] Performance: <1ms per frame for 50 cursors

---

## Phase 5: Multi-Object Selection

### 5.1 Implement Selection State Management

**Objective:** Allow users to select and manipulate multiple objects simultaneously.

**Requirements:**
- Maintain `Set<objectId>` for selected objects
- Shift+Click adds/removes from selection
- Regular Click clears selection (unless shift held)
- Visual indication for all selected objects
- Support up to 100 selected objects

**Technical Design:**
```javascript
class CanvasManager {
  constructor() {
    this.selectedObjects = new Set(); // Set<string>
  }

  handleObjectClick(object, event) {
    if (event.shiftKey) {
      // Toggle selection
      if (this.selectedObjects.has(object.id)) {
        this.selectedObjects.delete(object.id);
      } else {
        this.selectedObjects.add(object.id);
      }
    } else {
      // Replace selection
      this.selectedObjects.clear();
      this.selectedObjects.add(object.id);
    }
    this.updateSelectionVisuals();
  }
}
```

**Acceptance Criteria:**
- [ ] Shift+Click adds objects to selection
- [ ] Regular Click clears previous selection
- [ ] Selected objects show blue outline/highlight
- [ ] Selection state survives pan/zoom operations
- [ ] Escape key clears all selections

### 5.2 Implement Multi-Object Dragging

**Objective:** Move all selected objects together as a group.

**Requirements:**
- When dragging any selected object, move all selected objects
- Calculate and apply same delta to all objects in selection
- Maintain relative positions between objects
- Send single batch update to backend on drag end

**Technical Design:**
```javascript
onDragMove(delta) {
  if (this.selectedObjects.size > 0) {
    // Move all selected objects
    for (const objectId of this.selectedObjects) {
      const object = this.objects.get(objectId);
      object.x += delta.x;
      object.y += delta.y;
    }
  }
}

onDragEnd() {
  // Batch update all moved objects
  const updates = Array.from(this.selectedObjects).map(id => ({
    object_id: id,
    position: this.objects.get(id).position
  }));

  this.pushEvent('update_objects_batch', { updates });
}
```

**Acceptance Criteria:**
- [ ] All selected objects move together maintaining relative positions
- [ ] Single batch update event sent to backend
- [ ] Optimistic updates render immediately
- [ ] Undo/redo works for multi-object moves
- [ ] Performance: No lag with 50+ selected objects

### 5.3 Backend Batch Update Support

**Objective:** Handle batch position updates efficiently on the backend.

**Requirements:**
- New LiveView event handler: `update_objects_batch`
- Single database transaction for all updates
- Single PubSub broadcast with all changes
- Conflict detection for locked objects

**Elixir Implementation:**
```elixir
def handle_event("update_objects_batch", %{"updates" => updates}, socket) do
  canvas_id = socket.assigns.canvas_id
  user_id = socket.assigns.current_user.id

  # Update all objects in single transaction
  Repo.transaction(fn ->
    Enum.each(updates, fn update ->
      Canvases.update_object(update["object_id"], update["position"], user_id)
    end)
  end)

  # Single broadcast
  PubSub.broadcast(
    CollabCanvas.PubSub,
    "canvas:#{canvas_id}",
    {:objects_updated_batch, updates}
  )

  {:noreply, socket}
end
```

**Acceptance Criteria:**
- [ ] Batch updates processed in single transaction
- [ ] All-or-nothing update semantics
- [ ] Single broadcast to all users
- [ ] Proper error handling and rollback
- [ ] Performance: <50ms for 50 object updates

---

## Testing Strategy

### Unit Tests

**CanvasManager Class:**
- [ ] Viewport culling calculations
- [ ] Multi-selection state management
- [ ] Drag delta calculations
- [ ] Cursor position transforms

**PerformanceMonitor:**
- [ ] FPS calculation accuracy
- [ ] Frame time tracking
- [ ] Performance overhead measurement

### Integration Tests

**LiveView Integration:**
- [ ] Object creation syncs to backend
- [ ] Batch updates persist correctly
- [ ] Real-time cursor updates
- [ ] Concurrent user interactions

### Performance Tests

**Benchmarks:**
- [ ] 1000 objects: Maintain 60 FPS
- [ ] 5000 objects (90% culled): Maintain 60 FPS
- [ ] 50 concurrent cursors: <2ms rendering overhead
- [ ] 100 selected objects: Drag at 60 FPS

**Load Testing:**
- [ ] 50 simultaneous users
- [ ] 10,000 objects per canvas
- [ ] 1000 updates per second
- [ ] Memory usage under 500MB

### Manual Testing Checklist

**Basic Functionality:**
- [ ] Create rectangle, circle, text
- [ ] Drag single object
- [ ] Drag multiple objects
- [ ] Pan with space+drag
- [ ] Zoom with scroll
- [ ] Delete objects

**Multi-User:**
- [ ] See other users' cursors
- [ ] See other users' edits in real-time
- [ ] Locked object indication
- [ ] Cursor name labels

**Performance:**
- [ ] Smooth pan/zoom with 1000+ objects
- [ ] No lag during multi-object drag
- [ ] Cursors render smoothly for 20+ users

---

## Implementation Plan

### Milestone 1: Architecture Refactoring (Day 1)
**Tasks:**
1. Extract CanvasManager class from hook
2. Implement PerformanceMonitor
3. Update hook to use new class structure
4. Verify backward compatibility

**Deliverables:**
- `core/canvas_manager_class.js`
- `core/performance_monitor.js`
- Updated `canvas_manager.js` hook

### Milestone 2: Viewport Culling (Day 2)
**Tasks:**
1. Implement `updateVisibleObjects()` method
2. Integrate with pan/zoom handlers
3. Add configurable padding parameter
4. Performance testing with 5000 objects

**Deliverables:**
- Viewport culling implementation
- Performance benchmark results

### Milestone 3: Centralized Drag Handler (Day 2-3)
**Tasks:**
1. Implement global event handlers
2. Migrate drag logic from per-object to global
3. Remove old event listeners
4. Verify LiveView integration

**Deliverables:**
- Centralized event handling
- Memory usage reduction metrics

### Milestone 4: Cursor Optimization (Day 3)
**Tasks:**
1. Create shared cursor texture
2. Migrate to sprite-based rendering
3. Implement tint-based coloring
4. Optimize label rendering

**Deliverables:**
- Shared texture system
- GPU memory savings metrics

### Milestone 5: Multi-Selection (Day 4-5)
**Tasks:**
1. Implement selection state management
2. Add Shift+Click handler
3. Implement multi-object dragging
4. Create backend batch update handler
5. Visual selection indicators

**Deliverables:**
- Multi-selection feature complete
- Backend batch update endpoint
- User documentation

### Milestone 6: Testing & Polish (Day 5)
**Tasks:**
1. Run full test suite
2. Performance benchmarking
3. Fix any bugs discovered
4. Update documentation

**Deliverables:**
- Test results report
- Performance comparison (before/after)
- Updated README

---

## Success Metrics

### Performance Metrics

**Target Improvements:**
- **FPS:** 40 → 60 FPS with 1000 objects (+50%)
- **Memory:** 300MB → 90MB for 50 cursors (-70%)
- **Render Time:** 25ms → 16ms per frame (-36%)
- **Event Listeners:** 3000 → 100 (-97%)

### User Experience

**Qualitative Goals:**
- Buttery smooth panning and zooming
- Instant response to drag operations
- No visible lag with 50+ users
- Professional desktop-app feel

---

## Risk Mitigation

### Technical Risks

**Risk: Breaking existing functionality**
- Mitigation: Comprehensive test suite before changes
- Mitigation: Feature flags for gradual rollout
- Mitigation: Easy rollback mechanism

**Risk: Performance worse on low-end devices**
- Mitigation: Progressive enhancement approach
- Mitigation: Device capability detection
- Mitigation: Configurable culling aggressiveness

**Risk: LiveView sync issues with batch updates**
- Mitigation: Extensive integration testing
- Mitigation: Conflict resolution strategy
- Mitigation: Optimistic update reconciliation

### Project Risks

**Risk: Scope creep beyond 5 days**
- Mitigation: Strict phase gating
- Mitigation: MVP-first approach
- Mitigation: Defer nice-to-haves to Phase 6

**Risk: Common Lisp reference code doesn't translate well**
- Mitigation: Adapt patterns rather than direct port
- Mitigation: Leverage PixiJS best practices
- Mitigation: Consult PixiJS documentation for equivalents

---

## Code Quality Standards

### Architecture Principles
- **Separation of Concerns:** Clear boundaries between hook, manager, and PixiJS
- **Single Responsibility:** Each class/module has one clear purpose
- **Testability:** All logic testable without DOM or LiveView
- **Performance First:** Minimize allocations, cache calculations

### Code Style
- **ES6+ Features:** Use modern JavaScript (classes, async/await, destructuring)
- **TypeScript-Ready:** JSDoc comments for all public methods
- **Error Handling:** Graceful degradation, no silent failures
- **Logging:** Structured logging with performance markers

### Documentation Requirements
- **Inline Comments:** Complex algorithms explained
- **Method Documentation:** JSDoc for all public APIs
- **Architecture Diagrams:** Visual representation of class relationships
- **Performance Notes:** Document optimization reasoning

---

## Rollout Strategy

### Phase 1: Internal Testing (Day 5)
- Deploy to staging environment
- Manual testing with 5-10 internal users
- Performance profiling and metrics collection

### Phase 2: Beta Release (Week 2)
- Feature flag: `enable_advanced_canvas: true`
- Invite 50 beta users
- Monitor performance metrics and bug reports

### Phase 3: General Availability (Week 3)
- Enable for all users
- Monitor error rates and performance
- Prepare hotfix process

### Rollback Plan
- Feature flag to revert to old implementation
- Database migrations are backward compatible
- Keep old code for 2 weeks post-GA

---

## Future Enhancements (Out of Scope)

### Potential Phase 6 Features
- **Spatial Index:** Quadtree for faster hit detection
- **WebGL Shaders:** Custom shaders for effects
- **Object Grouping:** Hierarchical object organization
- **Smart Snapping:** Align objects with guides
- **Collaborative Cursors:** Show what each user is selecting
- **Undo/Redo Stack:** Full history management
- **Copy/Paste:** Duplicate objects easily

---

## Appendix: Reference Implementation Comparison

### Common Lisp Reference Features
```javascript
// Key patterns to port:

1. PerformanceMonitor class
   - FPS tracking with moving average
   - Frame time analysis
   - Memory usage monitoring

2. Viewport culling algorithm
   - calculateVisibleBounds(padding)
   - boundsIntersect(a, b)
   - updateVisibleObjects()

3. Centralized event handling
   - Single stage-level listeners
   - State machine for drag/pan/zoom
   - Event delegation pattern

4. Shared texture optimization
   - generateTexture() for reusable assets
   - Sprite pooling for cursors
   - Tint-based color variations

5. Multi-selection architecture
   - Set-based selection tracking
   - Batch update queue
   - Selection visual container
```

### Phoenix LiveView Specific Adaptations

**Events to Backend:**
```javascript
// Current:
this.pushEvent('update_object', { object_id, position });

// New batch update:
this.pushEvent('update_objects_batch', {
  updates: [
    { object_id: 1, position: {x, y} },
    { object_id: 2, position: {x, y} },
    // ...
  ]
});
```

**Real-time Sync:**
```javascript
// Maintain optimistic updates
// Reconcile with server state on conflict
// Handle late-arriving updates gracefully
```

---

## Conclusion

This PRD provides a comprehensive blueprint for enhancing the CollabCanvas frontend with battle-tested performance patterns from the Common Lisp reference implementation. By following this phased approach, we'll achieve significant performance gains while maintaining code quality and LiveView integration.

**Key Deliverables:**
1. Modular CanvasManager architecture
2. 10x performance improvement via culling
3. 70% GPU memory reduction for cursors
4. Multi-object selection capability
5. Centralized, maintainable event handling

**Timeline:** 3-5 days for full implementation and testing

**Next Steps:**
1. Review and approve PRD
2. Set up Task Master tasks from this PRD
3. Begin Milestone 1: Architecture Refactoring
4. Daily progress check-ins and performance validation
