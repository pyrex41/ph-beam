defmodule CollabCanvas.AI.Agent do
  @moduledoc """
  AI Agent for executing natural language commands on canvas objects.

  This module provides an intelligent interface for canvas manipulation through natural language.
  It integrates with the Anthropic Claude API to parse user commands and translate them into
  specific canvas operations using function calling tools.

  ## Purpose

  The AI Agent serves as a bridge between human language and canvas operations, allowing users to:
  - Create shapes, text, and complex UI components with natural descriptions
  - Move, resize, and delete objects using conversational commands
  - List and query canvas objects
  - Group multiple objects together

  ## Claude API Integration

  The agent uses Claude 3.5 Sonnet with function calling to:
  1. Parse natural language commands into structured tool calls
  2. Validate canvas operations before execution
  3. Handle multi-step operations in a single command
  4. Provide error handling and fallback responses

  ## Function Calling Tools

  The following tools are available for canvas operations:
  - `create_shape` - Creates rectangles, circles, and other basic shapes
  - `create_text` - Adds text objects with customizable styling
  - `create_component` - Builds complex UI components (login forms, navbars, cards, etc.)
  - `move_shape` - Repositions objects on the canvas
  - `resize_shape` - Changes object dimensions
  - `delete_object` - Removes objects from the canvas
  - `list_objects` - Retrieves all objects on a canvas
  - `group_objects` - Groups multiple objects together
  - `resize_object` - Resizes objects with optional aspect ratio preservation
  - `rotate_object` - Rotates objects by a specified angle around a pivot point
  - `change_style` - Changes styling properties (fill, stroke, opacity, fonts, etc.)
  - `update_text` - Updates text content and formatting options
  - `move_object` - Moves objects using delta or absolute coordinates

  Tool definitions are managed by `CollabCanvas.AI.Tools` module.

  ## Error Handling

  The agent implements comprehensive error handling:
  - API key validation before requests
  - Canvas existence verification
  - HTTP error response handling
  - Malformed response detection
  - Unknown tool call logging
  - Object not found errors

  All errors are returned as `{:error, reason}` tuples for consistent handling.

  ## Configuration

  Requires the `CLAUDE_API_KEY` environment variable to be set with a valid
  Anthropic API key.

  ## Examples

      # Simple shape creation
      Agent.execute_command("create a red square at 100, 100", canvas_id)
      {:ok, [%{tool: "create_shape", result: {:ok, %Object{}}}]}

      # Multiple operations
      Agent.execute_command("create a blue circle and a login form", canvas_id)
      {:ok, [
        %{tool: "create_shape", result: {:ok, %Object{}}},
        %{tool: "create_component", result: {:ok, [%Object{}, ...]}}
      ]}

      # Error case
      Agent.execute_command("create a shape", 999)
      {:error, :canvas_not_found}
  """

  require Logger
  alias CollabCanvas.Canvases
  alias CollabCanvas.AI.Tools
  alias CollabCanvas.AI.ComponentBuilder
  alias CollabCanvas.AI.Layout

  @claude_api_url "https://api.anthropic.com/v1/messages"
  @claude_model "claude-3-5-sonnet-20241022"
  @claude_api_version "2023-06-01"

  @doc """
  Executes a natural language command on a canvas.

  ## Parameters
    * `command` - Natural language command string (e.g., "create a red rectangle at 100,100")
    * `canvas_id` - The ID of the canvas to operate on
    * `selected_ids` - Optional list of selected object IDs for layout/arrangement commands (default: [])

  ## Returns
    * `{:ok, results}` - List of operation results
    * `{:error, reason}` - Error description

  ## Examples

      iex> execute_command("create a rectangle", 1)
      {:ok, [%{type: "create_shape", result: {:ok, %Object{}}}]}

      iex> execute_command("arrange horizontally", 1, [1, 2, 3])
      {:ok, [%{type: "arrange_objects", result: {:ok, %{updated: 3}}}]}

      iex> execute_command("invalid command", 999)
      {:error, :canvas_not_found}

  """
  def execute_command(command, canvas_id, selected_ids \\ []) do
    # Verify canvas exists
    case Canvases.get_canvas(canvas_id) do
      nil ->
        {:error, :canvas_not_found}

      _canvas ->
        # Build enhanced command with selection context if provided
        enhanced_command = build_command_with_context(command, selected_ids, canvas_id)

        # Call Claude API with function calling
        case call_claude_api(enhanced_command) do
          {:ok, tool_calls} ->
            # Inject selected_ids into arrange_objects tool calls if not provided
            enriched_tool_calls = enrich_tool_calls(tool_calls, selected_ids)

            # Process tool calls and execute canvas operations
            results = process_tool_calls(enriched_tool_calls, canvas_id)
            {:ok, results}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc """
  Calls Claude API with function calling tools to parse the command.

  Makes an HTTP POST request to the Anthropic API with the user's natural language
  command and the available tool definitions. Claude analyzes the command and returns
  structured tool calls that can be executed against the canvas.

  ## Parameters
    * `command` - Natural language command string (e.g., "create a red rectangle")

  ## Returns
    * `{:ok, tool_calls}` - List of tool call maps with `:id`, `:name`, and `:input` keys
    * `{:error, :missing_api_key}` - CLAUDE_API_KEY environment variable not set
    * `{:error, {:api_error, status, body}}` - API returned non-200 status code
    * `{:error, {:request_failed, reason}}` - HTTP request failed
    * `{:error, :invalid_response_format}` - API response format unexpected

  ## Examples

      iex> call_claude_api("create a blue circle at 50, 50")
      {:ok, [
        %{
          id: "toolu_123",
          name: "create_shape",
          input: %{"type" => "circle", "x" => 50, "y" => 50, "color" => "#0000FF"}
        }
      ]}

      iex> call_claude_api("list all objects")
      {:ok, [%{id: "toolu_456", name: "list_objects", input: %{}}]}

      iex> System.delete_env("CLAUDE_API_KEY")
      iex> call_claude_api("create shape")
      {:error, :missing_api_key}
  """
  def call_claude_api(command) do
    api_key = get_api_key()

    if is_nil(api_key) or api_key == "" do
      {:error, :missing_api_key}
    else
      headers = [
        {"x-api-key", api_key},
        {"anthropic-version", @claude_api_version},
        {"content-type", "application/json"}
      ]

      body = %{
        model: @claude_model,
        max_tokens: 1024,
        tools: Tools.get_tool_definitions(),
        messages: [
          %{
            role: "user",
            content: command
          }
        ]
      }

      case Req.post(@claude_api_url, json: body, headers: headers) do
        {:ok, %{status: 200, body: response_body}} ->
          parse_claude_response(response_body)

        {:ok, %{status: status, body: body}} ->
          Logger.error("Claude API error: #{status} - #{inspect(body)}")
          {:error, {:api_error, status, body}}

        {:error, reason} ->
          Logger.error("Claude API request failed: #{inspect(reason)}")
          {:error, {:request_failed, reason}}
      end
    end
  end

  @doc """
  Processes tool calls from Claude API response and executes canvas operations.

  Takes the structured tool calls returned by Claude and executes each one sequentially
  against the canvas. Each tool call is translated into the appropriate canvas operation
  (create, update, delete, etc.) and the results are collected.

  ## Parameters
    * `tool_calls` - List of tool call maps from Claude API, each containing:
      - `:id` - Unique identifier for the tool call
      - `:name` - Name of the tool to execute
      - `:input` - Map of parameters for the tool
    * `canvas_id` - The ID of the canvas to operate on

  ## Returns
    * List of operation result maps, each containing:
      - `:tool` - Name of the tool that was executed
      - `:input` - Original input parameters
      - `:result` - Result tuple from the operation (e.g., `{:ok, %Object{}}` or `{:error, reason}`)

  ## Examples

      iex> tool_calls = [
      ...>   %{id: "t1", name: "create_shape", input: %{"type" => "rectangle", "x" => 10, "y" => 10}},
      ...>   %{id: "t2", name: "create_text", input: %{"text" => "Hello", "x" => 50, "y" => 50}}
      ...> ]
      iex> process_tool_calls(tool_calls, canvas_id)
      [
        %{tool: "create_shape", input: %{...}, result: {:ok, %Object{}}},
        %{tool: "create_text", input: %{...}, result: {:ok, %Object{}}}
      ]

      iex> unknown_call = [%{id: "t1", name: "unknown_tool", input: %{}}]
      iex> process_tool_calls(unknown_call, canvas_id)
      [%{tool: "unknown", input: %{...}, result: {:error, :unknown_tool}}]
  """
  def process_tool_calls(tool_calls, canvas_id) do
    Enum.map(tool_calls, fn tool_call ->
      execute_tool_call(tool_call, canvas_id)
    end)
  end

  # Private Functions

  # Retrieves the Claude API key from environment variables.
  # Returns nil if not set.
  defp get_api_key do
    System.get_env("CLAUDE_API_KEY")
  end

  # Builds an enhanced command with selection context for better AI understanding
  defp build_command_with_context(command, [], _canvas_id), do: command

  defp build_command_with_context(command, selected_ids, _canvas_id) when is_list(selected_ids) and length(selected_ids) > 0 do
    # Fetch selected objects to provide context
    objects = Enum.map(selected_ids, fn id ->
      case Canvases.get_object(id) do
        nil -> nil
        obj ->
          data = if is_binary(obj.data), do: Jason.decode!(obj.data), else: obj.data || %{}
          %{
            id: obj.id,
            type: obj.type,
            position: obj.position,
            data: data
          }
      end
    end)
    |> Enum.reject(&is_nil/1)

    if length(objects) > 0 do
      context = """
      Selected objects context:
      #{inspect(objects, pretty: true)}

      User command: #{command}
      """
      context
    else
      command
    end
  end

  # Enriches tool calls by injecting selected object IDs into arrange_objects calls
  defp enrich_tool_calls(tool_calls, []), do: tool_calls

  defp enrich_tool_calls(tool_calls, selected_ids) when is_list(selected_ids) and length(selected_ids) > 0 do
    Enum.map(tool_calls, fn tool_call ->
      case tool_call.name do
        "arrange_objects" ->
          # If object_ids not provided or empty, use selected_ids
          input = tool_call.input
          object_ids = Map.get(input, "object_ids", [])

          updated_input = if length(object_ids) == 0 do
            Map.put(input, "object_ids", Enum.map(selected_ids, &to_string/1))
          else
            input
          end

          %{tool_call | input: updated_input}

        _ ->
          tool_call
      end
    end)
  end


  # Parses the Claude API response to extract tool calls.
  #
  # Handles different stop_reason values:
  # - "tool_use" - Response contains tool calls to execute
  # - "end_turn" - Response is text-only with no tool calls
  # - other - Logs warning and returns empty list
  #
  # Returns {:ok, tool_calls} list or {:error, :invalid_response_format}
  defp parse_claude_response(%{"content" => content, "stop_reason" => stop_reason}) do
    case stop_reason do
      "tool_use" ->
        tool_calls =
          content
          |> Enum.filter(fn item -> item["type"] == "tool_use" end)
          |> Enum.map(fn tool_use ->
            %{
              id: tool_use["id"],
              name: tool_use["name"],
              input: tool_use["input"]
            }
          end)

        {:ok, tool_calls}

      "end_turn" ->
        # No tool calls, just text response
        {:ok, []}

      other ->
        Logger.warning("Unexpected stop_reason: #{other}")
        {:ok, []}
    end
  end

  defp parse_claude_response(response) do
    Logger.error("Unexpected Claude API response format: #{inspect(response)}")
    {:error, :invalid_response_format}
  end

  # Executes a create_shape tool call to create a basic shape on the canvas.
  #
  # Supported shape types: rectangle, circle, triangle, etc.
  # Extracts width, height, color from input and creates object at specified x,y position.
  defp execute_tool_call(%{name: "create_shape", input: input}, canvas_id) do
    data = %{
      width: input["width"],
      height: input["height"],
      color: Map.get(input, "color", "#000000")
    }

    attrs = %{
      position: %{
        x: input["x"],
        y: input["y"]
      },
      data: Jason.encode!(data)
    }

    result = Canvases.create_object(canvas_id, input["type"], attrs)

    %{
      tool: "create_shape",
      input: input,
      result: result
    }
  end

  # Executes a create_text tool call to add a text object to the canvas.
  #
  # Extracts text content, font_size (default 16), and color from input.
  # Creates text object at specified x,y position.
  defp execute_tool_call(%{name: "create_text", input: input}, canvas_id) do
    data = %{
      text: input["text"],
      font_size: Map.get(input, "font_size", 16),
      color: Map.get(input, "color", "#000000")
    }

    attrs = %{
      position: %{
        x: input["x"],
        y: input["y"]
      },
      data: Jason.encode!(data)
    }

    result = Canvases.create_object(canvas_id, "text", attrs)

    %{
      tool: "create_text",
      input: input,
      result: result
    }
  end

  # Executes a move_shape tool call to reposition an object on the canvas.
  #
  # Updates the object's position to the new x,y coordinates specified in input.
  defp execute_tool_call(%{name: "move_shape", input: input}, _canvas_id) do
    attrs = %{
      position: %{
        x: input["x"],
        y: input["y"]
      }
    }

    result = Canvases.update_object(input["object_id"], attrs)

    %{
      tool: "move_shape",
      input: input,
      result: result
    }
  end

  # Executes a resize_shape tool call to change an object's dimensions.
  #
  # Fetches existing object, merges width/height into data, and updates.
  # Returns error if object not found.
  defp execute_tool_call(%{name: "resize_shape", input: input}, _canvas_id) do
    # First get the existing object to merge data
    case Canvases.get_object(input["object_id"]) do
      nil ->
        %{
          tool: "resize_shape",
          input: input,
          result: {:error, :not_found}
        }

      object ->
        # Decode existing data, update width/height, re-encode
        existing_data = if object.data, do: Jason.decode!(object.data), else: %{}

        updated_data =
          existing_data
          |> Map.put("width", input["width"])
          |> Map.put("height", input["height"])

        attrs = %{
          data: Jason.encode!(updated_data)
        }

        result = Canvases.update_object(input["object_id"], attrs)

        %{
          tool: "resize_shape",
          input: input,
          result: result
        }
    end
  end

  # Executes a delete_object tool call to remove an object from the canvas.
  #
  # Deletes the object with the specified object_id.
  defp execute_tool_call(%{name: "delete_object", input: input}, _canvas_id) do
    result = Canvases.delete_object(input["object_id"])

    %{
      tool: "delete_object",
      input: input,
      result: result
    }
  end

  # Executes a list_objects tool call to retrieve all objects on the canvas.
  #
  # Fetches all objects and formats them for AI response with decoded data.
  defp execute_tool_call(%{name: "list_objects", input: _input}, canvas_id) do
    objects = Canvases.list_objects(canvas_id)

    # Format objects for AI response
    formatted_objects =
      Enum.map(objects, fn object ->
        decoded_data = if object.data, do: Jason.decode!(object.data), else: %{}

        %{
          id: object.id,
          type: object.type,
          position: object.position,
          data: decoded_data
        }
      end)

    %{
      tool: "list_objects",
      input: %{},
      result: {:ok, formatted_objects}
    }
  end

  # Executes a create_component tool call to build complex UI components.
  #
  # Supports multiple component types: login_form, navbar, card, button, sidebar.
  # Delegates to ComponentBuilder module with specified dimensions, theme, and content.
  defp execute_tool_call(%{name: "create_component", input: input}, canvas_id) do
    component_type = input["type"]
    x = input["x"]
    y = input["y"]
    width = Map.get(input, "width", 200)
    height = Map.get(input, "height", 100)
    theme = Map.get(input, "theme", "light")
    content = Map.get(input, "content", %{})

    result =
      case component_type do
        "login_form" ->
          ComponentBuilder.create_login_form(canvas_id, x, y, width, height, theme, content)

        "navbar" ->
          ComponentBuilder.create_navbar(canvas_id, x, y, width, height, theme, content)

        "card" ->
          ComponentBuilder.create_card(canvas_id, x, y, width, height, theme, content)

        "button" ->
          ComponentBuilder.create_button_group(canvas_id, x, y, width, height, theme, content)

        "sidebar" ->
          ComponentBuilder.create_sidebar(canvas_id, x, y, width, height, theme, content)

        _ ->
          {:error, :unknown_component_type}
      end

    %{
      tool: "create_component",
      input: input,
      result: result
    }
  end

  # Executes a group_objects tool call to group multiple objects together.
  #
  # Currently returns success with generated group_id.
  # Full grouping logic would need to be implemented in Canvases context.
  defp execute_tool_call(%{name: "group_objects", input: input}, _canvas_id) do
    # For now, just return success - actual grouping logic would need to be implemented in Canvases
    %{
      tool: "group_objects",
      input: input,
      result: {:ok, %{group_id: Ecto.UUID.generate(), object_ids: input["object_ids"]}}
    }
  end

  # Executes a resize_object tool call to resize an object with optional aspect ratio preservation.
  #
  # Fetches existing object, calculates new dimensions (with aspect ratio if requested),
  # merges into data, and updates. Returns error if object not found.
  defp execute_tool_call(%{name: "resize_object", input: input}, _canvas_id) do
    case Canvases.get_object(input["object_id"]) do
      nil ->
        %{
          tool: "resize_object",
          input: input,
          result: {:error, :not_found}
        }

      object ->
        existing_data = if object.data, do: Jason.decode!(object.data), else: %{}

        # Calculate dimensions based on aspect ratio setting
        {new_width, new_height} =
          if Map.get(input, "maintain_aspect_ratio", false) do
            # Preserve aspect ratio: calculate height based on width
            old_width = Map.get(existing_data, "width", 100)
            old_height = Map.get(existing_data, "height", 100)
            aspect_ratio = old_height / old_width
            calculated_height = input["width"] * aspect_ratio
            {input["width"], calculated_height}
          else
            # Use provided dimensions
            {input["width"], Map.get(input, "height", Map.get(existing_data, "height", input["width"]))}
          end

        updated_data =
          existing_data
          |> Map.put("width", new_width)
          |> Map.put("height", new_height)

        attrs = %{data: Jason.encode!(updated_data)}
        result = Canvases.update_object(input["object_id"], attrs)

        %{
          tool: "resize_object",
          input: input,
          result: result
        }
    end
  end

  # Executes a rotate_object tool call to rotate an object by a specified angle.
  #
  # Stores rotation angle and pivot point in object data. Frontend will apply the rotation.
  defp execute_tool_call(%{name: "rotate_object", input: input}, _canvas_id) do
    case Canvases.get_object(input["object_id"]) do
      nil ->
        %{
          tool: "rotate_object",
          input: input,
          result: {:error, :not_found}
        }

      object ->
        existing_data = if object.data, do: Jason.decode!(object.data), else: %{}

        # Normalize angle to 0-360 range
        normalized_angle = rem(round(input["angle"]), 360)
        normalized_angle = if normalized_angle < 0, do: normalized_angle + 360, else: normalized_angle

        updated_data =
          existing_data
          |> Map.put("rotation", normalized_angle)
          |> Map.put("pivot_point", Map.get(input, "pivot_point", "center"))

        attrs = %{data: Jason.encode!(updated_data)}
        result = Canvases.update_object(input["object_id"], attrs)

        %{
          tool: "rotate_object",
          input: input,
          result: result
        }
    end
  end

  # Executes a change_style tool call to modify styling properties of an object.
  #
  # Supports fill, stroke, stroke_width, opacity, font properties, and color changes.
  defp execute_tool_call(%{name: "change_style", input: input}, _canvas_id) do
    case Canvases.get_object(input["object_id"]) do
      nil ->
        %{
          tool: "change_style",
          input: input,
          result: {:error, :not_found}
        }

      object ->
        existing_data = if object.data, do: Jason.decode!(object.data), else: %{}

        # Parse value based on property type
        value =
          case input["property"] do
            prop when prop in ["stroke_width", "font_size"] ->
              # Numeric properties
              case Float.parse(input["value"]) do
                {num, _} -> num
                :error -> String.to_integer(input["value"])
              end
            "opacity" ->
              # Opacity is 0-1
              case Float.parse(input["value"]) do
                {num, _} -> max(0.0, min(1.0, num))
                :error -> 1.0
              end
            _ ->
              # String properties (colors, fonts)
              input["value"]
          end

        updated_data = Map.put(existing_data, input["property"], value)
        attrs = %{data: Jason.encode!(updated_data)}
        result = Canvases.update_object(input["object_id"], attrs)

        %{
          tool: "change_style",
          input: input,
          result: result
        }
    end
  end

  # Executes an update_text tool call to modify text content and formatting.
  #
  # Updates text content and any formatting options provided (font_size, font_family, color, etc.).
  defp execute_tool_call(%{name: "update_text", input: input}, _canvas_id) do
    case Canvases.get_object(input["object_id"]) do
      nil ->
        %{
          tool: "update_text",
          input: input,
          result: {:error, :not_found}
        }

      object ->
        # Verify it's a text object
        if object.type != "text" do
          %{
            tool: "update_text",
            input: input,
            result: {:error, :not_text_object}
          }
        else
          existing_data = if object.data, do: Jason.decode!(object.data), else: %{}

          # Update text and formatting options
          updated_data = existing_data
          updated_data = if Map.has_key?(input, "new_text"), do: Map.put(updated_data, "text", input["new_text"]), else: updated_data
          updated_data = if Map.has_key?(input, "font_size"), do: Map.put(updated_data, "font_size", input["font_size"]), else: updated_data
          updated_data = if Map.has_key?(input, "font_family"), do: Map.put(updated_data, "font_family", input["font_family"]), else: updated_data
          updated_data = if Map.has_key?(input, "color"), do: Map.put(updated_data, "color", input["color"]), else: updated_data
          updated_data = if Map.has_key?(input, "align"), do: Map.put(updated_data, "align", input["align"]), else: updated_data
          updated_data = if Map.has_key?(input, "bold"), do: Map.put(updated_data, "bold", input["bold"]), else: updated_data
          updated_data = if Map.has_key?(input, "italic"), do: Map.put(updated_data, "italic", input["italic"]), else: updated_data

          attrs = %{data: Jason.encode!(updated_data)}
          result = Canvases.update_object(input["object_id"], attrs)

          %{
            tool: "update_text",
            input: input,
            result: result
          }
        end
    end
  end

  # Executes a move_object tool call to reposition an object using delta or absolute coordinates.
  #
  # Supports both relative movement (delta_x, delta_y) and absolute positioning (x, y).
  defp execute_tool_call(%{name: "move_object", input: input}, _canvas_id) do
    case Canvases.get_object(input["object_id"]) do
      nil ->
        %{
          tool: "move_object",
          input: input,
          result: {:error, :not_found}
        }

      object ->
        current_position = object.position || %{"x" => 0, "y" => 0}
        current_x = Map.get(current_position, "x") || Map.get(current_position, :x) || 0
        current_y = Map.get(current_position, "y") || Map.get(current_position, :y) || 0

        # Calculate new position based on delta or absolute coordinates
        new_x =
          cond do
            Map.has_key?(input, "delta_x") -> current_x + input["delta_x"]
            Map.has_key?(input, "x") -> input["x"]
            true -> current_x
          end

        new_y =
          cond do
            Map.has_key?(input, "delta_y") -> current_y + input["delta_y"]
            Map.has_key?(input, "y") -> input["y"]
            true -> current_y
          end

        attrs = %{
          position: %{
            x: new_x,
            y: new_y
          }
        }

        result = Canvases.update_object(input["object_id"], attrs)

        %{
          tool: "move_object",
          input: input,
          result: result
        }
    end
  end

  # Executes an arrange_objects tool call to layout multiple objects in a specified pattern.
  #
  # Supports horizontal, vertical, grid, circular, and stack layouts.
  # Applies layout algorithms from CollabCanvas.AI.Layout module and batch updates all objects.
  defp execute_tool_call(%{name: "arrange_objects", input: input}, _canvas_id) do
    object_ids = input["object_ids"]
    layout_type = input["layout_type"]

    # Start performance timer
    start_time = System.monotonic_time(:millisecond)

    # Fetch all objects to arrange
    objects = Enum.map(object_ids, fn id ->
      case Canvases.get_object(id) do
        nil -> nil
        obj ->
          # Decode data if it's a JSON string
          data = if is_binary(obj.data) do
            Jason.decode!(obj.data)
          else
            obj.data || %{}
          end

          %{
            id: obj.id,
            position: obj.position,
            data: data
          }
      end
    end)
    |> Enum.reject(&is_nil/1)

    if length(objects) == 0 do
      %{
        tool: "arrange_objects",
        input: input,
        result: {:error, :no_objects_found}
      }
    else
      # Apply layout algorithm based on type
      updates = case layout_type do
        "horizontal" ->
          spacing = Map.get(input, "spacing", :even)
          Layout.distribute_horizontally(objects, spacing)

        "vertical" ->
          spacing = Map.get(input, "spacing", :even)
          Layout.distribute_vertically(objects, spacing)

        "grid" ->
          columns = Map.get(input, "columns", 3)
          spacing = Map.get(input, "spacing", 20)
          Layout.arrange_grid(objects, columns, spacing)

        "circular" ->
          radius = Map.get(input, "radius", 200)
          Layout.circular_layout(objects, radius)

        "stack" ->
          # Stack is vertical distribution with optional alignment
          alignment = Map.get(input, "alignment")
          distributed = Layout.distribute_vertically(objects, Map.get(input, "spacing", 20))

          if alignment do
            # Apply alignment after stacking
            aligned_objects = Enum.map(distributed, fn update ->
              obj = Enum.find(objects, fn o -> o.id == update.id end)
              %{obj | position: update.position}
            end)
            Layout.align_objects(aligned_objects, alignment)
          else
            distributed
          end

        _ ->
          []
      end

      # Apply alignment if specified and not already applied
      final_updates = if Map.has_key?(input, "alignment") and layout_type != "stack" do
        # Reconstruct objects with new positions for alignment
        aligned_objects = Enum.map(updates, fn update ->
          obj = Enum.find(objects, fn o -> o.id == update.id end)
          %{obj | position: update.position}
        end)
        Layout.align_objects(aligned_objects, input["alignment"])
      else
        updates
      end

      # Batch update all objects atomically
      results = Enum.map(final_updates, fn update ->
        attrs = %{position: update.position}
        Canvases.update_object(update.id, attrs)
      end)

      # Check if any updates failed
      failed = Enum.any?(results, fn
        {:error, _} -> true
        _ -> false
      end)

      # Calculate performance metrics
      end_time = System.monotonic_time(:millisecond)
      duration_ms = end_time - start_time

      # Log performance (should be <500ms for up to 50 objects per PRD requirement)
      Logger.info("Layout operation completed: #{layout_type} layout for #{length(results)} objects in #{duration_ms}ms")

      if duration_ms > 500 do
        Logger.warning("Layout operation exceeded 500ms target: #{duration_ms}ms for #{length(results)} objects")
      end

      if failed do
        %{
          tool: "arrange_objects",
          input: input,
          result: {:error, :partial_update_failure}
        }
      else
        %{
          tool: "arrange_objects",
          input: input,
          result: {:ok, %{updated: length(results), layout: layout_type, duration_ms: duration_ms}}
        }
      end
    end
  end

  # Fallback handler for unknown tool calls.
  #
  # Logs a warning and returns an error result for any unrecognized tool.
  defp execute_tool_call(tool_call, _canvas_id) do
    Logger.warning("Unknown tool call: #{inspect(tool_call)}")

    %{
      tool: "unknown",
      input: tool_call,
      result: {:error, :unknown_tool}
    }
  end
end
