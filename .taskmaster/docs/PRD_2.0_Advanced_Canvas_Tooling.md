# PRD 2.0: Advanced Canvas Tooling

## Executive Summary

This PRD defines the requirements for essential Figma-like features that transform the canvas from a basic drawing tool into a powerful, precise design tool. These features enable professional designers to work efficiently with complex compositions.

**PixiJS v8 Compatibility:** This PRD is written for PixiJS v8.x (latest: v8.13.2). Key API changes from v7:
- `getBounds()` now returns a `Bounds` object; use `.rectangle` to access the Rectangle (e.g., `object.getBounds().rectangle`)
- Graphics, Sprite, Mesh can no longer have children - only Container can have children
- All code examples in this PRD reflect v8 API usage

## Performance Requirements

- **Selection Operations:** Multi-select and transformation operations must complete in <50ms
- **Layer Panel Updates:** Layer hierarchy changes must reflect in <100ms across all clients
- **Smart Guides:** Guide calculations and rendering must not impact frame rate (<16ms per frame)
- **Rendering:** Maintain 60 FPS with 500+ objects during any transformation operation

## Core Features

### 2.1 Advanced Selection & Transformation

**User Story:** As a designer, I can select multiple objects by holding Shift or dragging a selection box, and I can resize and rotate them using interactive handles.

**Requirements:**

1. **Multi-Selection Implementation**
   - Click to select single object
   - Shift+Click to add/remove objects from selection
   - Drag to create selection rectangle (marquee selection)
   - Cmd/Ctrl+A to select all objects
   - ESC to clear selection
   - Click on empty canvas area to deselect all

2. **Selection Bounding Box**
   - Calculate and display bounding box around all selected objects
   - Bounding box should update in real-time as objects move
   - Different visual styles for single vs. multi-select
   - Show selection count when multiple objects selected

3. **Resize Handles**
   - 8 resize handles (4 corners, 4 edges)
   - Corner handles: proportional resize by default
   - Edge handles: resize along one axis only
   - Hold Shift: force proportional resize from edges
   - Hold Alt/Option: resize from center
   - Visual feedback during resize (show dimensions)

4. **Rotation Handle**
   - Single rotation handle above the selection bounding box
   - Drag to rotate around the center point
   - Hold Shift while rotating: snap to 15-degree increments
   - Display rotation angle during operation
   - Rotation pivot point indicator

5. **Transformation Persistence**
   - All transformations must update the underlying object data
   - Maintain aspect ratios when specified
   - Preserve relative positions in multi-select transforms
   - Broadcast all transformations in real-time to collaborators

**Technical Implementation:**

- **Frontend (`hooks/canvas_renderer.js`):**
  - Add `selectionManager` class to track selected object IDs
  - Implement marquee selection using PixiJS Graphics (draw selection rectangle)
  - Create `TransformControls` component for handles (drawn with Graphics, added to a Container)
  - Add keyboard event listeners for modifiers
  - Calculate bounding boxes: use `object.getBounds().rectangle` (PixiJS v8 API) for AABB (Axis-Aligned Bounding Box)

- **Backend:**
  - Add `rotation` field to Object schema (float, default 0)
  - Enhance `update_object` event to handle batch updates for multi-select
  - Add `transform_objects` event for batch transformations
  - Validate transformation constraints server-side

**Database Schema Changes:**

```elixir
# Add to Object schema
field :rotation, :float, default: 0.0
field :scale_x, :float, default: 1.0
field :scale_y, :float, default: 1.0
```

**Acceptance Criteria:**

- Users can select multiple objects using Shift+Click or marquee
- Resize handles work correctly with proper constraints
- Rotation handle allows smooth rotation with angle display
- All transformations sync in real-time across clients
- Keyboard modifiers work as expected (Shift, Alt, Cmd/Ctrl)

---

### 2.2 Layers Panel

**User Story:** As a designer, I can see a list of all objects in a layers panel, change their stacking order (Z-index) by dragging them, and group them into folders.

**Requirements:**

1. **Layer List Display**
   - Show hierarchical list of all canvas objects
   - Display object type icons (rect, circle, text, image)
   - Show object names (editable inline)
   - Indicate selected objects with highlight
   - Show visibility toggle (eye icon) for each object
   - Show lock status for each object

