defmodule CollabCanvas.AI.Tools do
  @moduledoc """
  Defines tool schemas for Claude function calling.

  This module provides tool definitions that Claude can use to interact with the canvas,
  including creating shapes, text, and complex UI components.
  """

  @doc """
  Returns the tool definitions for Claude API function calling.
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
              type: "string",
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
              type: "string",
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
              type: "string",
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
              items: %{type: "string"}
            },
            group_name: %{
              type: "string",
              description: "Name for the group"
            }
          },
          required: ["object_ids"]
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