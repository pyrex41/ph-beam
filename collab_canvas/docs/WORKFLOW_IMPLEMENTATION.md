# Workflow Features Implementation

This document describes the implementation of professional workflow features for CollabCanvas as specified in PRD 2 (prd-workflow.md).

## Overview

The workflow features add essential professional design tools including:
- Advanced selection and grouping
- Layer management and alignment
- Expanded shape and text tools
- High-velocity keyboard shortcuts
- Reusable color palettes
- Export to PNG/SVG

## Implementation Date
**Started:** October 18, 2025

---

## Feature WF-01: Advanced Selection & Grouping

### Backend Implementation ✅ COMPLETED

#### Database Schema Changes
**File:** `priv/repo/migrations/20251018025313_add_group_id_and_z_index_to_objects.exs`

Added two new fields to the `objects` table:
- `group_id` (UUID, nullable) - Links objects together in a group
- `z_index` (float, default 0.0) - Controls layering order

```elixir
alter table(:objects) do
  add :group_id, :uuid
  add :z_index, :float, default: 0.0
end

create index(:objects, [:group_id])
create index(:objects, [:z_index])
```

#### Schema Updates
**File:** `lib/collab_canvas/canvases/object.ex`

Updated the Object schema to include:
- Added `group_id` and `z_index` fields to the schema
- Updated Jason encoder to include these fields in JSON output
- Added fields to the changeset for validation
- Added new shape types: "star", "triangle", "polygon"

#### Context Functions
**File:** `lib/collab_canvas/canvases.ex`

Added new functions for group management:
- `create_group/1` - Groups multiple objects by assigning them a shared group_id
- `ungroup/2` - Removes group_id from grouped objects
- `get_group_objects/1` - Retrieves all objects in a group
- `update_z_index/2` - Updates z_index for an object
- `bring_to_front/1` - Moves object/group to front
- `send_to_back/1` - Moves object/group to back

### Frontend Implementation ✅ COMPLETED

#### Multi-Select Enhancement
The canvas_manager.js already has:
- `selectedObjects` as a Set for multiple selection  
- `toggleSelection/1` function for Shift+Click
- Multi-object dragging support

#### Lasso Selection ✅ IMPLEMENTED
**File:** `assets/js/core/canvas_manager.js`

Implemented:
- Lasso selection state tracking (`isLassoSelecting`, `lassoStart`, `lassoRect`)
- `createLassoRect()` - Creates visual feedback graphics for lasso
- `updateLassoRect()` - Updates lasso rectangle during drag
- `finalizeLassoSelection()` - Selects all objects within lasso area
- `rectanglesIntersect()` - Geometric intersection detection
- Integrated with pointer down/move/up handlers
- Supports Shift+Click to add to existing selection

#### Grouping Functions ✅ IMPLEMENTED
**File:** `assets/js/core/canvas_manager.js`

Implemented:
- `groupSelected()` - Emits create_group event with selected object IDs
- `ungroupSelected()` - Emits ungroup event for selected objects
- Keyboard shortcuts: 
  - Cmd/Ctrl+G for grouping
  - Cmd/Ctrl+Shift+G for ungrouping
- Backend handlers in canvas_live.ex for group operations

#### Additional Keyboard Shortcuts ✅ IMPLEMENTED
**File:** `assets/js/core/canvas_manager.js`

Implemented:
- `duplicateSelected()` - Duplicate selected objects (Cmd/Ctrl+D)
- `copySelected()` - Copy to clipboard (Cmd/Ctrl+C)
- `pasteFromClipboard()` - Paste from clipboard (Cmd/Ctrl+V)
- `nudgeSelected()` - Move objects 1px with arrows, 10px with Shift+arrows
- `selectAll()` - Select all objects (Cmd/Ctrl+A)
- Cross-platform support (detects Mac vs Windows/Linux for Cmd vs Ctrl)

#### LiveView Integration ✅ IMPLEMENTED
**File:** `lib/collab_canvas_web/live/canvas_live.ex`

