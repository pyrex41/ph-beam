# CollabCanvas Advanced Features PRD

## Product Requirements Document
**Version:** 1.0
**Date:** October 18, 2025
**Project:** CollabCanvas - Figma Clone
**Purpose:** Add advanced Figma-inspired features to meet rubric requirements

---

## Executive Summary

This PRD defines three critical features to elevate CollabCanvas to production quality:

1. **Copy/Paste System** (Tier 1) - Standard clipboard operations for canvas objects
2. **Context-Aware Layer Panel** (Tier 2) - Intelligent layer management for selections
3. **Auto-Layout System** (Tier 3) - Flexbox-like automatic spacing and sizing

These features complete the advanced features section of the rubric:
- **Tier 1**: Color picker ✓, Grouping ✓, Copy/paste (NEW) = 3/3 features
- **Tier 2**: Layer panel (NEW), Z-index ✓ = 2/2 features
- **Tier 3**: Auto-layout (NEW) = 1/1 feature
- **Total potential score**: 13-15 points (Excellent)

---

## Feature 1: Copy/Paste System

### Overview
Implement standard copy/paste operations for canvas objects with keyboard shortcuts, preserving all object properties and supporting multi-object selection.

### User Stories

**As a canvas user:**
- I want to copy selected objects using Cmd+C (Mac) / Ctrl+C (Windows)
- I want to paste copied objects using Cmd+V (Mac) / Ctrl+V (Windows)
- I want pasted objects to appear with a small offset from originals (avoid overlap)
- I want to paste the same objects multiple times
- I want to copy/paste groups of objects while maintaining relative positions

### Technical Requirements

#### Keyboard Shortcuts
- **Copy**: `Cmd+C` (Mac) / `Ctrl+C` (Windows)
- **Paste**: `Cmd+V` (Mac) / `Ctrl+V` (Windows)
- **Cut**: `Cmd+X` (Mac) / `Ctrl+X` (Windows) - Copy + Delete

#### Clipboard Data Structure
Store copied objects in browser session storage:
```javascript
{
  objects: [
    {
      type: "rectangle",
      position: { x: 100, y: 200 },
      data: { width: 150, height: 100, color: "#FF0000", ... }
    },
    // ... more objects
  ],
  timestamp: 1634567890,
  canvasId: 123 // Optional: prevent cross-canvas paste
}
```

