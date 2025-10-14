defmodule CollabCanvas.AI.Agent do
  @moduledoc """
  AI Agent for executing natural language commands on canvas.
  Integrates with Claude API to process user commands and execute canvas operations.
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

  ## Parameters
    * `command` - Natural language command string

  ## Returns
    * `{:ok, tool_calls}` - List of tool calls to execute
    * `{:error, reason}` - Error description
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

  ## Parameters
    * `tool_calls` - List of tool call maps from Claude API
    * `canvas_id` - The ID of the canvas to operate on

  ## Returns
    * List of operation results
  """
  def process_tool_calls(tool_calls, canvas_id) do
    Enum.map(tool_calls, fn tool_call ->
      execute_tool_call(tool_call, canvas_id)
    end)
  end

  # Private Functions

  defp get_api_key do
    System.get_env("CLAUDE_API_KEY")
  end


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

  defp execute_tool_call(%{name: "delete_object", input: input}, _canvas_id) do
    result = Canvases.delete_object(input["object_id"])

    %{
      tool: "delete_object",
      input: input,
      result: result
    }
  end

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

  defp execute_tool_call(%{name: "group_objects", input: input}, _canvas_id) do
    # For now, just return success - actual grouping logic would need to be implemented in Canvases
    %{
      tool: "group_objects",
      input: input,
      result: {:ok, %{group_id: Ecto.UUID.generate(), object_ids: input["object_ids"]}}
    }
  end

  defp execute_tool_call(tool_call, _canvas_id) do
    Logger.warning("Unknown tool call: #{inspect(tool_call)}")

    %{
      tool: "unknown",
      input: tool_call,
      result: {:error, :unknown_tool}
    }
  end
end
