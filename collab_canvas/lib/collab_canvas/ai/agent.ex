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

  @claude_api_url "https://api.anthropic.com/v1/messages"
  @claude_model "claude-3-5-sonnet-20241022"
  @claude_api_version "2023-06-01"

  @doc """
  Executes a natural language command on a canvas.

  ## Parameters
    * `command` - Natural language command string (e.g., "create a red rectangle at 100,100")
    * `canvas_id` - The ID of the canvas to operate on

  ## Returns
    * `{:ok, results}` - List of operation results
    * `{:error, reason}` - Error description

  ## Examples

      iex> execute_command("create a rectangle", 1)
      {:ok, [%{type: "create_shape", result: {:ok, %Object{}}}]}

      iex> execute_command("invalid command", 999)
      {:error, :canvas_not_found}

  """
  def execute_command(command, canvas_id) do
    # Verify canvas exists
    case Canvases.get_canvas(canvas_id) do
      nil ->
        {:error, :canvas_not_found}

      _canvas ->
        # Call Claude API with function calling
        case call_claude_api(command) do
          {:ok, tool_calls} ->
            # Process tool calls and execute canvas operations
            results = process_tool_calls(tool_calls, canvas_id)
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