2. **Z-Index Management**
   - Drag-and-drop to reorder objects in the list
   - Higher position in list = higher z-index (on top)
   - Real-time visual feedback during drag
   - Broadcast z-index changes to all clients
   - Keyboard shortcuts: Cmd+] (bring forward), Cmd+[ (send backward)

3. **Object Grouping**
   - Create folder/group containers
   - Drag objects into groups
   - Expand/collapse groups
   - Move entire groups as single units
   - Nested groups support (up to 5 levels deep)
   - Auto-name groups (e.g., "Group 1", "Group 2")

4. **Layer Operations**
   - Right-click context menu: rename, duplicate, delete, group
   - Double-click to rename object
   - Click to select object (highlights on canvas)
   - Multi-select in layers panel with Shift/Cmd
   - Search/filter objects by name or type

**Technical Implementation:**

- **Frontend:**
  - Create new LiveComponent: `LayerPanelLive`
  - Mount in `CanvasLive` template
  - Use HTML5 drag-and-drop API or sortable.js
  - Implement collapsible tree structure

- **Backend:**
  - Add `z_index` field to Object schema (integer)
  - Add `parent_id` field for grouping (self-referential foreign key)
  - Add `name` field (string, default to "Rectangle 1", etc.)
  - Add `visible` field (boolean, default true)
  - Create `update_z_index` event handler
  - Create `group_objects` and `ungroup_objects` event handlers

**Database Schema Changes:**

```elixir
# Add to Object schema
field :z_index, :integer, default: 0
field :parent_id, :id  # Self-referential for grouping
field :name, :string
field :visible, :boolean, default: true
```

**API Changes:**

```elixir
# New events
handle_event("update_z_index", %{"object_id" => id, "new_index" => index}, socket)
handle_event("rename_object", %{"id" => id, "name" => name}, socket)
handle_event("toggle_visibility", %{"id" => id}, socket)
handle_event("group_objects", %{"object_ids" => ids, "group_name" => name}, socket)
handle_event("ungroup_objects", %{"group_id" => id}, socket)
```

**Acceptance Criteria:**

- All objects appear in layers panel with correct hierarchy
- Drag-and-drop reordering works smoothly and syncs across clients
- Objects can be grouped into folders with expand/collapse
- Visibility toggle affects canvas rendering immediately
- Search/filter functionality works correctly
- Layer panel reflects selection state from canvas and vice versa

---

### 2.3 Object Grouping

**User Story:** As a user, I can select multiple objects and group them, so they move and transform together as a single unit.

**Requirements:**

1. **Group Creation**
   - Select 2+ objects and use keyboard shortcut Cmd+G to group
   - Right-click menu option: "Group Selection"
   - Create new group object containing selected objects
   - Auto-generate group name or allow custom name
   - Groups appear as folders in layers panel

2. **Group Transformations**
   - Selecting a group selects all child objects
   - Moving a group moves all children relative to their positions
   - Resizing a group scales all children proportionally
   - Rotating a group rotates all children around group center
   - Group has its own bounding box encompassing all children

3. **Group Management**
   - Cmd+Shift+G to ungroup
   - Double-click group to enter isolation mode (edit children)
   - Click outside or press ESC to exit isolation mode
   - Delete group: option to delete children or just the group container
   - Nested groups: groups can contain other groups

4. **Collaborative Group Editing**
   - Broadcast group creation/deletion to all clients
   - Lock entire group when any child is being edited
   - Show which user is editing which group
   - Handle conflicts when multiple users try to group same objects

**Technical Implementation:**

- **Frontend:**
  - Extend `selectionManager` to handle group selections
  - Calculate group bounding boxes recursively
  - Implement isolation mode (dim other objects, show breadcrumb)
  - Apply transformations to child objects based on group transform

- **Backend:**
  - Groups are special Object records with `type: "group"`
  - Child objects reference group via `parent_id`
  - Store group's own position/transform separate from children
  - Context function: `Canvases.group_objects(canvas_id, object_ids, user_id)`
  - Context function: `Canvases.ungroup_objects(canvas_id, group_id)`

**Database Schema:**

```elixir
# Group object data structure
%{
  "type" => "group",
  "name" => "Group 1"
}
# Children have parent_id pointing to group
```

**API Changes:**

```elixir
handle_event("create_group", %{"object_ids" => ids, "name" => name}, socket)
handle_event("enter_group_isolation", %{"group_id" => id}, socket)
handle_event("exit_group_isolation", %{}, socket)
```

**Acceptance Criteria:**

- Multiple objects can be grouped with keyboard shortcut
- Group transformations affect all children correctly
- Ungrouping restores objects to their current positions
- Isolation mode works for editing group contents
- Nested groups work up to 5 levels deep
- All group operations sync across clients in real-time

---

### 2.4 Smart Guides & Snapping

**User Story:** As a designer, when I move an object, I see smart guides that help me align it to the center or edges of other objects or the canvas.

**Requirements:**

1. **Alignment Guides**
   - Show vertical/horizontal guide lines when objects align
   - Guide types:
     - Edge-to-edge alignment (left, right, top, bottom)
     - Center-to-center alignment (horizontal, vertical)
     - Canvas center alignment
   - Display multiple guides simultaneously
   - Guides appear as thin colored lines (magenta/cyan)

2. **Snapping Behavior**
   - Snap distance threshold: 5 pixels (configurable)
   - Snap cursor position to guide when within threshold
   - Visual feedback: line becomes solid when snapped
   - Hold Cmd/Ctrl to temporarily disable snapping
   - Snap to nearest guide when multiple candidates

3. **Distance Indicators**
   - Show distance between objects when dragging
   - Display measurements on guide lines
   - Highlight equal spacing when distributing objects
   - Use canvas units (default: pixels)

4. **Performance Optimization**
   - Calculate guides only for nearby objects (within 500px)
   - Throttle guide calculations to 60 FPS
   - Don't send guide data over network (client-side only)
   - Cache object bounds for quick collision detection

**Technical Implementation:**

- **Frontend Only (`hooks/canvas_renderer.js`):**
  - Create `SmartGuides` class
  - During drag operation, iterate through visible objects
  - Calculate alignment candidates using AABB intersection (use `getBounds().rectangle` for each object)
  - Draw temporary guide lines using PixiJS Graphics (added to a Container overlay layer)
  - Adjust drag position when within snap threshold
  - Clear guides on mouse up (remove Graphics from Container)

**Algorithm for Guide Detection:**

```javascript
function findAlignmentGuides(draggingObject, allObjects, snapThreshold = 5) {
  const guides = [];
  // PixiJS v8: getBounds() returns Bounds object, use .rectangle to get Rectangle
  const bounds = draggingObject.getBounds().rectangle;

  for (const obj of allObjects) {
    if (obj.id === draggingObject.id) continue;
    // PixiJS v8: getBounds() returns Bounds object, use .rectangle to get Rectangle
    const targetBounds = obj.getBounds().rectangle;

    // Check vertical alignment
    if (Math.abs(bounds.left - targetBounds.left) < snapThreshold) {
      guides.push({ type: 'vertical', x: targetBounds.left, align: 'left' });
    }
    if (Math.abs(bounds.right - targetBounds.right) < snapThreshold) {
      guides.push({ type: 'vertical', x: targetBounds.right, align: 'right' });
    }
    // ... more alignment checks
  }

  return guides;
}
```

**Acceptance Criteria:**

- Guide lines appear when objects align during drag
- Objects snap to guides within 5px threshold
- Multiple guides can be shown simultaneously
- Cmd/Ctrl key disables snapping
- No performance impact (maintains 60 FPS with 500+ objects)
- Distance measurements are accurate and readable

---

## Testing Requirements

1. **Selection Tests**
   - Test single, multi-select, and marquee selection
   - Test all transformation operations (move, resize, rotate)
   - Verify keyboard modifiers work correctly
   - Test with nested groups

2. **Layers Panel Tests**
   - Test drag-and-drop reordering
   - Test grouping and ungrouping
   - Test visibility toggles
   - Verify sync across multiple clients

3. **Smart Guides Tests**
   - Test all alignment types
   - Test snapping behavior
   - Test snap disable with Cmd/Ctrl
   - Performance test with 500+ objects

4. **Integration Tests**
   - Test selection + layers panel interaction
   - Test groups + smart guides
   - Test collaborative editing of selections/groups

## Success Metrics

- All transformation operations complete within 50ms
- Layer panel updates sync within 100ms
- Smart guides calculate without impacting frame rate
- User efficiency increases by 30% for alignment tasks
- Zero conflicts during collaborative multi-select operations
- User satisfaction rating of 4.5+/5 for canvas tooling
