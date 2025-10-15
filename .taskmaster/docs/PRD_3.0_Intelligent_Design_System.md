# PRD 3.0: The Intelligent Design System

## Executive Summary

This PRD defines requirements to elevate the AI agent from a simple object creator to an intelligent design assistant. Additionally, it introduces a component system and style management to transform the tool from a drawing application into a comprehensive design system platform.

## Performance Requirements

- **AI Response Time:** AI commands must return visual results or feedback in under **2 seconds**
- **Component Updates:** Changes to main components must propagate to all instances within **100ms**
- **Style Application:** Applying styles to selected objects must complete within **50ms**
- **AI Layout Calculations:** Layout arrangement commands must complete within **500ms** for up to 50 objects

## Core Features

### 3.1 Reusable Component System

**User Story:** As a designer, I can create a "main component" from a set of objects, and then create multiple "instances" of it. When I edit the main component, all instances update automatically.

**Requirements:**

1. **Component Creation**
   - Select one or more objects and convert to main component
   - Keyboard shortcut: Cmd+Alt+K (Create Component)
   - Assign a unique name to the component
   - Component appears in a dedicated Components panel
   - Main component is marked with a special icon (purple diamond)

2. **Component Structure**
   - Store component definition as a template of objects
   - Include all properties: geometry, styles, relationships
   - Support nested components (components within components)
   - Version each component change
   - Tag components by category (buttons, cards, layouts, etc.)

3. **Instance Creation**
   - Drag component from Components panel to canvas
   - Keyboard shortcut: Cmd+Alt+V (Paste as Instance)
   - Each instance maintains a link to the main component
   - Instances marked with purple outline in layers panel

4. **Instance Overrides**
   - Allow specific properties to be overridden per instance:
     - Text content
     - Images
     - Colors (within defined style slots)
     - Visibility of nested elements
   - Overrides persist when main component updates
   - Visual indicator showing which properties are overridden
   - Right-click option: "Reset to Main Component"

5. **Component Propagation**
   - Editing main component updates all instances in real-time
   - Changes apply to all canvases where component is used
   - Preserve instance overrides during updates
   - Show notification: "Updating 12 instances..."
   - Undo entire component update as single operation

6. **Component Organization**
   - Components library shared across all canvases in workspace
   - Folder organization in Components panel
   - Search and filter components by name/tag
   - Publish/unpublish components for team use
   - Version history for each component

**Technical Implementation:**

- **Database Schema:**

```elixir
# New table: components
create table(:components) do
  add :name, :string, null: false
  add :description, :text
  add :category, :string
  add :canvas_id, references(:canvases, on_delete: :cascade)
  add :created_by, :string
  add :is_published, :boolean, default: false
  add :template_data, :map  # Stores the object structure

  timestamps()
end

# Modify objects table
field :component_id, references(:components, on_delete: :nilify)
field :is_main_component, :boolean, default: false
field :instance_overrides, :map, default: %{}
```

- **Backend:**
  - Context: `lib/collab_canvas/components.ex`
  - Functions: `create_component/3`, `instantiate_component/3`, `update_component/2`
  - PubSub broadcasts on component changes
  - Batch update all instances when main component changes

- **Frontend:**
  - New LiveComponent: `ComponentsPanelLive`
  - Display component library with preview thumbnails
  - Drag-and-drop to instantiate components
  - Override panel for selected instances

**API Changes:**

```elixir
# New events
handle_event("create_component", %{
  "object_ids" => ids,
  "name" => name,
  "category" => category
}, socket)

handle_event("instantiate_component", %{
  "component_id" => id,
  "position" => %{"x" => x, "y" => y}
}, socket)

handle_event("update_component", %{
  "component_id" => id,
  "changes" => changes
}, socket)

handle_event("override_instance_property", %{
  "instance_id" => id,
  "property" => property,
  "value" => value
}, socket)
```

**Acceptance Criteria:**

