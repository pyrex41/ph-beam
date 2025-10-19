# CollabCanvas AI Tools Reference

## Complete List of Available AI Tools

This document lists all 19 AI tools available for canvas manipulation. These tools are called by the Claude API when processing natural language commands.

---

## 1. create_shape
**Purpose**: Create basic shapes (rectangles and circles)

**Parameters**:
- `type` (required): "rectangle" | "circle"
- `x` (required): X coordinate (supports semantic positioning!)
- `y` (required): Y coordinate (supports semantic positioning!)
- `width` (required): Width in pixels
- `height`: Height in pixels (defaults to width for circles)
- `fill`: Fill color (hex format, default: "#000000")
- `stroke`: Stroke color (hex format)
- `stroke_width`: Stroke width in pixels
- `count`: Number of identical shapes to create (auto-arranges horizontally)

**Semantic Positioning** (NEW!):
Instead of numeric coordinates, you can use location-based terms:
- **Vertical**: "top", "middle"/"center", "bottom"
- **Horizontal**: "left", "center", "right"
- **Combined**: "top-left", "top-right", "bottom-left", "bottom-right", "top-center", etc.

**Examples**:
```
"create a red rectangle at 100, 100"
"create 5 blue circles"
"create a square with 2px black border"
"create a circle at the top"           ← NEW! Uses viewport position
"create three rectangles in the middle" ← NEW! Centers them
"create a red circle on the left"       ← NEW! Left side of view
"create text at the top-right"          ← NEW! Combination
```

---

## 2. create_text
**Purpose**: Add text elements to the canvas

**Parameters**:
- `text` (required): Text content
- `x` (required): X coordinate (supports semantic positioning!)
- `y` (required): Y coordinate (supports semantic positioning!)
- `font_size`: Font size in pixels (default: 16)
- `font_family`: Font family (default: "Arial")
- `color`: Text color (hex format, default: "#000000")
- `align`: Text alignment ("left" | "center" | "right")

**Examples**:
```
"add text 'Hello World' at 200, 150"
"create large red title at the top"     ← NEW! Uses top of viewport
"add text 'Footer' at the bottom"       ← NEW! Bottom of viewport
"put 'Welcome' in the center"           ← NEW! Center of view
```

---

## 3. move_shape (LEGACY - use move_object instead)
**Purpose**: Move an existing shape

**Parameters**:
- `object_id` (required): ID of object to move
- `x` (required): New X coordinate
- `y` (required): New Y coordinate

---

## 4. resize_shape (LEGACY - use resize_object instead)
**Purpose**: Resize an existing shape

**Parameters**:
- `object_id` (required): ID of object to resize
- `width` (required): New width
- `height` (required): New height

---

## 5. create_component
**Purpose**: Create complex UI components (login forms, buttons, navbars, etc.)

**Parameters**:
- `type` (required): "login_form" | "button" | "card" | "navbar" | "sidebar"
- `x` (required): X coordinate
- `y` (required): Y coordinate
- `width`: Component width (default: 200)
- `height`: Component height (default: 100)
- `theme`: Color theme ("light" | "dark" | "blue" | "green", default: "light")
- `content`: Component-specific configuration object
  - `title`: Component title or label
  - `subtitle`: Secondary text
  - `items`: List of items (for navbars, lists)

**Examples**:
```
"create a login form at 100, 100"
"add a blue navbar at the top"
"create a dark themed card"
```

---

## 6. delete_object
**Purpose**: Remove an object from the canvas

**Parameters**:
- `object_id` (required): ID of object to delete

**Examples**:
```
"delete object 5"
"remove the selected object"
```

---

## 7. group_objects
**Purpose**: Group multiple objects together

**Parameters**:
- `object_ids` (required): Array of object IDs to group
- `group_name`: Name for the group

**Examples**:
```
"group objects 1, 2, and 3"
"group selected objects as 'header'"
```

---

## 8. resize_object
**Purpose**: Resize an object with optional aspect ratio preservation

**Parameters**:
- `object_id` (required): ID of object to resize
- `width` (required): New width
- `height`: New height (optional)
- `maintain_aspect_ratio`: Boolean (default: false)