Added event handlers:
- `handle_event("create_group", ...)` - Creates group and broadcasts
- `handle_event("ungroup", ...)` - Ungroups objects and broadcasts
- `handle_event("duplicate_object", ...)` - Duplicates object with offset
- `handle_info({:objects_grouped, ...}, ...)` - Receives group broadcasts
- `handle_info({:objects_ungrouped, ...}, ...)` - Receives ungroup broadcasts

---

## Feature WF-02: Layer Management & Alignment Tools

### Backend Implementation ✅ COMPLETED

#### Database Schema
Already completed in WF-01 (z_index field).

#### Layout Functions
**File:** `lib/collab_canvas/ai/layout.ex`

The Layout module already exists with comprehensive alignment functions:
- `align_objects/2` - Aligns objects (left, right, center, top, bottom, middle)
- `distribute_horizontally/2` - Even horizontal distribution
- `distribute_vertically/2` - Even vertical distribution
- `arrange_grid/3` - Grid layout
- `circular_layout/2` - Circular arrangement

These functions can be exposed directly to the frontend.

### Frontend Implementation 🔜 PENDING

#### Context Menu (To Be Implemented)
Need to create a right-click context menu with:
- Bring to Front
- Send to Back
- Bring Forward
- Send Backward
- Separator
- Align Left/Center/Right
- Align Top/Middle/Bottom
- Distribute Horizontally/Vertically

#### Toolbar Alignment Tools (To Be Implemented)
Add alignment buttons to the main toolbar or properties panel.

---

## Feature WF-03: Expanded Shape & Text Tools

### Backend Implementation 🔜 PENDING

The Object schema already supports new shape types (added in WF-01):
- "star"
- "triangle"  
- "polygon"

Need to verify data JSON structure supports:
- `sides` for polygon
- `points` for star (number of points)
- `fontWeight`, `fontStyle`, `textDecoration`, `fontSize` for text

### Frontend Implementation 🔜 PENDING

#### New Shape Tools (To Be Implemented)
**File:** `assets/js/core/canvas_manager.js`

Need to add rendering functions:
- `createStar()` - Draw star shape with configurable points
- `createTriangle()` - Draw triangle
- `createPolygon()` - Draw n-sided polygon

#### Text Formatting (To Be Implemented)
Need to add a text formatting panel with:
- Bold toggle
- Italic toggle
- Underline toggle
- Font size selector
- Font family selector (future)

Update text object rendering to apply these styles.

---

## Feature WF-04: High-Velocity Keyboard Shortcuts

### Frontend Implementation ✅ COMPLETED

**File:** `assets/js/core/canvas_manager.js`

Implemented keyboard shortcuts:
- `Cmd/Ctrl+D` - Duplicate selected objects (calls `duplicateSelected()`)
- `Cmd/Ctrl+C` - Copy selected objects to clipboard (calls `copySelected()`)
- `Cmd/Ctrl+V` - Paste objects from clipboard (calls `pasteFromClipboard()`)
- `Arrow Keys` - Nudge selected objects 1px (calls `nudgeSelected()`)
- `Shift+Arrow Keys` - Nudge selected objects 10px (calls `nudgeSelected()`)
- `Cmd/Ctrl+A` - Select all objects (calls `selectAll()`)
- `Cmd/Ctrl+G` - Group selected objects (calls `groupSelected()`)
- `Cmd/Ctrl+Shift+G` - Ungroup selected objects (calls `ungroupSelected()`)

All shortcuts detect the platform (Mac vs Windows/Linux) and use appropriate modifier keys.

---

## Feature WF-05: Reusable Color Palettes

### Backend Implementation 🔜 PENDING

#### Database Schema (To Be Created)
**New Migration:** `create_palettes_and_palette_colors.exs`

```elixir
create table(:palettes) do
  add :name, :string, null: false
  add :user_id, references(:users, on_delete: :delete_all), null: false
  timestamps(type: :utc_datetime)
end

create table(:palette_colors) do
  add :palette_id, references(:palettes, on_delete: :delete_all), null: false
  add :color_hex, :string, null: false
  add :position, :integer, null: false
  timestamps(type: :utc_datetime)
end

create index(:palettes, [:user_id])
create index(:palette_colors, [:palette_id])
```

