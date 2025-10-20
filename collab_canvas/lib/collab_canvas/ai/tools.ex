defmodule CollabCanvas.AI.Tools do
  @moduledoc """
  Defines function calling tool definitions for the Claude API.

  This module provides tool schemas that enable Claude AI to interact with the
  CollabCanvas system by creating, modifying, and organizing visual elements on
  the canvas. Tools are defined using the Claude API's function calling format,
  which includes JSON Schema-based input validation.

  ## Available Tools

  The module provides the following tools for canvas manipulation:

  - `create_shape` - Creates basic shapes (rectangles and circles) with customizable
    styling including fill color, stroke color, and stroke width
  - `create_text` - Adds text elements to the canvas with configurable font properties,
    color, and alignment
  - `move_shape` - Repositions existing shapes to new coordinates
  - `resize_shape` - Adjusts the dimensions of existing shapes
  - `create_component` - Generates complex UI components (buttons, cards, navbars,
    login forms, sidebars) with theme support
  - `delete_object` - Removes objects from the canvas
  - `group_objects` - Combines multiple objects into a named group for organization
  - `resize_object` - Resizes objects with optional aspect ratio preservation
  - `rotate_object` - Rotates objects by a specified angle around a pivot point
  - `change_style` - Changes styling properties (fill, stroke, opacity, fonts, etc.)
  - `update_text` - Updates text content and formatting options
  - `move_object` - Moves objects using delta or absolute coordinates

  ## Tool Schema Format

  Each tool definition follows the Claude API function calling schema:

      %{
        name: "tool_name",
        description: "What the tool does",
        input_schema: %{
          type: "object",
          properties: %{
            param_name: %{
              type: "string" | "number" | "array" | "object",
              description: "Parameter description",
              enum: [...],        # Optional: allowed values
              default: value      # Optional: default value
            }
          },
          required: ["param1", "param2"]
        }
      }

  ## Integration with Agent Module

  The `CollabCanvas.AI.Agent` module uses these tool definitions in two ways:

  1. **Tool Registration** - The definitions are passed to Claude's API via the
     `tools` parameter in chat completion requests, allowing Claude to understand
     what actions it can perform.

  2. **Tool Execution** - When Claude decides to use a tool, the Agent module:
     - Receives the tool name and parameters from Claude's response
     - Validates the parameters using `validate_tool_call/2`
     - Executes the corresponding canvas operation
     - Returns results to Claude for continued conversation

  ## Validation

  The module includes validation functions that:

  - Check for required parameters
  - Apply default values for optional parameters
  - Ensure parameter types match the schema
  - Return `{:ok, params}` or `{:error, reason}` tuples

  ## Example Usage

      # Get all tool definitions for Claude API
      tools = CollabCanvas.AI.Tools.get_tool_definitions()

      # Validate a tool call before execution
      case CollabCanvas.AI.Tools.validate_tool_call("create_shape", params) do
        {:ok, validated_params} -> execute_tool(validated_params)
        {:error, reason} -> handle_error(reason)
      end
  """

  @doc """
  Get tool definitions filtered by canvas size.

  For small canvases (<100 objects): Includes select_objects_by_description (AI filters)
  For large canvases (>=100 objects): Includes select_objects_by_filter_criteria (server filters)

  ## Parameters
    * `object_count` - Number of objects on canvas (default: 0)

  ## Returns
  List of tool definition maps containing:
  - `:name` - Tool identifier
  - `:description` - What the tool does
  - `:input_schema` - JSON Schema for validation
  """
  def get_tool_definitions(object_count \\ 0) do
    all_tools = get_all_tool_definitions()

    # Filter tools based on canvas size
    if object_count < 100 do
      # Small canvas: include direct selection, exclude filter criteria
      Enum.reject(all_tools, fn tool ->
        tool[:name] == "select_objects_by_filter_criteria"
      end)
    else
      # Large canvas: include filter criteria, exclude direct selection
      Enum.reject(all_tools, fn tool ->
        tool[:name] == "select_objects_by_description"
      end)
    end
  end

  defp get_all_tool_definitions do
    [
      %{
        name: "create_shape",
        description:
          "Create one or more shapes (rectangle or circle) on the canvas. ALWAYS provide type, x, y, and width (these are required). For creating multiple shapes, add the count parameter - shapes will be arranged horizontally with automatic spacing.\n\nSEMANTIC POSITIONING: When the user says 'at the top', 'in the middle', 'on the left', etc., use the coordinates provided in the CURRENT VIEWPORT section (if available). For example: 'create a circle at the top' means use the y-coordinate from the 'top' semantic position, NOT arbitrary values like 100.",
        input_schema: %{
          type: "object",
          properties: %{
            type: %{
              type: "string",
              enum: ["rectangle", "circle"],
              description: "REQUIRED: The type of shape to create"
            },
            x: %{
              type: "number",
              description:
                "REQUIRED: X coordinate for the first shape position. If the user uses semantic positions like 'left', 'center', 'right', use the coordinates from the CURRENT VIEWPORT section."
            },
            y: %{
              type: "number",
              description:
                "REQUIRED: Y coordinate for the first shape position. If the user uses semantic positions like 'top', 'middle', 'bottom', use the coordinates from the CURRENT VIEWPORT section."
            },
            width: %{
              type: "number",
              description:
                "REQUIRED: Width of the shape (for rectangles) or diameter (for circles)"
            },
            height: %{
              type: "number",
              description: "Height of the shape (only for rectangles, ignored for circles)"
            },
            fill: %{
              type: "string",
              description: "Fill color in hex format (e.g., #3b82f6)",
              default: "#3b82f6"
            },
            stroke: %{
              type: "string",
              description: "Stroke color in hex format",
              default: "#1e40af"
            },
            stroke_width: %{
              type: "number",
              description: "Width of the stroke",
              default: 2
            },
            count: %{
              type: "integer",
              description:
                "Number of shapes to create (default: 1). When count > 1, shapes are arranged horizontally with spacing based on their width.",
              default: 1,
              minimum: 1,
              maximum: 100
            },
            spacing: %{
              type: "number",
              description:
                "Spacing between multiple shapes in pixels (default: 1.5x the width). Only used when count > 1.",
              default: nil
            }
          },
          required: ["type", "x", "y", "width"]
        }
      },
      %{
        name: "create_text",
        description: "Add text to the canvas. Supports semantic positioning - use viewport coordinates when user says 'at the top', 'in the middle', etc.",
        input_schema: %{
          type: "object",
          properties: %{
            text: %{
              type: "string",
              description: "The text content to display"
            },
            x: %{
              type: "number",
              description: "X coordinate for text position. If the user uses semantic positions like 'left', 'center', 'right', use coordinates from CURRENT VIEWPORT section."
            },
            y: %{
              type: "number",
              description: "Y coordinate for text position. If the user uses semantic positions like 'top', 'middle', 'bottom', use coordinates from CURRENT VIEWPORT section."
            },
            font_size: %{
              type: "number",
              description: "Font size in pixels",
              default: 16
            },
            font_family: %{
              type: "string",
              description: "Font family name",
              default: "Arial"
            },
            color: %{
              type: "string",
              description: "Text color in hex format",
              default: "#000000"
            },
            align: %{
              type: "string",
              enum: ["left", "center", "right"],
              description: "Text alignment",
              default: "left"
            }
          },
          required: ["text", "x", "y"]
        }
      },
      %{
        name: "move_shape",
        description: "Move an existing shape to a new position",
        input_schema: %{
          type: "object",
          properties: %{
            shape_id: %{
              type: "integer",
              description: "ID of the shape to move"
            },
            x: %{
              type: "number",
              description: "New X coordinate"
            },
            y: %{
              type: "number",
              description: "New Y coordinate"
            }
          },
          required: ["shape_id", "x", "y"]
        }
      },
      %{
        name: "resize_shape",
        description: "Resize an existing shape",
        input_schema: %{
          type: "object",
          properties: %{
            shape_id: %{
              type: "integer",
              description: "ID of the shape to resize"
            },
            width: %{
              type: "number",
              description: "New width"
            },
            height: %{
              type: "number",
              description: "New height (ignored for circles)"
            }
          },
          required: ["shape_id", "width"]
        }
      },
      %{
        name: "create_component",
        description: "Create a complex UI component (group of shapes and text)",
        input_schema: %{
          type: "object",
          properties: %{
            type: %{
              type: "string",
              enum: ["button", "card", "navbar", "login_form", "sidebar"],
              description: "Type of component to create"
            },
            x: %{
              type: "number",
              description: "X coordinate for component position"
            },
            y: %{
              type: "number",
              description: "Y coordinate for component position"
            },
            width: %{
              type: "number",
              description: "Component width",
              default: 200
            },
            height: %{
              type: "number",
              description: "Component height",
              default: 100
            },
            theme: %{
              type: "string",
              enum: ["light", "dark", "blue", "green"],
              description: "Color theme for the component",
              default: "light"
            },
            content: %{
              type: "object",
              description: "Component-specific content configuration",
              properties: %{
                title: %{type: "string", description: "Component title or label"},
                subtitle: %{type: "string", description: "Secondary text"},
                items: %{
                  type: "array",
                  description: "List of items (for navbars, lists, etc.)",
                  items: %{type: "string"}
                }
              }
            }
          },
          required: ["type", "x", "y"]
        }
      },
      %{
        name: "delete_object",
        description: "Delete an object from the canvas",
        input_schema: %{
          type: "object",
          properties: %{
            object_id: %{
              type: "integer",
              description: "ID of the object to delete"
            }
          },
          required: ["object_id"]
        }
      },
      %{
        name: "group_objects",
        description: "Group multiple objects together",
        input_schema: %{
          type: "object",
          properties: %{
            object_ids: %{
              type: "array",
              description: "List of object IDs to group",
              items: %{type: "integer"}
            },
            group_name: %{
              type: "string",
              description: "Name for the group"
            }
          },
          required: ["object_ids"]
        }
      },
      %{
        name: "resize_object",
        description: "Resize an object with optional aspect ratio preservation",
        input_schema: %{
          type: "object",
          properties: %{
            object_id: %{
              type: "integer",
              description: "ID of the object to resize"
            },
            width: %{
              type: "number",
              description: "New width for the object"
            },
            height: %{
              type: "number",
              description: "New height for the object"
            },
            maintain_aspect_ratio: %{
              type: "boolean",
              description: "Whether to maintain the object's aspect ratio when resizing",
              default: false
            }
          },
          required: ["object_id", "width"]
        }
      },
      %{
        name: "rotate_object",
        description: "Rotate an object by a specified angle (RELATIVE rotation, adds to current rotation).

IMPORTANT: This is RELATIVE rotation, not absolute.
- User: 'rotate 90 degrees' → angle: 90 (adds 90° to current rotation)
- User: 'rotate -45 degrees' → angle: -45 (rotates counter-clockwise)
- If object is at 45° and user says 'rotate 90 degrees', final rotation will be 135°",
        input_schema: %{
          type: "object",
          properties: %{
            object_id: %{
              type: "integer",
              description: "ID of the object to rotate"
            },
            angle: %{
              type: "number",
              description: "Rotation delta in degrees to add to current rotation (positive = clockwise, negative = counter-clockwise)"
            },
            pivot_point: %{
              type: "string",
              enum: ["center", "top-left", "top-right", "bottom-left", "bottom-right"],
              description: "Point around which to rotate the object",
              default: "center"
            }
          },
          required: ["object_id", "angle"]
        }
      },
      %{
        name: "change_style",
        description: "Change styling properties of an object",
        input_schema: %{
          type: "object",
          properties: %{
            object_id: %{
              type: "integer",
              description: "ID of the object to style"
            },
            property: %{
              type: "string",
              enum: [
                "fill",
                "stroke",
                "stroke_width",
                "opacity",
                "font_size",
                "font_family",
                "color"
              ],
              description: "The style property to change"
            },
            value: %{
              type: "string",
              description:
                "The new value for the property (e.g., '#ff0000' for colors, '2' for widths)"
            }
          },
          required: ["object_id", "property", "value"]
        }
      },
      %{
        name: "update_text",
        description: "Update text content and formatting of a text object",
        input_schema: %{
          type: "object",
          properties: %{
            object_id: %{
              type: "integer",
              description: "ID of the text object to update"
            },
            new_text: %{
              type: "string",
              description: "New text content"
            },
            font_size: %{
              type: "number",
              description: "Font size in pixels"
            },
            font_family: %{
              type: "string",
              description: "Font family name"
            },
            color: %{
              type: "string",
              description: "Text color in hex format"
            },
            align: %{
              type: "string",
              enum: ["left", "center", "right"],
              description: "Text alignment"
            },
            bold: %{
              type: "boolean",
              description: "Whether text should be bold"
            },
            italic: %{
              type: "boolean",
              description: "Whether text should be italic"
            }
          },
          required: ["object_id"]
        }
      },
      %{
        name: "move_object",
        description: "Move a SINGLE object to a new position using delta or absolute coordinates. For moving MULTIPLE objects, use move_objects_batch instead.",
        input_schema: %{
          type: "object",
          properties: %{
            object_id: %{
              type: "integer",
              description: "ID of the object to move"
            },
            delta_x: %{
              type: "number",
              description: "Relative X movement (positive = right, negative = left)"
            },
            delta_y: %{
              type: "number",
              description: "Relative Y movement (positive = down, negative = up)"
            },
            x: %{
              type: "number",
              description: "Absolute X coordinate (used if delta_x not provided)"
            },
            y: %{
              type: "number",
              description: "Absolute Y coordinate (used if delta_y not provided)"
            }
          },
          required: ["object_id"]
        }
      },
      %{
        name: "move_objects_batch",
        description: "Move MULTIPLE objects by the same delta. Use this when moving 2 or more objects (e.g., 'move all green circles down 100px').

IMPORTANT: Use this tool instead of calling move_object multiple times.

EXAMPLES:
- User: 'move all green circles down 150 pixels' → First select objects, then move_objects_batch(object_ids: [1,2,3,4,5], delta_y: 150)
- User: 'move the selected shapes to the right 200px' → move_objects_batch(object_ids: selected_ids, delta_x: 200)
- User: 'shift all blue rectangles up and left' → move_objects_batch(object_ids: [10,11,12], delta_x: -100, delta_y: -100)",
        input_schema: %{
          type: "object",
          properties: %{
            object_ids: %{
              type: "array",
              items: %{type: "integer"},
              description: "Array of object IDs to move (minimum 2 objects)"
            },
            delta_x: %{
              type: "number",
              description: "Relative X movement for all objects (positive = right, negative = left)"
            },
            delta_y: %{
              type: "number",
              description: "Relative Y movement for all objects (positive = down, negative = up)"
            }
          },
          required: ["object_ids"]
        }
      },
      %{
        name: "change_layer_order",
        description: "Change the stacking order (z-index) of objects. Use this for commands like 'put X behind Y', 'bring to front', 'send to back', etc.

EXAMPLES:
- User: 'put the red circle behind the blue rectangle' → change_layer_order(object_id: red_circle_id, operation: 'send_to_back')
- User: 'bring the text to the front' → change_layer_order(object_id: text_id, operation: 'bring_to_front')
- User: 'move the square back one layer' → change_layer_order(object_id: square_id, operation: 'move_backward')
- User: 'move the circle forward' → change_layer_order(object_id: circle_id, operation: 'move_forward')

IMPORTANT: For relative commands like 'put X behind Y', you typically want to:
1. Select the object to move (X)
2. Use 'send_to_back' or 'move_backward' to put it behind
3. The operation applies to the entire canvas z-index stack",
        input_schema: %{
          type: "object",
          properties: %{
            object_id: %{
              type: "integer",
              description: "ID of the object whose layer order should change"
            },
            operation: %{
              type: "string",
              enum: ["bring_to_front", "send_to_back", "move_forward", "move_backward"],
              description: "Layer operation: bring_to_front (top of stack), send_to_back (bottom), move_forward (+1 layer), move_backward (-1 layer)"
            }
          },
          required: ["object_id", "operation"]
        }
      },
      %{
        name: "arrange_objects",
        description:
          "Arranges selected objects in standard layout patterns. Use this for CIRCULAR, horizontal, vertical, grid, and stack layouts. For circular layouts, objects are distributed evenly around a circle at a specified radius. For custom patterns like diagonal lines, waves, or arcs, use arrange_objects_with_pattern instead.\n\nAUTO-SPACING: The system automatically prevents overlaps by calculating safe spacing/radius based on object sizes. Your suggested radius is a HINT - the system will use it or increase it as needed to prevent overlaps.\n\nIMPORTANT LIMITATIONS:\n- CANNOT group or sort by color - only by position/size/id\n- If user requests 'grouped by color', IGNORE that requirement and just arrange in the pattern\n- For circular layouts, ALWAYS use this tool with layout_type='circular', NEVER use arrange_objects_with_pattern\n\nEXAMPLES:\nUser: 'arrange all objects in 3 rows' → arrange_objects(object_ids: [1,2,3,4,5,6,7,8,9], layout_type: 'grid', rows: 3)\nUser: 'arrange horizontally with 50px spacing' → arrange_objects(object_ids: [1,2,3], layout_type: 'horizontal', spacing: 50)\nUser: 'arrange in a 4 column grid' → arrange_objects(object_ids: [1,2,3,4,5,6,7,8], layout_type: 'grid', columns: 4)\n\nCIRCULAR LAYOUT GUIDANCE:\nUser: 'arrange in a circle' → arrange_objects(object_ids: [1,2,3,4,5], layout_type: 'circular', radius: 200)\nUser: 'arrange in a circle grouped by color' → arrange_objects(object_ids: [1,2,3,4,5], layout_type: 'circular', radius: 200) [ignore 'grouped by color']\nUser: 'arrange in a small/tight circle' → use radius: 100-150\nUser: 'arrange in a large circle' → use radius: 300-500\nUser: 'arrange in a huge circle' → use radius: 600-800\nDEFAULT radius is 200px (medium circle). ALWAYS adjust radius based on: 'small', 'large', 'huge', 'tight', 'wide' keywords in command.",
        input_schema: %{
          type: "object",
          properties: %{
            object_ids: %{
              type: "array",
              items: %{type: "integer"},
              description: "IDs of objects to arrange"
            },
            layout_type: %{
              type: "string",
              enum: ["horizontal", "vertical", "grid", "circular", "stack"],
              description: "Type of layout to apply"
            },
            spacing: %{
              type: "number",
              description: "Spacing between objects in pixels (default: 20)",
              default: 20
            },
            alignment: %{
              type: "string",
              enum: ["left", "center", "right", "top", "middle", "bottom"],
              description: "Alignment for objects (used with stack layout or separately)"
            },
            columns: %{
              type: "number",
              description: "Number of columns for grid layout (optional, mutually exclusive with 'rows')"
            },
            rows: %{
              type: "number",
              description: "Number of rows for grid layout (optional, mutually exclusive with 'columns'). If specified, columns will be calculated automatically."
            },
            radius: %{
              type: "number",
              description: "Radius in pixels for circular layout. CRITICAL: Adjust based on user's size preference: small/tight=100-150, medium/default=200, large=300-500, huge=600-800. NEVER use same default for all circles - interpret 'large circle', 'small circle', etc.",
              default: 200
            }
          },
          required: ["object_ids", "layout_type"]
        }
      },
      %{
        name: "show_object_labels",
        description:
          "Toggle visual labels on canvas objects. Use this when user asks to 'show object IDs', 'show labels', 'display object names', or 'hide labels'. Labels appear directly on the canvas above each object showing their human-readable names (Rectangle 1, Circle 2, etc.)",
        input_schema: %{
          type: "object",
          properties: %{
            show: %{
              type: "boolean",
              description: "True to show labels, false to hide them"
            }
          },
          required: ["show"]
        }
      },
      %{
        name: "arrange_objects_with_pattern",
        description:
          "Arrange objects using flexible programmatic patterns like diagonal lines, waves, and arcs with SORTING and GROUPING support.\n\nCRITICAL EXCLUSIONS:\n- For CIRCULAR layouts use arrange_objects with layout_type='circular' - NEVER use this tool\n- For STAR patterns use arrange_in_star tool\n\nSORTING vs GROUPING:\n- SORT: User says 'sort by color' → set sort_by='color' (smooth continuum, no extra spacing)\n- GROUP: User says 'group by color' or 'grouped by shape' → set group_by='color' (extra spacing between groups)\n\nEXAMPLES:\n- 'arrange in a line, grouped by color' → pattern='line', group_by='color', group_spacing=100\n- 'diagonal pattern, sorted by size' → pattern='diagonal', sort_by='size'\n- 'wave pattern, grouped by shape' → pattern='wave', group_by='shape'\n\nIMPORTANT: This tool ARRANGES objects in patterns. Always use when user wants spatial arrangement/organization.",
        input_schema: %{
          type: "object",
          properties: %{
            object_ids: %{
              type: "array",
              items: %{type: "integer"},
              description: "IDs of objects to arrange"
            },
            pattern: %{
              type: "string",
              enum: ["line", "diagonal", "wave", "arc", "custom"],
              description:
                "Pattern type: ONLY 'line', 'diagonal', 'wave', 'arc', or 'custom'. CRITICAL: 'star' is NOT valid - use arrange_in_star tool instead!"
            },
            direction: %{
              type: "string",
              enum: ["horizontal", "vertical", "diagonal-right", "diagonal-left", "up", "down"],
              description: "Direction of the pattern (used with line and diagonal patterns)"
            },
            spacing: %{
              type: "number",
              description: "Spacing between objects in pixels",
              default: 50
            },
            alignment: %{
              type: "string",
              enum: ["start", "center", "end", "baseline"],
              description: "How objects align within the pattern"
            },
            start_x: %{
              type: "number",
              description: "Starting X coordinate for the pattern"
            },
            start_y: %{
              type: "number",
              description: "Starting Y coordinate for the pattern"
            },
            amplitude: %{
              type: "number",
              description: "Amplitude for wave/arc patterns (height of waves)",
              default: 100
            },
            frequency: %{
              type: "number",
              description: "Frequency for wave patterns (number of waves)",
              default: 2
            },
            sort_by: %{
              type: "string",
              enum: ["none", "x", "y", "size", "id", "color", "type", "shape"],
              description: "SORTING (continuum): Arranges objects on a smooth continuum by attribute. Objects gradually transition from smallest to largest, or one color to another. No extra spacing between different values. Use for gradual progressions.",
              default: "none"
            },
            group_by: %{
              type: "string",
              enum: ["none", "color", "type", "shape", "size"],
              description: "GROUPING (with spacing): Groups objects by attribute with EXTRA SPACING between groups. All red objects together, then GAP, then all blue objects together. Use when user says 'group by color', 'grouped by shape', etc. Creates visual separation between different groups.",
              default: "none"
            },
            group_spacing: %{
              type: "number",
              description: "Extra spacing (in pixels) to add between different groups when group_by is used. Default: 100px. Ignored if group_by is 'none'.",
              default: 100
            }
          },
          required: ["object_ids", "pattern"]
        }
      },
      %{
        name: "define_object_relationships",
        description:
          "Define spatial relationships using declarative constraints - HIGHLY FLEXIBLE for building complex formations. Use this to create triangles, pyramids, ladders, or any structured arrangement by defining relationships: 'A below B', 'C aligned with D', 'E centered between F and G'. Build complex shapes by chaining relationships (e.g., triangle: place objects below and left_of/right_of each other). The system solves constraints to calculate positions. Perfect for hierarchical, symmetric, or geometric patterns.",
        input_schema: %{
          type: "object",
          properties: %{
            relationships: %{
              type: "array",
              description: "List of relationship constraints to apply",
              items: %{
                type: "object",
                properties: %{
                  subject_id: %{
                    type: "integer",
                    description: "ID of the object being positioned"
                  },
                  relation: %{
                    type: "string",
                    enum: [
                      "above",
                      "below",
                      "left_of",
                      "right_of",
                      "aligned_horizontally_with",
                      "aligned_vertically_with",
                      "centered_between",
                      "same_spacing_as"
                    ],
                    description: "The spatial relationship to enforce"
                  },
                  reference_id: %{
                    type: "integer",
                    description:
                      "ID of the reference object (or first reference for centered_between)"
                  },
                  reference_id_2: %{
                    type: "integer",
                    description:
                      "Second reference object ID (used only for centered_between and same_spacing_as)"
                  },
                  spacing: %{
                    type: "number",
                    description: "Distance to maintain between objects (in pixels)",
                    default: 20
                  }
                },
                required: ["subject_id", "relation", "reference_id"]
              }
            },
            apply_constraints: %{
              type: "boolean",
              description:
                "Whether to apply constraint solving (true) or simple sequential application (false)",
              default: true
            }
          },
          required: ["relationships"]
        }
      },
      %{
        name: "select_objects_by_description",
        description:
          "Select objects by filtering the full object list provided in the context.

STEP-BY-STEP INSTRUCTIONS:
1. Look at the FULL OBJECT LIST FOR FILTERING section in the context (JSON array of all objects)
2. Filter objects based on the user's description
3. For SQUARES: Find objects where type=rectangle AND width equals height (within 10px)
4. For RECTANGLES: Find objects where type=rectangle AND |width - height| > 10px
5. For CIRCLES: Find objects where type=circle
6. Match colors exactly (e.g., #00FF00 for green, #FF0000 for red, #0000FF for blue, #FFA500 for orange)
7. Return the IDs of ALL matching objects in the object_ids array

CONCRETE EXAMPLE:
User says: 'select green squares'
Context shows: [{id: 2229, type: rectangle, data: {color: #00FF00, width: 80, height: 80}}, {id: 2230, type: rectangle, data: {color: #00FF00, width: 80, height: 80}}, {id: 2231, type: rectangle, data: {color: #00FF00, width: 80, height: 80}}]
You return: {object_ids: [2229, 2230, 2231], description: 'green squares'}

User says: 'select all circles'
You find all objects where type=circle
You return: {object_ids: [2226, 2227, 2228, 2232, 2233, 2234], description: 'all circles'}",
        input_schema: %{
          type: "object",
          properties: %{
            description: %{
              type: "string",
              description: "User's selection request (e.g., 'select all small red circles', 'select squares')"
            },
            object_ids: %{
              type: "array",
              items: %{type: "integer"},
              description: "REQUIRED: Array of matching object IDs after filtering the full object list."
            }
          },
          required: ["description", "object_ids"]
        }
      },
      %{
        name: "select_objects_by_filter_criteria",
        description:
          "Select objects by returning filter criteria. The server will apply these filters to the large canvas efficiently.

You receive canvas STATISTICS only (no full object list). Analyze the stats and return filter criteria.

**COLOR MATCHING:**
Return exact hex color from the available colors list
- 'red objects' → color: '#FF0000'
- 'blue circles' → color: '#0000FF'

**SIZE FILTERING:**
Use size_stats percentiles to determine thresholds:
- 'small objects' → size_max: p30 (bottom 30%)
- 'large objects' → size_min: p70 (top 30%)
- 'tiny objects' → size_max: p10 (bottom 10%)
- 'huge objects' → size_min: p90 (top 10%)
- 'medium objects' → size_min: p40, size_max: p60 (middle 20%)

**SHAPE TYPE:**
- 'all circles' → shape_type: 'circle'
- 'all rectangles' → shape_type: 'rectangle'
- 'all squares' → shape_type: 'square'

**POSITION:**
- 'objects on the left' → position: 'left'
- Valid: top, bottom, left, right, center, top-left, top-right, bottom-left, bottom-right

EXAMPLES:
Given size_stats: {p10: 50, p30: 100, p70: 350, p90: 500}
Given colors: ['#FF0000', '#0000FF', '#00FF00']
- 'select small red circles' → {color: '#FF0000', size_max: 100, shape_type: 'circle'}
- 'select huge objects' → {size_min: 500}
- 'select large blue objects on the left' → {color: '#0000FF', size_min: 350, position: 'left'}",
        input_schema: %{
          type: "object",
          properties: %{
            description: %{
              type: "string",
              description: "User's selection request"
            },
            color: %{
              type: "string",
              description: "Hex color code to filter by (from available colors). Optional."
            },
            size_min: %{
              type: "number",
              description: "Minimum size threshold in pixels (use percentiles from size_stats). Optional."
            },
            size_max: %{
              type: "number",
              description: "Maximum size threshold in pixels (use percentiles from size_stats). Optional."
            },
            shape_type: %{
              type: "string",
              description: "Shape type to filter. Optional.",
              enum: ["circle", "rectangle", "square", "text"]
            },
            position: %{
              type: "string",
              description: "Position relative to viewport. Optional.",
              enum: ["top", "bottom", "left", "right", "center", "top-left", "top-right", "bottom-left", "bottom-right"]
            }
          },
          required: ["description"]
        }
      },
      %{
        name: "arrange_in_star",
        description:
          "Arranges objects in a STAR pattern with alternating outer and inner points. CRITICAL: Use this tool for ANY star-related arrangement request ('arrange in a star', 'make a star shape', 'star pattern', etc.). The star has customizable number of points, outer radius, and inner radius. Objects are placed at alternating outer/inner points around a center.\n\nAUTO-SPACING: The system automatically prevents overlaps by calculating safe radii based on object sizes. Your suggested radii are HINTS - the system will use them or increase them as needed to prevent overlaps and maintain proper star proportions.\n\nEXAMPLES:\nUser: 'arrange in a star' → arrange_in_star(object_ids: [1,2,3,4,5,6,7,8,9,10], points: 5, outer_radius: 300)\nUser: 'make a 6-pointed star' → arrange_in_star(object_ids: [...], points: 6, outer_radius: 300)\nUser: 'arrange in a small star' → arrange_in_star(object_ids: [...], points: 5, outer_radius: 150)\nUser: 'create a large star pattern' → arrange_in_star(object_ids: [...], points: 5, outer_radius: 500)\n\nSTAR SIZING GUIDANCE:\n- small star: outer_radius: 150-200\n- medium star (default): outer_radius: 300\n- large star: outer_radius: 400-600\n- huge star: outer_radius: 700+\n\nThe inner_radius is automatically calculated as 40% of outer_radius unless specified.",
        input_schema: %{
          type: "object",
          properties: %{
            object_ids: %{
              type: "array",
              items: %{type: "integer"},
              description: "IDs of objects to arrange in star pattern"
            },
            points: %{
              type: "integer",
              description: "Number of star points (e.g., 5 for classic 5-pointed star, 6 for Star of David). Minimum 3.",
              default: 5
            },
            outer_radius: %{
              type: "number",
              description: "Radius to outer star points in pixels. CRITICAL: Adjust based on user's size preference: small=150-200, medium/default=300, large=400-600, huge=700+",
              default: 300
            },
            inner_radius: %{
              type: "number",
              description: "Radius to inner star points in pixels. If not specified, defaults to 40% of outer_radius for a balanced star shape."
            }
          },
          required: ["object_ids"]
        }
      },
      %{
        name: "arrange_along_path",
        description:
          "Arranges objects along a defined geometric path: straight LINE, curved ARC, smooth BEZIER curve, or expanding SPIRAL. This is the MOST FLEXIBLE arrangement tool - use it to create sophisticated patterns by specifying mathematical paths.\n\nPATH TYPES:\n\n1. LINE - Straight line between two points\n   Example: 'arrange along a diagonal line' → path_type: 'line', start_x: 100, start_y: 100, end_x: 500, end_y: 400\n\n2. ARC - Portion of a circle (smooth curve)\n   Example: 'arrange in a half-circle arc' → path_type: 'arc', center_x: 400, center_y: 300, radius: 200, start_angle: 0, end_angle: 180\n   Example: 'arrange in a quarter circle' → path_type: 'arc', start_angle: 0, end_angle: 90\n\n3. BEZIER - Smooth S-curve or custom curve with control points\n   Example: 'arrange in an S-curve' → path_type: 'bezier', start_x: 100, start_y: 300, end_x: 600, end_y: 300, control1_x: 250, control1_y: 100, control2_x: 450, control2_y: 500\n\n4. SPIRAL - Expanding/contracting spiral\n   Example: 'arrange in a spiral' → path_type: 'spiral', center_x: 400, center_y: 300, start_radius: 50, end_radius: 300, rotations: 2\n\nUSE CASES:\n- Curved lines, arcs, half-circles → use 'arc' path\n- S-curves, flowing curves → use 'bezier' path\n- Spirals, vortex patterns → use 'spiral' path\n- Any straight line → use 'line' path\n\nIMPORTANT: This tool can CREATE COMPLEX SHAPES by combining multiple path calls. For example, a heart shape = two bezier curves + one arc.",
        input_schema: %{
          type: "object",
          properties: %{
            object_ids: %{
              type: "array",
              items: %{type: "integer"},
              description: "IDs of objects to arrange along the path"
            },
            path_type: %{
              type: "string",
              enum: ["line", "arc", "bezier", "spiral"],
              description: "Type of path: 'line' (straight), 'arc' (circular curve), 'bezier' (smooth curve), 'spiral' (expanding circle)"
            },
            start_x: %{
              type: "number",
              description: "Starting X coordinate (for line and bezier paths)"
            },
            start_y: %{
              type: "number",
              description: "Starting Y coordinate (for line and bezier paths)"
            },
            end_x: %{
              type: "number",
              description: "Ending X coordinate (for line and bezier paths)"
            },
            end_y: %{
              type: "number",
              description: "Ending Y coordinate (for line and bezier paths)"
            },
            center_x: %{
              type: "number",
              description: "Center X coordinate (for arc and spiral paths)"
            },
            center_y: %{
              type: "number",
              description: "Center Y coordinate (for arc and spiral paths)"
            },
            radius: %{
              type: "number",
              description: "Arc radius in pixels (for arc path only)",
              default: 200
            },
            start_angle: %{
              type: "number",
              description: "Starting angle in degrees for arc (0 = right, 90 = bottom, 180 = left, 270 = top)",
              default: 0
            },
            end_angle: %{
              type: "number",
              description: "Ending angle in degrees for arc",
              default: 180
            },
            control1_x: %{
              type: "number",
              description: "First control point X (for bezier curves - pulls curve toward this point)"
            },
            control1_y: %{
              type: "number",
              description: "First control point Y (for bezier curves)"
            },
            control2_x: %{
              type: "number",
              description: "Second control point X (for bezier curves - creates S-shapes)"
            },
            control2_y: %{
              type: "number",
              description: "Second control point Y (for bezier curves)"
            },
            start_radius: %{
              type: "number",
              description: "Starting radius for spiral (inner circle)",
              default: 50
            },
            end_radius: %{
              type: "number",
              description: "Ending radius for spiral (outer circle)",
              default: 300
            },
            rotations: %{
              type: "number",
              description: "Number of complete rotations for spiral",
              default: 2
            }
          },
          required: ["object_ids", "path_type"]
        }
      }
    ]
  end

  @doc """
  Validates a tool call against its schema.
  Returns {:ok, params} if valid, {:error, reason} if invalid.
  """
  def validate_tool_call(tool_name, params) do
    tool = Enum.find(get_tool_definitions(), &(&1.name == tool_name))

    case tool do
      nil ->
        {:error, "Unknown tool: #{tool_name}"}

      tool_def ->
        validate_params(params, tool_def.input_schema)
    end
  end

  defp validate_params(params, schema) do
    required = Map.get(schema, :required, [])
    properties = Map.get(schema, :properties, %{})

    # Check required fields
    missing =
      Enum.filter(required, fn field ->
        field = to_string(field)
        !Map.has_key?(params, field) && !Map.has_key?(params, String.to_atom(field))
      end)

    if length(missing) > 0 do
      {:error, "Missing required fields: #{Enum.join(missing, ", ")}"}
    else
      # Add defaults for optional fields
      params_with_defaults =
        Enum.reduce(properties, params, fn {key, prop}, acc ->
          key_str = to_string(key)
          key_atom = String.to_atom(key_str)

          if !Map.has_key?(acc, key_str) && !Map.has_key?(acc, key_atom) &&
               Map.has_key?(prop, :default) do
            Map.put(acc, key_atom, prop.default)
          else
            acc
          end
        end)

      {:ok, params_with_defaults}
    end
  end
end