**Examples**:
```
"resize object 3 to 200px wide"
"make it twice as big"
```

---

## 9. rotate_object
**Purpose**: Rotate an object by a specified angle

**Parameters**:
- `object_id` (required): ID of object to rotate
- `angle` (required): Rotation angle in degrees (0-360)
- `pivot`: Pivot point ("center" | "top-left" | "top-right" | "bottom-left" | "bottom-right", default: "center")

**Examples**:
```
"rotate object 5 by 45 degrees"
"turn it upside down"
```

---

## 10. change_style
**Purpose**: Change styling properties of an object

**Parameters**:
- `object_id` (required): ID of object to style
- `fill`: Fill color (hex format)
- `stroke`: Stroke color (hex format)
- `stroke_width`: Stroke width in pixels
- `opacity`: Opacity (0-1)
- `font_size`: Font size (for text objects)
- `font_family`: Font family (for text objects)
- `font_weight`: Font weight ("normal" | "bold")
- `font_style`: Font style ("normal" | "italic")

**Examples**:
```
"make it blue"
"change the border to red 3px"
"set opacity to 50%"
```

---

## 11. update_text
**Purpose**: Update text content and formatting

**Parameters**:
- `object_id` (required): ID of text object to update
- `text`: New text content
- `font_size`: Font size in pixels
- `font_family`: Font family
- `color`: Text color (hex format)
- `align`: Text alignment ("left" | "center" | "right")

**Examples**:
```
"change the text to 'Updated Title'"
"make the text larger"
```

---

## 12. move_object
**Purpose**: Move an object using delta or absolute coordinates

**Parameters**:
- `object_id` (required): ID of object to move
- `x`: Absolute X coordinate OR delta_x with use_delta=true
- `y`: Absolute Y coordinate OR delta_y with use_delta=true
- `use_delta`: Boolean - if true, x/y are relative offsets (default: false)

**Examples**:
```
"move object 3 to 500, 200"
"move it 50 pixels right"
"shift it down 100px"
```

---

## 13. arrange_objects ⭐ PRIMARY LAYOUT TOOL
**Purpose**: Arrange objects in standard layout patterns (horizontal, vertical, grid, circular, stack)

**Parameters**:
- `object_ids` (required): Array of object IDs to arrange
- `layout_type` (required): "horizontal" | "vertical" | "grid" | "circular" | "stack"
- `spacing`: Spacing between objects in pixels (default: 20)
- `alignment`: Alignment for objects ("left" | "center" | "right" | "top" | "middle" | "bottom")
- `columns`: Number of columns for grid layout (mutually exclusive with rows)
- `rows`: Number of rows for grid layout (mutually exclusive with columns)
- `radius`: Radius for circular layout (default: 200)
  - small/tight: 100-150
  - medium: 200
  - large: 300-500
  - huge: 600-800

**Examples**:
```
"arrange all objects in 3 rows"
"arrange horizontally with 50px spacing"
"arrange in a 4 column grid"
"arrange in a circle" (uses default radius 200)
"arrange in a small circle" (AI should use radius ~100-150)
"arrange in a large circle" (AI should use radius ~300-500)
"arrange in a huge circle" (AI should use radius ~600-800)
```

**IMPORTANT FOR CIRCULAR LAYOUTS**:
- Default radius is 200px (medium circle)
- AI MUST interpret size keywords: small, large, huge, tight, wide
- Objects are distributed evenly around the circle
- Center is calculated from average position of selected objects

---

## 14. show_object_labels
**Purpose**: Toggle visual labels on canvas objects (shows object IDs/names)

**Parameters**:
- `show` (required): Boolean - true to show labels, false to hide

**Examples**:
```
"show object IDs"
"show labels"
"hide labels"
```

---

## 15. arrange_objects_with_pattern
**Purpose**: Arrange objects using flexible programmatic patterns (diagonal, wave, arc)

**NOTE**: For CIRCULAR layouts, use `arrange_objects` instead!