#### Paste Behavior
- **Offset calculation**: Add 20px to both x and y coordinates
- **ID generation**: Create new object IDs (don't reuse source IDs)
- **Selection**: Select newly pasted objects immediately
- **Grouping**: If copying a group, maintain group structure in paste
- **Multi-paste**: Allow pasting same clipboard content multiple times

#### Edge Cases
- Empty selection → Copy does nothing (no error)
- Locked objects → Copy succeeds, paste creates unlocked copies
- Paste with no copied data → No action
- Cross-canvas paste → Allow (user may want to copy between canvases)

### Implementation Tasks

1. **Frontend (JavaScript)**
   - Add keyboard event listeners for Cmd/Ctrl+C/V/X
   - Implement clipboard storage (sessionStorage or in-memory)
   - Calculate paste offset positions
   - Emit `paste_objects` event to server with object data

2. **Backend (LiveView)**
   - Handle `paste_objects` event
   - Create new objects in database (bulk insert)
   - Broadcast object creation to all clients
   - Preserve object properties (color, size, rotation, etc.)

3. **UI Feedback**
   - Show toast notification: "Copied N objects"
   - Visual feedback on paste (brief highlight or animation)
   - Disable paste button/shortcut when clipboard empty

### Acceptance Criteria

- [ ] Cmd+C copies selected objects without visual change
- [ ] Cmd+V pastes objects with 20px x/y offset
- [ ] Pasted objects are immediately selected
- [ ] Can paste same objects multiple times with incremental offsets
- [ ] Multi-object paste maintains relative positions
- [ ] Works across different browser tabs (same session)
- [ ] Cmd+X cuts (copies + deletes) selected objects
- [ ] No errors when copying/pasting empty selection

### Performance Requirements
- Copy operation: < 50ms for up to 100 objects
- Paste operation: < 200ms for up to 100 objects (includes DB write)

---

## Feature 2: Context-Aware Layer Panel

### Overview
Create an intelligent layer management panel that shows context-sensitive layer information based on current selection. When objects are selected, show their relative z-index ordering and allow drag-to-reorder.

### Current State
- All objects (up to 50) displayed in a list
- Right-click context menu to move forward/back (works)
- Z-index management system exists in backend
- No visual drag-to-reorder interface

### User Stories

**As a canvas user:**
- I want to see only relevant layers when I select objects (not all 50)
- I want to drag layers up/down to reorder their z-index
- I want visual feedback showing which layer is selected
- I want to see layer thumbnails or icons for quick identification
- I want the layer panel to update in real-time when other users reorder

### Technical Requirements

#### Display Modes

**Mode 1: No Selection**
- Show all canvas objects (current behavior)
- Sorted by z-index (bottom to top)
- Limit to 50 objects with scroll

**Mode 2: Single Object Selected**
- Show object's "layer neighborhood":
  - 2 objects below (lower z-index)
  - Selected object (highlighted)
  - 2 objects above (higher z-index)
- Total: 5 objects maximum
- Highlight selected object with blue border

**Mode 3: Multiple Objects Selected**
- Show only selected objects
- Sorted by relative z-index within selection
- Highlight all selected objects
- Allow reordering within group

#### Layer Item Display
Each layer shows:
- **Thumbnail**: Small preview (40x40px) of object
  - Rectangle: filled rect with border
  - Circle: filled circle
  - Text: "T" icon with preview text
  - Group: folder icon
- **Name**: Auto-generated or user-defined
  - Format: `{Type} #{id}` (e.g., "Rectangle #42")
- **Lock indicator**: Padlock icon if locked by another user
- **Visibility toggle**: Eye icon (future feature, grayed out for now)

#### Drag-to-Reorder Behavior

**Interaction:**
1. User clicks and holds on layer item
2. Item becomes semi-transparent (opacity: 0.7)
3. Drag up/down within panel
4. Drop zone shows blue line indicating insert position
5. On release, update z-index in database

**Z-Index Calculation:**
- Dragging layer A above layer B: Set `A.z_index = B.z_index + 1`
- Recalculate all affected z-indices to maintain gaps
- Broadcast changes to all clients via PubSub

**Constraints:**
- Cannot reorder locked objects (show error toast)
- Reordering in multi-select mode only affects selected objects
- Real-time updates: other users see reorder immediately

### Implementation Tasks

1. **Database Schema** (if needed)
   - Add `name` field to `objects` table (optional, can use auto-generated)
   - Ensure `z_index` field exists and is indexed

2. **Frontend (React Component or LiveView)**
   - Create `LayerPanel` component
   - Implement drag-and-drop library integration (e.g., `react-beautiful-dnd` or native)
   - Add selection mode detection logic
   - Render layer thumbnails (mini canvas or SVG icons)
   - Handle drag start/end events

3. **Backend (LiveView Event Handlers)**
   - Handle `reorder_layer` event with `object_id` and `new_z_index`
   - Calculate z-index updates for affected objects
   - Update database in transaction
   - Broadcast `{:layers_reordered, updates}` to all clients

4. **Real-Time Sync**
   - Subscribe to `{:layers_reordered, updates}` in `handle_info/2`
   - Update layer panel without flicker
   - Highlight changed layers briefly (flash animation)

### UI Mockup (Text Description)

```
┌─────────────────────────────────┐
│  Layers                    [ ] │
├─────────────────────────────────┤
│  ┌───┐                          │
│  │ ▪ │  Rectangle #15      🔒  │ ← Locked by other user
│  └───┘                          │
├─────────────────────────────────┤
│  ┌───┐                          │
│  │ ○ │  Circle #12         ✓   │ ← Selected (blue border)
│  └───┘                          │
├─────────────────────────────────┤
│  ┌───┐                          │
│  │ T │  Text #8                │
│  └───┘                          │
└─────────────────────────────────┘
```

### Acceptance Criteria

- [ ] Panel shows all objects when nothing selected
- [ ] Panel shows 5-object neighborhood for single selection
- [ ] Panel shows only selected objects for multi-selection
- [ ] Can drag layer items up/down smoothly
- [ ] Blue drop indicator shows insert position during drag
- [ ] Z-index updates immediately on drop
- [ ] Other users see layer reorder in real-time (< 200ms)
- [ ] Cannot drag locked objects (shows error toast)
- [ ] Layer thumbnails accurately represent object type
- [ ] Selected layers have blue highlight border

### Performance Requirements
- Layer panel render: < 100ms for 50 objects
- Drag-to-reorder: < 50ms visual feedback
- Z-index update + broadcast: < 200ms

---

## Feature 3: Auto-Layout System (Tier 3)

### Overview
Implement a Figma-style auto-layout system that applies flexbox-like rules to groups of objects, automatically managing spacing, sizing, and alignment. This is a Tier 3 advanced feature worth significant rubric points.

### User Stories

**As a canvas user:**
- I want to apply auto-layout to a group of objects
- I want objects to automatically space themselves evenly
- I want to set horizontal or vertical layout direction
- I want to define padding and gap between objects
- I want objects to resize automatically when I change properties
- I want auto-layout to work with real-time collaboration

### Technical Requirements

#### Auto-Layout Properties

**Container Properties:**
- **Direction**: `horizontal` | `vertical`
- **Alignment**: `start` | `center` | `end` | `stretch`
- **Spacing**: Gap between child objects (px)
- **Padding**: Internal padding around children (px)
- **Wrap**: `wrap` | `nowrap` (if objects exceed container width/height)

**Child Properties:**
- **Grow**: Proportion of available space to fill (0 = fixed size, 1+ = flexible)
- **Shrink**: Whether object can shrink below min size (0 or 1)
- **Min Width/Height**: Minimum dimensions (px)
- **Max Width/Height**: Maximum dimensions (px, optional)

#### Data Model

**Database Schema Addition:**
Add `auto_layout` JSON field to `objects` table:
```elixir
%{
  enabled: true,
  direction: "horizontal",
  alignment: "center",
  spacing: 12,
  padding: 16,
  wrap: false
}
```

Add `auto_layout_child` JSON field for child-specific properties:
```elixir
%{
  grow: 1,
  shrink: 1,
  min_width: 50,
  min_height: 30
}
```

#### Layout Algorithm

**Step 1: Detect Auto-Layout Container**
- User selects multiple objects → Right-click → "Apply Auto-Layout"
- Creates invisible container group with auto-layout properties
- Children become part of auto-layout system

**Step 2: Calculate Layout**
```javascript
function calculateAutoLayout(container, children) {
  const { direction, alignment, spacing, padding } = container.auto_layout;

  // 1. Calculate available space
  const availableSpace = direction === 'horizontal'
    ? container.width - (padding * 2) - (spacing * (children.length - 1))
    : container.height - (padding * 2) - (spacing * (children.length - 1));

  // 2. Distribute space based on grow factors
  const totalGrow = children.reduce((sum, child) => sum + child.auto_layout_child.grow, 0);

  children.forEach((child, index) => {
    const growRatio = child.auto_layout_child.grow / totalGrow;
    const allocatedSpace = availableSpace * growRatio;

    // 3. Apply constraints (min/max)
    const finalSize = Math.max(
      child.auto_layout_child.min_width,
      Math.min(child.auto_layout_child.max_width || Infinity, allocatedSpace)
    );

    // 4. Position child
    if (direction === 'horizontal') {
      child.width = finalSize;
      child.x = padding + (index * (finalSize + spacing));
      child.y = calculateAlignment(alignment, container.height, child.height);
    } else {
      child.height = finalSize;
      child.y = padding + (index * (finalSize + spacing));
      child.x = calculateAlignment(alignment, container.width, child.width);
    }
  });
}
```

**Step 3: Real-Time Updates**
- When user drags auto-layout container → Children move together
- When user resizes container → Recalculate child sizes/positions
- When user adds/removes child → Recalculate entire layout
- Broadcast updates via PubSub

#### UI Controls

**Auto-Layout Panel** (appears when container selected):
```
┌─────────────────────────────────┐
│  Auto-Layout Settings            │
├─────────────────────────────────┤
│  Direction:  ○ Horizontal        │
│              ● Vertical          │
│                                  │
│  Alignment:  [Start ▼]           │
│  Spacing:    [12   px]           │
│  Padding:    [16   px]           │
│  Wrap:       [ ] Enable          │
├─────────────────────────────────┤
│  [Remove Auto-Layout]            │
└─────────────────────────────────┘
```

**Child Properties** (appears when child selected):
```
┌─────────────────────────────────┐
│  Auto-Layout Child               │
├─────────────────────────────────┤
│  Grow:      [1    ]              │
│  Shrink:    [☑] Allow            │
│  Min Width: [50   px]            │
│  Max Width: [     px] (optional) │
└─────────────────────────────────┘
```

### Implementation Tasks

1. **Database Migration**
   - Add `auto_layout` JSON column to `objects` table
   - Add `auto_layout_child` JSON column to `objects` table
   - Add migration rollback support

2. **Backend (Elixir)**
   - Create `AutoLayout` module with layout calculation logic
   - Add `apply_auto_layout/2` function to Canvases context
   - Add `update_auto_layout/3` function for property changes
   - Handle layout recalculation on child add/remove

3. **Frontend (JavaScript)**
   - Create `AutoLayoutManager` class
   - Implement layout calculation algorithm (mirrors backend)
   - Add UI controls for auto-layout properties
   - Handle real-time layout updates

4. **LiveView Integration**
   - Handle `apply_auto_layout` event
   - Handle `update_auto_layout` event
   - Broadcast layout changes via PubSub
   - Add `handle_info/2` for layout updates

5. **AI Agent Integration**
   - Add AI tool: `apply_auto_layout`
   - Enable commands like "arrange these in a horizontal auto-layout with 20px spacing"
   - Support complex commands: "create a button group with auto-layout"

### Acceptance Criteria

- [ ] Can apply auto-layout to selected objects (right-click menu)
- [ ] Auto-layout panel shows container properties
- [ ] Can change direction (horizontal/vertical) with immediate effect
- [ ] Can adjust spacing/padding with live preview
- [ ] Children resize based on grow/shrink factors
- [ ] Alignment options work correctly (start/center/end/stretch)
- [ ] Adding new object to container triggers recalculation
- [ ] Removing object from container triggers recalculation
- [ ] Resizing container redistributes space to children
- [ ] Real-time sync: other users see layout changes immediately
- [ ] Can remove auto-layout (converts to regular group)
- [ ] AI commands can create auto-layout containers

### Performance Requirements
- Layout calculation: < 100ms for up to 20 children
- Real-time update: < 200ms from user action to all clients
- Resize recalculation: < 50ms for smooth interaction

### Edge Cases
- **Locked children**: Skip locked objects in layout calculation, maintain position
- **Nested auto-layouts**: Support auto-layout containers within auto-layouts (max 2 levels)
- **Insufficient space**: Shrink objects to min size, then clip if still insufficient
- **Empty container**: Show placeholder message "Add objects to enable auto-layout"

---

## Implementation Priority

### Phase 1: Copy/Paste (Estimated: 2-3 days)
1. Keyboard shortcuts (0.5 day)
2. Clipboard storage (0.5 day)
3. Paste logic with offset (1 day)
4. Backend integration (0.5 day)
5. Testing (0.5 day)

### Phase 2: Layer Panel (Estimated: 3-4 days)
1. Context-aware display logic (1 day)
2. Drag-to-reorder UI (1.5 days)
3. Z-index calculation (0.5 day)
4. Real-time sync (0.5 day)
5. Testing (0.5 day)

### Phase 3: Auto-Layout (Estimated: 5-7 days)
1. Database schema (0.5 day)
2. Layout algorithm (2 days)
3. UI controls (1.5 days)
4. LiveView integration (1 day)
5. AI tool integration (0.5 day)
6. Testing (1 day)

**Total estimated time**: 10-14 days

---

## Success Metrics

### Rubric Score Impact
- **Section 3 (Advanced Features)**: 4-6 points → 13-15 points ✅
- **Overall project score**: 55-65 → 75-85 (C → B/A range)

### User Experience Metrics
- Copy/paste usage: > 10 operations per user session
- Layer reorder usage: > 5 operations per user session
- Auto-layout adoption: > 30% of groups use auto-layout

### Technical Metrics
- Copy/paste success rate: > 99%
- Layer reorder conflicts: < 1% (multi-user edge case)
- Auto-layout calculation errors: 0%

---

## Dependencies

### Technical Dependencies
- Existing object grouping system ✓
- Z-index management ✓
- Real-time PubSub infrastructure ✓
- LiveView event handling ✓

### External Libraries
- Drag-and-drop library (e.g., `@dnd-kit/core` for React or native HTML5)
- No additional backend dependencies needed

### Risk Mitigation
- **Risk**: Drag-and-drop UX complexity
  - **Mitigation**: Use proven library, test extensively with multi-user scenarios
- **Risk**: Auto-layout performance with large groups
  - **Mitigation**: Limit max children to 50, optimize calculation algorithm
- **Risk**: Real-time sync conflicts during layout changes
  - **Mitigation**: Use optimistic UI updates, server is source of truth

---

## Testing Strategy

### Unit Tests
- Copy/paste: clipboard storage, offset calculation, ID generation
- Layer panel: context detection, z-index calculation
- Auto-layout: layout algorithm with various configurations

### Integration Tests
- Copy/paste: end-to-end with database
- Layer panel: drag-to-reorder with real-time sync
- Auto-layout: multi-user layout changes

### E2E Tests (Puppeteer)
- Copy/paste: keyboard shortcuts in browser
- Layer panel: drag-and-drop interaction
- Auto-layout: resize container, observe children

### Performance Tests
- Copy/paste: 100 objects
- Layer panel: 50 objects with rapid reordering
- Auto-layout: 20 children with rapid resize

---

## Documentation Updates

### User Documentation
- Add keyboard shortcuts reference (Cmd+C/V/X)
- Layer panel usage guide with screenshots
- Auto-layout tutorial with examples

### Developer Documentation
- Update CLAUDE.md with new features
- Add auto-layout algorithm explanation
- Document AI tool integration for auto-layout

### API Documentation
- New LiveView events: `paste_objects`, `reorder_layer`, `apply_auto_layout`
- New PubSub messages: `{:layers_reordered, updates}`, `{:auto_layout_applied, container}`

---

## Open Questions

1. **Copy/Paste**: Should we support rich clipboard data for paste into other apps (e.g., SVG)?
   - **Decision**: Phase 2 feature, start with internal clipboard only

2. **Layer Panel**: Should we show object thumbnails or just icons?
   - **Recommendation**: Icons for MVP, thumbnails in Phase 2

3. **Auto-Layout**: Should we support percentage-based sizing (like CSS)?
   - **Decision**: Fixed pixels only for MVP, percentages in Phase 2

4. **Auto-Layout**: Maximum nesting depth?
   - **Decision**: 2 levels max (container → children with auto-layout)

---

## Appendix: AI Tool Definitions

### Tool: apply_auto_layout
```json
{
  "name": "apply_auto_layout",
  "description": "Apply flexbox-like auto-layout to selected objects with automatic spacing and sizing",
  "input_schema": {
    "type": "object",
    "properties": {
      "object_ids": {
        "type": "array",
        "items": { "type": "integer" },
        "description": "IDs of objects to include in auto-layout container"
      },
      "direction": {
        "type": "string",
        "enum": ["horizontal", "vertical"],
        "description": "Layout direction"
      },
      "spacing": {
        "type": "number",
        "description": "Gap between objects in pixels"
      },
      "padding": {
        "type": "number",
        "description": "Internal padding in pixels"
      }
    },
    "required": ["object_ids", "direction"]
  }
}
```

### Example AI Commands
- "Apply horizontal auto-layout to these buttons with 12px spacing"
- "Create a vertical auto-layout for this list with 8px gaps"
- "Make this group an auto-layout container with center alignment"

---

**End of PRD**
