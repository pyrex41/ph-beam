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
  Returns the complete list of tool definitions for Claude API function calling.

  This function provides all available tools that Claude can use to interact with
  the canvas. Each tool definition includes a name, description, and JSON Schema
  for input validation.

  ## Return Value

  Returns a list of tool definition maps, where each map contains:

  - `:name` - String identifier for the tool (e.g., "create_shape")
  - `:description` - Human-readable explanation of what the tool does
  - `:input_schema` - JSON Schema object defining required and optional parameters

  ## Usage

  The returned tool definitions are typically passed to the Claude API during
  initialization of a chat session:

      tools = CollabCanvas.AI.Tools.get_tool_definitions()
      # Pass tools to Claude API in the `tools` parameter

  The Agent module automatically includes these tools in its API requests,
  enabling Claude to call them based on user prompts and conversation context.

  ## Tool Categories

  The tools are organized into several categories:

  - **Creation Tools**: `create_shape`, `create_text`, `create_component`
  - **Manipulation Tools**: `move_shape`, `resize_shape`
  - **Organization Tools**: `group_objects`, `delete_object`

  ## Examples

      iex> tools = CollabCanvas.AI.Tools.get_tool_definitions()
      iex> length(tools)
      12

      iex> tools = CollabCanvas.AI.Tools.get_tool_definitions()
      iex> Enum.map(tools, & &1.name)
      ["create_shape", "create_text", "move_shape", "resize_shape",
       "create_component", "delete_object", "group_objects", "resize_object",
       "rotate_object", "change_style", "update_text", "move_object"]
  """
  def get_tool_definitions do
    [
      %{
        name: "create_shape",
        description: "Create a shape (rectangle or circle) on the canvas",
        input_schema: %{
          type: "object",
          properties: %{
            type: %{
              type: "string",
              enum: ["rectangle", "circle"],
              description: "The type of shape to create"
            },
            x: %{
              type: "number",
              description: "X coordinate for the shape position"
            },
            y: %{
              type: "number",
              description: "Y coordinate for the shape position"
            },
            width: %{
              type: "number",
              description: "Width of the shape (for rectangles) or diameter (for circles)"
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
            }
          },
          required: ["type", "x", "y", "width"]
        }
      },
      %{
        name: "create_text",
        description: "Add text to the canvas",
        input_schema: %{
          type: "object",
          properties: %{
            text: %{
              type: "string",
              description: "The text content to display"
            },
            x: %{
              type: "number",
              description: "X coordinate for text position"
            },
            y: %{
              type: "number",
              description: "Y coordinate for text position"
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
        description: "Rotate an object by a specified angle",
        input_schema: %{
          type: "object",
          properties: %{
            object_id: %{
              type: "integer",
              description: "ID of the object to rotate"
            },
            angle: %{
              type: "number",
              description: "Rotation angle in degrees (0-360, positive = clockwise)"
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
              enum: ["fill", "stroke", "stroke_width", "opacity", "font_size", "font_family", "color"],
              description: "The style property to change"
            },
            value: %{
              type: "string",
              description: "The new value for the property (e.g., '#ff0000' for colors, '2' for widths)"
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
        description: "Move an object to a new position using delta or absolute coordinates",
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
        name: "arrange_objects",
        description: "Arranges selected objects in standard layout patterns. Use this for CIRCULAR, horizontal, vertical, grid, and stack layouts. For circular layouts, objects are distributed evenly around a circle at a specified radius. For custom patterns like diagonal lines, waves, or arcs, use arrange_objects_with_pattern instead.",
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
              description: "Number of columns for grid layout",
              default: 3
            },
            radius: %{
              type: "number",
              description: "Radius in pixels for circular layout",
              default: 200
            }
          },
          required: ["object_ids", "layout_type"]
        }
      },
      %{
        name: "show_object_labels",
        description: "Toggle visual labels on canvas objects. Use this when user asks to 'show object IDs', 'show labels', 'display object names', or 'hide labels'. Labels appear directly on the canvas above each object showing their human-readable names (Rectangle 1, Circle 2, etc.)",
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
        description: "Arrange objects using flexible programmatic patterns like diagonal lines, waves, and arcs. NOTE: For CIRCULAR layouts (objects distributed around a circle), use arrange_objects with layout_type='circular' instead. This tool is for: 'triangular', 'pyramid', 'zigzag', 'wave', 'arc', 'diagonal line', etc. Supports line, diagonal, wave, and arc patterns with customizable parameters. For complex shapes like triangles or pyramids, use 'line' or 'diagonal' patterns with appropriate start positions and spacing, or make multiple calls to build up the shape row by row.",
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
              description: "Pattern type: 'line' for straight line (vertical/horizontal), 'diagonal' for angled line, 'wave' for wavy pattern, 'arc' for curved arc, 'custom' for fully custom positioning"
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
              enum: ["none", "x", "y", "size", "id"],
              description: "How to sort objects before arranging",
              default: "none"
            }
          },
          required: ["object_ids", "pattern"]
        }
      },
      %{
        name: "define_object_relationships",
        description: "Define spatial relationships using declarative constraints - HIGHLY FLEXIBLE for building complex formations. Use this to create triangles, pyramids, ladders, or any structured arrangement by defining relationships: 'A below B', 'C aligned with D', 'E centered between F and G'. Build complex shapes by chaining relationships (e.g., triangle: place objects below and left_of/right_of each other). The system solves constraints to calculate positions. Perfect for hierarchical, symmetric, or geometric patterns.",
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
                    enum: ["above", "below", "left_of", "right_of", "aligned_horizontally_with", "aligned_vertically_with", "centered_between", "same_spacing_as"],
                    description: "The spatial relationship to enforce"
                  },
                  reference_id: %{
                    type: "integer",
                    description: "ID of the reference object (or first reference for centered_between)"
                  },
                  reference_id_2: %{
                    type: "integer",
                    description: "Second reference object ID (used only for centered_between and same_spacing_as)"
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
              description: "Whether to apply constraint solving (true) or simple sequential application (false)",
              default: true
            }
          },
          required: ["relationships"]
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
    missing = Enum.filter(required, fn field ->
      field = to_string(field)
      !Map.has_key?(params, field) && !Map.has_key?(params, String.to_atom(field))
    end)

    if length(missing) > 0 do
      {:error, "Missing required fields: #{Enum.join(missing, ", ")}"}
    else
      # Add defaults for optional fields
      params_with_defaults = Enum.reduce(properties, params, fn {key, prop}, acc ->
        key_str = to_string(key)
        key_atom = String.to_atom(key_str)

        if !Map.has_key?(acc, key_str) && !Map.has_key?(acc, key_atom) && Map.has_key?(prop, :default) do
          Map.put(acc, key_atom, prop.default)
        else
          acc
        end
      end)

      {:ok, params_with_defaults}
    end
  end
end