**Parameters**:
- `object_ids` (required): Array of object IDs to arrange
- `pattern` (required): "line" | "diagonal" | "wave" | "arc" | "custom"
- `direction`: "horizontal" | "vertical" | "diagonal-right" | "diagonal-left"
- `spacing`: Spacing between objects (default: 50)
- `alignment`: "start" | "center" | "end" | "baseline"
- `start_x`: Starting X coordinate
- `start_y`: Starting Y coordinate
- `amplitude`: Height of waves/arcs (default: 100)
- `frequency`: Number of waves (default: 2)
- `sort_by`: "none" | "x" | "y" | "size" | "id" (default: "none")

**Examples**:
```
"arrange objects in a diagonal line"
"create a wave pattern"
"arrange in an arc"
```

**Pattern Types**:
- **line**: Straight line (horizontal or vertical)
- **diagonal**: Angled line (diagonal-right or diagonal-left)
- **wave**: Sine wave pattern with amplitude and frequency
- **arc**: Parabolic arc curve

---

## 16. define_object_relationships
**Purpose**: Define spatial relationships using declarative constraints (highly flexible!)

**Parameters**:
- `relationships` (required): Array of relationship constraint objects
  - `subject_id` (required): ID of object being positioned
  - `relation` (required): Relationship type
  - `reference_id` (required): ID of reference object
  - `reference_id_2`: Second reference (for "centered_between")
  - `spacing`: Distance in pixels (default: 20)
- `apply_constraints`: Boolean (default: true)

**Relationship Types**:
- `"above"` - Position subject above reference
- `"below"` - Position subject below reference
- `"left_of"` - Position subject left of reference
- `"right_of"` - Position subject right of reference
- `"aligned_horizontally_with"` - Align Y coordinates
- `"aligned_vertically_with"` - Align X coordinates
- `"centered_between"` - Center subject between two references

**Examples**:
```
"arrange objects in a triangle"
"create a pyramid formation"
"place object 2 below object 1"
"align objects vertically"
```

**Use Cases**:
- Triangles/pyramids (use multiple "below" + "left_of"/"right_of" relationships)
- Hierarchical layouts (organizational charts)
- Symmetric patterns
- Custom geometric formations

---

## 17. select_objects_by_description
**Purpose**: Select objects using natural language descriptions

**Parameters**:
- `description` (required): Natural language description of objects to select
  - Visual properties: "red circles", "small rectangles"
  - Spatial position: "top-left corner", "center", "bottom"
  - Combinations: "all blue objects in the top half"

**Examples**:
```
"select all red circles"
"select the small objects"
"select objects in the top-left corner"
"select all rectangles"
```

**Returns**: Array of object IDs matching the description

---

## 18. arrange_in_star ⭐ NEW!
**Purpose**: Arrange objects in a star pattern with alternating outer/inner points

**Parameters**:
- `object_ids` (required): Array of object IDs to arrange
- `points`: Number of star points (default: 5)
  - 5 = classic 5-pointed star
  - 6 = Star of David / hexagram
  - 3+ = any multi-pointed star
- `outer_radius`: Distance to outer star points in pixels (default: 300)
  - small: 150-200
  - medium: 300
  - large: 400-600
  - huge: 700+
- `inner_radius`: Distance to inner star points (defaults to 40% of outer_radius)

**How it works**:
Objects are placed at alternating outer and inner points radiating from center:
- Even indices (0, 2, 4...) → outer points
- Odd indices (1, 3, 5...) → inner points

**Examples**:
```
"arrange in a star"
"make a 6-pointed star"
"arrange in a small star"
"create a large star pattern"
"arrange 10 objects in a 5-pointed star"
```

**Use Cases**:
- Classic 5-pointed star (☆)
- Star of David (✡)
- Starburst patterns
- Decorative radial arrangements

---

## 19. arrange_along_path ⭐ NEW! MOST FLEXIBLE TOOL
**Purpose**: Arrange objects along geometric paths (line, arc, bezier curve, spiral)

**Path Types**:

### LINE - Straight line between two points
**Parameters**: `start_x`, `start_y`, `end_x`, `end_y`
```
"arrange along a diagonal line from 100,100 to 500,400"
```