- Users can create components from selected objects
- Instances can be created by dragging from Components panel
- Editing main component updates all instances in real-time
- Instance overrides persist through component updates
- Component system works across multiple canvases
- All operations sync correctly in collaborative sessions

---

### 3.2 AI-Powered Layouts

**User Story:** As an AI user, I can select several objects and issue commands like "Arrange these in a horizontal row" or "Space these evenly."

**Requirements:**

1. **Selection-Based AI Commands**
   - AI recognizes when objects are selected
   - Commands reference "selected objects" or "these objects"
   - Examples:
     - "Arrange these in a horizontal row"
     - "Space these evenly vertically"
     - "Create a grid with these objects"
     - "Center these objects on the canvas"
     - "Align these to the left"

2. **Layout Algorithms**
   - **Distribute Horizontally:** Even spacing along X-axis
   - **Distribute Vertically:** Even spacing along Y-axis
   - **Grid Layout:** Arrange objects in rows and columns
   - **Circular Layout:** Arrange objects in a circle
   - **Stack:** Align objects vertically/horizontally with minimal spacing
   - **Auto Layout:** Intelligently arrange based on object sizes

3. **Alignment Commands**
   - Align left/right/center (horizontal)
   - Align top/bottom/middle (vertical)
   - Align to canvas center
   - Align to artboard bounds
   - Relative alignment: "Put the circle above the square"

4. **Spacing and Distribution**
   - Even spacing between objects
   - Specific spacing: "Space these 20 pixels apart"
   - Smart padding: "Add padding around these objects"
   - Tidy up: "Organize this mess" (AI decides best layout)

**Technical Implementation:**

- **Backend (`lib/collab_canvas/ai/`):**
  - Create new module: `Layout.ex`
  - Implement layout algorithms:

```elixir
defmodule CollabCanvas.AI.Layout do
  def distribute_horizontally(objects, spacing \\ :even)
  def distribute_vertically(objects, spacing \\ :even)
  def arrange_grid(objects, columns, spacing)
  def align_objects(objects, alignment)
  def circular_layout(objects, radius)
end
```

- **AI Tools:**
  - Add new tool: `arrange_objects`
  - Input schema:

```json
{
  "name": "arrange_objects",
  "description": "Arranges selected objects in specified layout",
  "input_schema": {
    "type": "object",
    "properties": {
      "object_ids": {
        "type": "array",
        "items": {"type": "string"},
        "description": "IDs of objects to arrange"
      },
      "layout_type": {
        "type": "string",
        "enum": ["horizontal", "vertical", "grid", "circular", "stack"],
        "description": "Type of layout to apply"
      },
      "spacing": {
        "type": "number",
        "description": "Spacing between objects in pixels"
      },
      "alignment": {
        "type": "string",
        "enum": ["left", "center", "right", "top", "middle", "bottom"]
      }
    },
    "required": ["object_ids", "layout_type"]
  }
}
```

- **Agent Enhancement:**
  - Modify `Agent.handle_command/2` to detect selected objects
  - Pass selection context to AI
  - Return batch update operations
  - Apply updates atomically

**Acceptance Criteria:**

- AI correctly interprets layout commands
- All standard layout types work correctly
- Spacing and alignment are precise
- Commands work with 2-50 selected objects
- Layout operations can be undone as single unit
- Real-time sync with collaborators

---

### 3.3 Expanded AI Command Vocabulary

**User Story:** As an AI user, I can manipulate objects with more detail, using commands like "resize the circle to 150px wide," "rotate the text 30 degrees," or "change the color of the selected square to #FF0000."

**Requirements:**

1. **Resize Commands**
   - Absolute size: "Make the rectangle 200px wide"
   - Relative size: "Make the circle 50% larger"
   - Proportional: "Scale the image to 150px width"
   - Specific dimensions: "Resize to 300x200"

