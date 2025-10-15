# PRD 3.0 Implementation - File Reference Guide

This document maps PRD 3.0 features to their implementation status in the codebase.

## File Paths (All Absolute)

### Backend - Elixir/Phoenix

**AI Module:**
- `/Users/reuben/gauntlet/figma-clone/ph-beam/collab_canvas/lib/collab_canvas/ai/`
  - `agent.ex` - AI command orchestration, Claude API integration (508 lines)
  - `component_builder.ex` - Pre-built component generation (508 lines)
  - `tools.ex` - AI tool definitions and validation (393 lines)
  - `themes.ex` - Color theme system (114 lines)

**Data Access Layer:**
- `/Users/reuben/gauntlet/figma-clone/ph-beam/collab_canvas/lib/collab_canvas/`
  - `canvases.ex` - Canvas and object CRUD operations (525 lines)
  
**Data Models:**
- `/Users/reuben/gauntlet/figma-clone/ph-beam/collab_canvas/lib/collab_canvas/canvases/`
  - `canvas.ex` - Canvas schema
  - `object.ex` - Object schema (77 lines) - CRITICAL: Missing component fields

**LiveView:**
- `/Users/reuben/gauntlet/figma-clone/ph-beam/collab_canvas/lib/collab_canvas_web/live/`
  - `canvas_live.ex` - Real-time collaborative canvas (1348 lines)

**Database Migrations:**
- `/Users/reuben/gauntlet/figma-clone/ph-beam/collab_canvas/priv/repo/migrations/`
  - `20251013211812_create_users.exs` - User table
  - `20251013211824_create_canvases.exs` - Canvas table
  - `20251013211830_create_objects.exs` - Objects table
  - `20251014120000_add_locked_by_to_objects.exs` - Collaborative locking

### Frontend - JavaScript

**Canvas Rendering:**
- `/Users/reuben/gauntlet/figma-clone/ph-beam/collab_canvas/assets/js/hooks/`
  - `canvas_manager.js` - PixiJS canvas hook (1019 lines) - CRITICAL: Single selection only

**App Configuration:**
- `/Users/reuben/gauntlet/figma-clone/ph-beam/collab_canvas/assets/js/`
  - `app.js` - Application initialization

---

## Feature Implementation Mapping

### 1. REUSABLE COMPONENT SYSTEM (3.1)

#### Implemented:
```
component_builder.ex
├── create_login_form()     [WORKING] ✓
├── create_navbar()         [WORKING] ✓
├── create_card()           [WORKING] ✓
├── create_button_group()   [WORKING] ✓
├── create_sidebar()        [WORKING] ✓
└── create_shape_for_component()  [WORKING] ✓

themes.ex
└── get_theme_colors()      [WORKING] ✓
    ├── light theme
    ├── dark theme
    ├── blue theme
    └── green theme
```

#### NOT Implemented:
```
components table            [MISSING] ✗
├── component definitions
├── component templates
├── component metadata
└── component versioning

instances table             [MISSING] ✗
├── instance creation
├── override tracking
├── link to main component
└── propagation logic

Object.ex schema updates    [MISSING] ✗
├── main_component_id field
├── component_overrides field
└── is_main_component flag
```

### 2. AI-POWERED LAYOUTS (3.2)

#### Implemented:
```
canvas_live.ex
├── create_object event     [WORKING] ✓
├── update_object event     [WORKING] ✓
├── delete_object event     [WORKING] ✓
└── move_shape via drag     [WORKING] ✓

canvas_manager.js
├── Single object selection [WORKING] ✓
├── Drag/move               [WORKING] ✓
└── Position tracking       [WORKING] ✓
```

#### NOT Implemented:
```
Multi-select               [MISSING] ✗
├── selectedObjects array   (currently: selectedObject single)
├── Shift+click support
├── Ctrl+click support
└── Selection highlighting UI

Layout algorithms          [MISSING] ✗
├── distribute_horizontal()
├── distribute_vertical()
├── align_left()
├── align_right()
├── align_center()
├── align_top()
├── align_bottom()
├── arrange_grid()
└── arrange_circular()

AI layout tools            [MISSING] ✗
├── "distribute_objects" tool
├── "align_objects" tool
└── "arrange_objects" tool
```

### 3. EXPANDED AI COMMAND VOCABULARY (3.3)

#### Implemented (7 tools):
```
tools.ex - get_tool_definitions()
├── create_shape            [WORKING] ✓
│   └── rectangles, circles
├── create_text             [WORKING] ✓
├── move_shape              [WORKING] ✓
├── resize_shape            [WORKING] ✓
├── delete_object           [WORKING] ✓
├── group_objects           [WORKING] ✓ (metadata only)
└── create_component        [WORKING] ✓
    └── 5 pre-built types

agent.ex - execute_tool_call()
├── execute_tool_call/create_shape    [WORKING] ✓
├── execute_tool_call/create_text     [WORKING] ✓
├── execute_tool_call/move_shape      [WORKING] ✓
├── execute_tool_call/resize_shape    [WORKING] ✓
├── execute_tool_call/delete_object   [WORKING] ✓
├── execute_tool_call/group_objects   [WORKING] ✓
└── execute_tool_call/create_component [WORKING] ✓
```