### ARC - Portion of a circle (smooth curve)
**Parameters**: `center_x`, `center_y`, `radius`, `start_angle`, `end_angle`
- Angles in degrees: 0=right, 90=bottom, 180=left, 270=top
```
"arrange in a half-circle arc" → start_angle: 0, end_angle: 180
"arrange in a quarter circle" → start_angle: 0, end_angle: 90
"arrange in a semicircle at the top" → start_angle: 180, end_angle: 360
```

### BEZIER - Smooth S-curve or custom curve
**Parameters**: `start_x`, `start_y`, `end_x`, `end_y`, `control1_x`, `control1_y`, `control2_x`, `control2_y`
- Control points "pull" the curve toward them
- Two control points create S-curves
```
"arrange in an S-curve"
"create a flowing curve"
```

### SPIRAL - Expanding/contracting spiral
**Parameters**: `center_x`, `center_y`, `start_radius`, `end_radius`, `rotations`
```
"arrange in a spiral" → rotations: 2 (default)
"create an expanding vortex" → start_radius: 50, end_radius: 400, rotations: 3
```

**Examples**:
```
"arrange objects along a curved arc"
"create a spiral pattern"
"arrange in an S-shape"
"arrange along a bezier curve"
"make a half-circle arrangement"
```

**Advanced Use Cases**:
- **Heart shape**: Two bezier curves + one arc
- **Infinity symbol**: Two symmetrical bezier curves
- **Wave pattern**: Multiple small arcs
- **Custom logos**: Combine multiple path calls

**Parameters (all paths)**:
- `object_ids` (required): Array of object IDs
- `path_type` (required): "line" | "arc" | "bezier" | "spiral"
- Path-specific parameters (see above)

---

## Tool Usage Summary

### Creation Tools
- `create_shape` - Basic shapes (rectangle, circle)
- `create_text` - Text elements
- `create_component` - Complex UI components

### Modification Tools
- `move_object` - Move objects
- `resize_object` - Resize objects
- `rotate_object` - Rotate objects
- `change_style` - Style properties
- `update_text` - Text content/formatting

### Organization Tools
- `arrange_objects` ⭐ - Standard layouts (grid, circular, horizontal, vertical)
- `arrange_in_star` ⭐ NEW! - Star patterns with N points
- `arrange_along_path` ⭐ NEW! - Path-based layouts (line, arc, bezier, spiral)
- `arrange_objects_with_pattern` - Custom patterns (wave, arc, diagonal)
- `define_object_relationships` - Constraint-based positioning
- `group_objects` - Group objects together

### Selection & Utility Tools
- `select_objects_by_description` - Natural language selection
- `show_object_labels` - Show/hide object IDs
- `delete_object` - Remove objects

---

## Debugging Tips

1. **Check console logs** - Raw AI responses now logged with:
   ```
   ========== RAW CLAUDE API RESPONSE ==========
   ... full JSON response ...
   =============================================

   ========== PARSED TOOL CALLS (N) ==========
   Tool: tool_name
   Input: { ... parameters ... }
   ---
   ========================================================
   ```

2. **Common Issues**:
   - **Circular layout too tight**: AI not adjusting radius - check if "large", "huge", etc. keywords present
   - **Grid layout errors**: Check rows/columns calculation in agent.ex:600-611
   - **Missing object_ids**: Check if selected_ids being injected properly

3. **Test Commands**:
   ```
   "create 5 blue circles"
   "arrange them in a small circle"
   "arrange them in a large circle"
   "arrange them in 2 rows"
   "show object labels"

   # NEW STAR TESTS:
   "create 10 red circles"
   "arrange them in a star"
   "arrange them in a 6-pointed star"

   # NEW PATH TESTS:
   "create 8 blue circles"
   "arrange them in a spiral"
   "arrange them along an arc"
   "arrange them in an S-curve"

   # NEW SEMANTIC POSITIONING TESTS:
   "create a red circle at the top"
   "create three blue rectangles in the middle"
   "add text 'Header' at the top-center"
   "create a square on the left"
   "put a circle at the bottom-right"
   ```