2. **Rotation Commands**
   - Absolute angle: "Rotate 45 degrees"
   - Relative rotation: "Rotate clockwise 30 degrees"
   - Reset rotation: "Make it upright"
   - Rotate to match: "Rotate to match the other rectangle"

3. **Style Manipulation**
   - Color changes: "Change color to red" or "#FF0000"
   - Transparency: "Make it 50% transparent"
   - Border/stroke: "Add a 2px black border"
   - Shadow: "Add a drop shadow"
   - Gradients: "Apply a gradient from blue to green"

4. **Text Commands**
   - Font changes: "Change font to Arial"
   - Size: "Make the text 24px"
   - Weight: "Make it bold"
   - Color: "Change text color to white"
   - Alignment: "Center align the text"

5. **Position Commands**
   - Absolute position: "Move to coordinates (100, 200)"
   - Relative position: "Move 50px to the right"
   - Position relative to others: "Put it above the blue square"

6. **Layer Commands**
   - Z-order: "Bring to front" or "Send to back"
   - Visibility: "Hide this object"
   - Locking: "Lock this layer"
   - Grouping: "Group these together"

**Technical Implementation:**

- **New AI Tools:**

```elixir
# lib/collab_canvas/ai/tools.ex

@tools [
  # ... existing tools ...
  %{
    "name" => "resize_object",
    "description" => "Resize an object to specific dimensions",
    "input_schema" => %{
      "type" => "object",
      "properties" => %{
        "object_id" => %{"type" => "string"},
        "width" => %{"type" => "number"},
        "height" => %{"type" => "number"},
        "maintain_aspect_ratio" => %{"type" => "boolean", "default" => false}
      },
      "required" => ["object_id"]
    }
  },
  %{
    "name" => "rotate_object",
    "description" => "Rotate an object by specified degrees",
    "input_schema" => %{
      "type" => "object",
      "properties" => %{
        "object_id" => %{"type" => "string"},
        "rotation" => %{"type" => "number", "description" => "Rotation in degrees"},
        "relative" => %{"type" => "boolean", "default" => false}
      },
      "required" => ["object_id", "rotation"]
    }
  },
  %{
    "name" => "change_style",
    "description" => "Change visual style properties of an object",
    "input_schema" => %{
      "type" => "object",
      "properties" => %{
        "object_id" => %{"type" => "string"},
        "fill" => %{"type" => "string"},
        "stroke" => %{"type" => "string"},
        "stroke_width" => %{"type" => "number"},
        "opacity" => %{"type" => "number"}
      },
      "required" => ["object_id"]
    }
  },
  %{
    "name" => "update_text",
    "description" => "Update text content and styling",
    "input_schema" => %{
      "type" => "object",
      "properties" => %{
        "object_id" => %{"type" => "string"},
        "text" => %{"type" => "string"},
        "font_size" => %{"type" => "number"},
        "font_family" => %{"type" => "string"},
        "font_weight" => %{"type" => "string"},
        "color" => %{"type" => "string"}
      },
      "required" => ["object_id"]
    }
  },
  %{
    "name" => "move_object",
    "description" => "Move object to specific position or by delta",
    "input_schema" => %{
      "type" => "object",
      "properties" => %{
        "object_id" => %{"type" => "string"},
        "x" => %{"type" => "number"},
        "y" => %{"type" => "number"},
        "relative" => %{"type" => "boolean", "default" => false}
      },
      "required" => ["object_id"]
    }
  }
]
```

- **Tool Implementation:**
  - Each tool maps to a context function
  - Tools modify object properties
  - Changes flow through standard update pipeline
  - All changes broadcast to collaborators

**Acceptance Criteria:**

- All command types work accurately
- AI correctly parses measurements and units
- Color names and hex codes both work
- Relative and absolute commands differentiated
- Commands work on both single and multi-select
- Undo/redo works for all AI commands

---

### 3.4 Styles & Design Tokens

**User Story:** As a designer, I can save colors and text styles to a palette and re-apply them to any object, ensuring consistency across my design.