#### NOT Implemented:
```
Transform operations       [MISSING] ✗
├── rotate_object tool
├── rotate_shape execution
└── rotation field in object.data

Style modification        [MISSING] ✗
├── change_fill tool
├── change_stroke tool
├── change_opacity tool
└── property modification handlers

Text operations          [MISSING] ✗
├── update_text_content tool
├── change_font_size tool
├── change_font_family tool
└── text property handlers

Layer operations         [MISSING] ✗
├── bring_to_front tool
├── send_to_back tool
└── z-index implementation

Position operations      [MISSING] ✗
└── position_relative tool (only absolute move)
```

#### Object Data Gaps (object.ex):
```
Current fields in object.data:
{
  width, height,           // Shapes
  fill, stroke, stroke_width,
  text, font_size, font_family, color, align  // Text
}

Missing fields:
{
  rotation,                // NOT stored
  opacity,                 // NOT stored
  effects,                 // NOT stored
  visibility,              // NOT stored
  shadow, blur, etc.      // NOT stored
}
```

### 4. STYLES & DESIGN TOKENS (3.4)

#### Implemented:
```
themes.ex
├── 4 hardcoded color themes
│   ├── light theme
│   ├── dark theme
│   ├── blue theme
│   └── green theme
└── ~15 color variables per theme
    ├── bg, border
    ├── text_primary, text_secondary
    ├── input_bg, input_border
    ├── button_bg, button_border, button_text
    ├── navbar_bg
    ├── card_bg, card_header_bg, card_footer_bg
    ├── shadow
    └── sidebar_bg, sidebar_item_bg, sidebar_item_border
```

#### NOT Implemented:
```
Database schema           [MISSING] ✗
├── design_tokens table
├── color_palettes table
├── text_styles table
├── effect_styles table
└── canvas_styles table

Token management UI      [MISSING] ✗
├── Token creation panel
├── Token editing UI
├── Token application UI
└── Token browser

Color palette system    [MISSING] ✗
├── Palette creation
├── Palette editing
├── Palette reuse
└── Palette selection in UI

Text style system       [MISSING] ✗
├── Style definition
├── Style storage
├── Style application
└── Style browsing

Effect system           [MISSING] ✗
├── Shadow presets
├── Blur presets
├── Effect storage
└── Effect application

Export functionality    [MISSING] ✗
├── CSS variable export
├── JSON export
├── Token format standards
└── Cross-project sharing
```

---

## Database Schema

### Current Tables:
1. `users` - User accounts
2. `canvases` - Canvas projects
3. `objects` - Canvas objects (shapes, text, components)

### Missing Tables:
```
components              # Main component definitions
├── id
├── canvas_id
├── name
├── description
├── definition (JSON)
├── preview (image)
└── created_at

instances              # Component instances
├── id
├── main_component_id
├── object_ids
├── overrides (JSON)
└── created_at

design_tokens          # Token definitions
├── id
├── canvas_id
├── name
├── value
├── category
├── description
└── created_at

color_palettes         # Color palette groups
├── id
├── canvas_id
├── name
├── colors (JSON array)
└── created_at

text_styles           # Text style presets
├── id
├── canvas_id
├── name
├── font_family
├── font_size
├── color
├── line_height
└── created_at

effect_styles         # Effect presets
├── id
├── canvas_id
├── name
├── effects (JSON)
└── created_at
```

### Required Schema Changes:
```
objects table modifications:
├── ADD: main_component_id (foreign key to components)
├── ADD: component_overrides (JSON)
├── ADD: rotation (float)
├── ADD: opacity (float, 0-1)
├── ADD: z_index (integer)
├── ADD: effects (JSON)
└── ADD: visible (boolean)
```

---

## Code Statistics

| File | Lines | Status | Key Function |
|------|-------|--------|---|
| agent.ex | 505 | Implemented | AI orchestration |
| component_builder.ex | 508 | Implemented | Component generation |
| tools.ex | 393 | Implemented | Tool definitions |
| canvas_live.ex | 1348 | Implemented | Real-time canvas |
| canvas_manager.js | 1019 | Implemented | PixiJS rendering |
| themes.ex | 114 | Implemented | Color themes |
| canvases.ex | 525 | Implemented | Data layer |
| object.ex | 77 | Partial | Schema (missing fields) |

---

## Testing Locations

Current tests would be in:
```
/Users/reuben/gauntlet/figma-clone/ph-beam/collab_canvas/test/
├── collab_canvas/
│   ├── ai/
│   │   ├── agent_test.exs      [Exists?]
│   │   ├── component_builder_test.exs [Exists?]
│   │   ├── tools_test.exs       [Exists?]
│   │   └── themes_test.exs      [Exists?]
│   ├── canvases_test.exs        [Exists?]
│   └── ...
└── collab_canvas_web/
    └── live/
        └── canvas_live_test.exs [Exists?]
```

---

## Next Steps

### Immediate (This Week):
1. Verify test coverage for existing features
2. Document AI tool usage patterns
3. Create component data model design

### Short Term (This Sprint):
1. Create database schema for components/instances
2. Implement multi-select in canvas_manager.js
3. Add component_id fields to object.ex

### Medium Term (Next Sprint):
1. Build instance creation workflow
2. Implement override tracking
3. Add layout algorithm module

### Long Term (Phase 2):
1. Build design token system
2. Add token management UI
3. Implement token export