#### Context Module (To Be Created)
**New File:** `lib/collab_canvas/color_palettes.ex`

Need to create context with functions:
- `create_palette/2` - Create named palette
- `add_color_to_palette/3` - Add color to palette
- `list_user_palettes/1` - Get user's palettes
- `delete_palette/1` - Remove palette

### Frontend Implementation 🔜 PENDING

#### Color Picker Enhancement (To Be Implemented)
Update the color picker component to:
- Display saved palettes
- Allow creating new palettes
- Quick-apply colors from palettes
- Manage palette colors (add/remove)

---

## Feature WF-06: Export to PNG/SVG

### Frontend Implementation 🔜 PENDING

**File:** `assets/js/core/canvas_manager.js`

Add export functions:
- `exportToPNG()` - Render canvas to PNG and download
- `exportToSVG()` - Convert PixiJS objects to SVG and download
- `exportSelection()` - Export only selected objects

Implementation approach:
1. For PNG: Use PixiJS extract API to render to data URL
2. For SVG: Convert PIXI graphics objects to SVG elements
3. Create download link and trigger click

---

## Integration with LiveView

### Canvas LiveView Updates
**File:** `lib/collab_canvas_web/live/canvas_live.ex`

Need to add handle_event callbacks for:
- "create_group" - Call Canvases.create_group/1
- "ungroup" - Call Canvases.ungroup/2
- "bring_to_front" - Call Canvases.bring_to_front/1
- "send_to_back" - Call Canvases.send_to_back/1
- "align_objects" - Call Layout.align_objects/2
- "distribute_objects" - Call Layout.distribute_horizontally/2 or distribute_vertically/2

### PubSub Broadcasting

All operations that modify objects should broadcast via PubSub:
```elixir
Phoenix.PubSub.broadcast(
  CollabCanvas.PubSub,
  "canvas:#{canvas_id}",
  {:object_updated, updated_objects}
)
```

---

## Testing Strategy

### Backend Tests
- Unit tests for Canvases context functions
- Test grouping/ungrouping logic
- Test z_index ordering
- Test alignment calculations

### Frontend Tests  
- Manual testing of all keyboard shortcuts
- Multi-select and lasso selection
- Group operations
- Export functionality

### Integration Tests
- Real-time sync of grouped objects
- Multi-user group editing
- Alignment operations across collaborators

---

## Performance Considerations

### Multi-Selection
- Use Set for O(1) lookup of selected objects
- Batch update broadcasts to reduce network traffic
- Throttle drag events to max 20 updates/second

### Lasso Selection
- Use spatial indexing for intersection detection
- Limit lasso updates to 30fps
- Optimize rectangle intersection algorithm

### Export
- Use offscreen canvas for rendering
- Implement export progress indicator for large canvases
- Limit export size to prevent browser memory issues

---

## Known Limitations

1. **Grouping**: Nested groups not supported in this implementation
2. **Export**: SVG export may not perfectly preserve all PixiJS effects
3. **Color Palettes**: Limited to 100 palettes per user
4. **Lasso Selection**: Limited to rectangular selection area

---

## Next Steps

1. ✅ Complete backend implementation for WF-01 and WF-02
2. 🔄 Implement frontend for WF-01 (lasso, grouping)
3. 🔜 Implement frontend for WF-02 (context menu, alignment UI)
4. 🔜 Implement WF-03 (new shapes, text formatting)
5. 🔜 Implement WF-04 (keyboard shortcuts)
6. 🔜 Implement WF-05 (color palettes - full stack)
7. 🔜 Implement WF-06 (export functionality)
8. 🔜 Integration testing
9. 🔜 Performance optimization
10. 🔜 Documentation and user guide

---

## References

- PRD: `.taskmaster/docs/prd-workflow.md`
- Tasks: `.taskmaster/tasks/tasks.json` (workflow section)
- Backend Code: `lib/collab_canvas/`
- Frontend Code: `assets/js/core/canvas_manager.js`