**Requirements:**

1. **Color Palette**
   - Save frequently used colors
   - Organize colors by category (primary, secondary, neutral)
   - Name each color (e.g., "Brand Blue", "Error Red")
   - Hex, RGB, HSL support
   - Color picker with saved palette integration
   - Apply saved color with one click

2. **Text Styles**
   - Save complete text formatting as a style
   - Include: font family, size, weight, color, line height, letter spacing
   - Name styles (e.g., "Heading 1", "Body Text", "Caption")
   - Preview each style in the panel
   - Apply to selected text with one click
   - Update all instances when style definition changes

3. **Effect Styles**
   - Shadow styles (drop shadow, inner shadow)
   - Blur effects
   - Gradient definitions
   - Border/stroke styles
   - Save and reuse combinations

4. **Style Management**
   - Create style from selected object
   - Edit style definition (updates all instances)
   - Delete styles (with warning if in use)
   - Import/export style libraries
   - Share styles across team

5. **Design Tokens**
   - Export styles as design tokens (JSON)
   - Integration with design systems
   - Semantic naming (e.g., `color.primary.500`)
   - Generate code for developers (CSS variables, Tailwind config)

**Technical Implementation:**

- **Database Schema:**

```elixir
# New table: styles
create table(:styles) do
  add :name, :string, null: false
  add :type, :string  # "color", "text", "effect"
  add :category, :string
  add :definition, :map
  add :canvas_id, references(:canvases, on_delete: :cascade)
  add :created_by, :string

  timestamps()
end

# New table: text_styles
create table(:text_styles) do
  add :name, :string, null: false
  add :font_family, :string
  add :font_size, :integer
  add :font_weight, :string
  add :line_height, :float
  add :letter_spacing, :float
  add :color, :string
  add :canvas_id, references(:canvases, on_delete: :cascade)

  timestamps()
end
```

- **Backend:**
  - Context: `lib/collab_canvas/styles.ex`
  - Functions: `create_style/2`, `apply_style/2`, `update_style/2`
  - PubSub for style changes

- **Frontend:**
  - New LiveComponent: `StylesPanelLive`
  - Color palette grid
  - Text styles list with previews
  - Style creation modal
  - Apply style button

**API Changes:**

```elixir
# New events
handle_event("create_style", %{
  "name" => name,
  "type" => type,
  "definition" => definition
}, socket)

handle_event("apply_style", %{
  "object_id" => id,
  "style_id" => style_id
}, socket)

handle_event("update_style", %{
  "style_id" => id,
  "definition" => definition
}, socket)

handle_event("export_design_tokens", %{"format" => format}, socket)
```

**Acceptance Criteria:**

- Users can create and save color/text/effect styles
- Styles can be applied to objects with one click
- Updating a style updates all instances
- Styles panel shows clear organization and previews
- Export to design tokens works for multiple formats
- All style operations sync across collaborators

---

## Testing Requirements

1. **Component System Tests**
   - Test component creation and instantiation
   - Test instance overrides and propagation
   - Test nested components
   - Test collaborative component editing

2. **AI Layout Tests**
   - Test all layout algorithms with various object counts
   - Test alignment accuracy (±1px tolerance)
   - Test with different object sizes and types
   - Performance test with 50 objects

3. **AI Command Tests**
   - Test each command type (resize, rotate, style, text)
   - Test command parsing accuracy
   - Test multi-object commands
   - Test undo/redo for AI operations

4. **Styles Tests**
   - Test style creation and application
   - Test style propagation on update
   - Test design token export
   - Test style sharing across canvases

## Success Metrics

- AI command success rate >95%
- Component updates propagate within 100ms
- Style application completes within 50ms
- AI layout calculations complete within 500ms
- User efficiency increases by 40% with components
- Design consistency improves by 60% with styles
- User satisfaction rating of 4.7+/5 for AI features
