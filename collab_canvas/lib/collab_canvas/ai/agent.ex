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

  @groq_api_url "https://api.groq.com/openai/v1/chat/completions"
  @default_groq_model "llama-3.3-70b-versatile"

  @openai_api_url "https://api.openai.com/v1/chat/completions"
  @default_openai_model "gpt-4o"

  @doc """
  Executes a natural language command on a canvas.

  ## Parameters
    * `command` - Natural language command string (e.g., "create a red rectangle at 100,100")
    * `canvas_id` - The ID of the canvas to operate on
    * `selected_ids` - Optional list of selected object IDs for layout/arrangement commands (default: [])
    * `opts` - Optional keyword list with:
      - `:current_color` - Current color from color picker to use as default for new objects

  ## Returns
    * `{:ok, results}` - List of operation results
    * `{:error, reason}` - Error description

  ## Examples

      iex> execute_command("create a rectangle", 1)
      {:ok, [%{type: "create_shape", result: {:ok, %Object{}}}]}

      iex> execute_command("arrange horizontally", 1, [1, 2, 3])
      {:ok, [%{type: "arrange_objects", result: {:ok, %{updated: 3}}}]}

      iex> execute_command("create a circle", 1, [], current_color: "#FF0000")
      {:ok, [%{type: "create_shape", result: {:ok, %Object{data: "{\"color\":\"#FF0000\"}"}}}]}

      iex> execute_command("invalid command", 999)
      {:error, :canvas_not_found}

  """
  def execute_command(command, canvas_id, selected_ids \\ [], opts \\ []) do
    # Extract current color from options
    current_color = Keyword.get(opts, :current_color, "#000000")

    # Verify canvas exists
    case Canvases.get_canvas(canvas_id) do
      nil ->
        {:error, :canvas_not_found}

      _canvas ->
        # Build enhanced command with selection context if provided
        enhanced_command = build_command_with_context(command, selected_ids, canvas_id, current_color)

        Logger.info("Calling AI API with command: #{command}")

        # Call Claude API with function calling
        case call_claude_api(enhanced_command) do
          {:ok, {:text_response, text}} ->
            # AI returned text (e.g., asking for clarification)
            Logger.info("AI returned text response: #{text}")
            {:ok, {:text_response, text}}

          {:ok, tool_calls} when is_list(tool_calls) ->
            # Log when AI returns no tools (might indicate confusion)
            Logger.info("AI returned #{length(tool_calls)} tool call(s)")

            if length(tool_calls) == 0 do
              Logger.warning("AI returned no tool calls for command: #{command}")
            end

            # Inject selected_ids into arrange_objects tool calls if not provided
            enriched_tool_calls = enrich_tool_calls(tool_calls, selected_ids)

            # Process tool calls and execute canvas operations
            results = process_tool_calls(enriched_tool_calls, canvas_id, current_color)
            {:ok, results}

          {:error, reason} ->
            Logger.error("AI API call failed: #{inspect(reason)}")
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
    provider = get_ai_provider()

    case provider do
      "openai" -> call_openai_api(command)
      "groq" -> call_groq_api(command)
      "claude" -> call_anthropic_api(command)
      _ -> call_anthropic_api(command)  # Default to Claude
    end
  end

  defp call_anthropic_api(command) do
    api_key = System.get_env("CLAUDE_API_KEY")

    if is_nil(api_key) or api_key == "" or api_key == "your_key_here" do
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

  defp call_groq_api(command) do
    api_key = System.get_env("GROQ_API_KEY")
    model = System.get_env("GROQ_MODEL") || @default_groq_model

    Logger.info("Using Groq API with model: #{model}")

    if is_nil(api_key) or api_key == "" do
      {:error, :missing_api_key}
    else
      headers = [
        {"Authorization", "Bearer #{api_key}"},
        {"content-type", "application/json"}
      ]

      # Convert Claude tool format to OpenAI function format (Groq uses OpenAI-compatible format)
      tools = Enum.map(Tools.get_tool_definitions(), fn tool ->
        %{
          type: "function",
          function: %{
            name: tool.name,
            description: tool.description,
            parameters: tool.input_schema
          }
        }
      end)

      body = %{
        model: model,
        messages: [
          %{
            role: "user",
            content: command
          }
        ],
        tools: tools,
        tool_choice: "auto",
        max_completion_tokens: 4096,
        temperature: 0.5
      }

      Logger.debug("Sending request to Groq API...")

      case Req.post(@groq_api_url, json: body, headers: headers) do
        {:ok, %{status: 200, body: response_body}} ->
          Logger.debug("Groq API responded successfully")
          parse_openai_response(response_body)

        {:ok, %{status: status, body: body}} ->
          Logger.error("Groq API error: #{status} - #{inspect(body)}")
          {:error, {:api_error, status, body}}

        {:error, reason} ->
          Logger.error("Groq API request failed: #{inspect(reason)}")
          {:error, {:request_failed, reason}}
      end
    end
  end

  defp call_openai_api(command) do
    api_key = System.get_env("OPENAI_API_KEY")
    model = System.get_env("OPENAI_MODEL") || @default_openai_model

    if is_nil(api_key) or api_key == "" or String.starts_with?(api_key, "sk-proj-") == false do
      {:error, :missing_api_key}
    else
      headers = [
        {"Authorization", "Bearer #{api_key}"},
        {"content-type", "application/json"}
      ]

      # Convert Claude tool format to OpenAI function format
      tools = Enum.map(Tools.get_tool_definitions(), fn tool ->
        %{
          type: "function",
          function: %{
            name: tool.name,
            description: tool.description,
            parameters: tool.input_schema
          }
        }
      end)

      body = %{
        model: model,
        messages: [
          %{
            role: "user",
            content: command
          }
        ],
        tools: tools,
        tool_choice: "auto"
      }

      case Req.post(@openai_api_url, json: body, headers: headers) do
        {:ok, %{status: 200, body: response_body}} ->
          parse_openai_response(response_body)

        {:ok, %{status: status, body: body}} ->
          Logger.error("OpenAI API error: #{status} - #{inspect(body)}")
          {:error, {:api_error, status, body}}

        {:error, reason} ->
          Logger.error("OpenAI API request failed: #{inspect(reason)}")
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
    * `current_color` - Current color from color picker to use as default for new objects

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
      iex> process_tool_calls(tool_calls, canvas_id, "#FF0000")
      [
        %{tool: "create_shape", input: %{...}, result: {:ok, %Object{}}},
        %{tool: "create_text", input: %{...}, result: {:ok, %Object{}}}
      ]

      iex> unknown_call = [%{id: "t1", name: "unknown_tool", input: %{}}]
      iex> process_tool_calls(unknown_call, canvas_id, "#000000")
      [%{tool: "unknown", input: %{...}, result: {:error, :unknown_tool}}]
  """
  def process_tool_calls(tool_calls, canvas_id, current_color \\ "#000000") do
    Enum.map(tool_calls, fn tool_call ->
      # Normalize tool call input (coerce string IDs to integers)
      normalized_call = normalize_tool_input(tool_call)
      execute_tool_call(normalized_call, canvas_id, current_color)
    end)
  end

  # Normalizes tool call inputs by coercing string IDs to integers
  # Some AI providers (like Groq) return object_id as strings despite schema specifying integer
  defp normalize_tool_input(%{name: name, input: input} = tool_call) do
    normalized_input = input
    |> normalize_id_field("object_id")
    |> normalize_id_field("shape_id")
    |> normalize_id_array_field("object_ids")

    %{tool_call | input: normalized_input}
  end

  # Coerces a single ID field from string to integer if present
  defp normalize_id_field(input, field_name) do
    case Map.get(input, field_name) do
      id when is_binary(id) ->
        case Integer.parse(id) do
          {int_id, _} -> Map.put(input, field_name, int_id)
          :error -> input
        end
      _ -> input
    end
  end

  # Coerces an array of IDs from strings to integers if present
  defp normalize_id_array_field(input, field_name) do
    case Map.get(input, field_name) do
      ids when is_list(ids) ->
        normalized_ids = Enum.map(ids, fn
          id when is_binary(id) ->
            case Integer.parse(id) do
              {int_id, _} -> int_id
              :error -> id
            end
          id -> id
        end)
        Map.put(input, field_name, normalized_ids)
      _ -> input
    end
  end

  # Private Functions

  # Retrieves the AI provider setting from environment variables.
  # Returns "claude", "groq", or "openai". Defaults to "claude" if not set.
  defp get_ai_provider do
    System.get_env("AI_PROVIDER") || "claude"
  end

  # Builds an enhanced command with all canvas objects and their human-readable names
  defp build_command_with_context(command, selected_ids, canvas_id, current_color) do
    # Fetch all canvas objects
    all_objects = Canvases.list_objects(canvas_id)

    # Generate human-readable display names (e.g., "Rectangle 1", "Circle 2")
    objects_with_names = generate_display_names(all_objects)

    # Build context with all objects and their display names
    available_objects_str = objects_with_names
    |> Enum.map(fn {obj, display_name} ->
      data = if is_binary(obj.data), do: Jason.decode!(obj.data), else: obj.data || %{}
      "  - #{display_name} (ID: #{obj.id}): #{obj.type} at (#{get_in(obj.position, ["x"])||0}, #{get_in(obj.position, ["y"])||0})"
    end)
    |> Enum.join("\n")

    # Build selected objects context if any
    selected_context = if is_list(selected_ids) and length(selected_ids) > 0 do
      selected_names = objects_with_names
      |> Enum.filter(fn {obj, _name} -> obj.id in selected_ids end)
      |> Enum.map(fn {_obj, name} -> name end)
      |> Enum.join(", ")

      "\nCurrently selected: #{selected_names}"
    else
      ""
    end

    # Build full context
    context = """
    CURRENT COLOR PICKER: #{current_color}
    - Use this color when creating new shapes/text UNLESS the user specifies a different color
    - If user says "create a rectangle" (without color), use #{current_color}
    - If user says "create a blue rectangle", use blue (#0000FF or similar)

    CANVAS OBJECTS (use these human-readable names in your responses):
    #{available_objects_str}#{selected_context}

    DISAMBIGUATION RULES:
    - When the user refers to "that square", "the circle", "that rectangle", etc. without specifying which one:
      * If objects are currently selected, operate on the selected objects
      * If no selection, ask the user to specify which one using the display names above (e.g., "Rectangle 1", "Circle 2")
      * If ambiguous and you must assume, use the most recently created object of that type

    - When referencing objects in tool calls, ALWAYS use the database ID (the number in parentheses), not the display name

    LAYOUT INTERPRETATION RULES:
    - "next to each other" / "side by side" = horizontal layout
    - "one after another horizontally" / "in a row" = horizontal layout
    - "one after another vertically" / "in a column" = vertical layout
    - "on top of each other" / "stacked" = vertical layout (stack type)
    - "line up" without direction specified = horizontal layout (most common interpretation)

    - When using horizontal or vertical layouts:
      * ALWAYS check object sizes before choosing spacing
      * If objects have vastly different sizes (>2x difference in width/height), use FIXED spacing (e.g., 20-30px) instead of :even
      * Fixed spacing prevents overlaps when size differences are large
      * Example: arrange_objects with layout_type="horizontal" and spacing=30 for different-sized objects

    - Default spacing recommendations:
      * Small objects (< 100px): spacing = 20
      * Medium objects (100-200px): spacing = 30
      * Large objects (> 200px): spacing = 40
      * Mixed sizes: use spacing >= largest dimension difference

    TOOL USAGE PHILOSOPHY - BE CREATIVE:
    - Your layout tools are HIGHLY FLEXIBLE - don't give up just because a pattern isn't explicitly named!
    - For complex formations (triangles, pyramids, spirals, custom patterns):
      * Use `arrange_objects_with_pattern` with line/diagonal/wave/arc patterns
      * Use `define_object_relationships` to build shapes with spatial constraints
      * Make MULTIPLE tool calls if needed to build complex shapes row by row or layer by layer
    - CRITICAL: How to create TRIANGLE/PYRAMID formations:
      * TRIANGLE = pyramid shape with rows getting wider (1 at top, 2 below, 3 below that, etc.)
      * For 6 objects triangle: Row 1 (1 object), Row 2 (2 objects), Row 3 (3 objects)
      * For 10 objects triangle: Rows of 1, 2, 3, 4 objects
      * METHOD 1: Make MULTIPLE `arrange_objects_with_pattern` calls - one line/horizontal per row
      * METHOD 2: Use `define_object_relationships` with "below" and "left_of"/"right_of" constraints
      * NEVER use just "diagonal" for triangles - that creates a diagonal LINE, not a triangle
    - Other examples:
      * Zigzag: `arrange_objects_with_pattern` with diagonal pattern alternating directions
      * Custom formations: Combine tools creatively or make sequential calls
    - Default to ATTEMPTING a layout with available tools before saying you can't do it
    - Only respond with text if the request is truly impossible with available tools

    CRITICAL EXECUTION RULES:
    - NEVER ask for permission or confirmation - JUST DO IT
    - NEVER respond with "Should I proceed?" or "Let me know if you'd like me to..." - EXECUTE IMMEDIATELY
    - When creating shapes/objects: Calculate positions and CALL create_shape/create_text tools multiple times
    - For grids/patterns: Make MULTIPLE tool calls in sequence with calculated x,y positions for each object
    - Example: "10x10 grid of circles" = make 100 create_shape tool calls with calculated positions (0,0), (50,0), (100,0)... etc.

    WHEN TO RESPOND WITH TEXT VS TOOLS:
    - USE TOOLS (ALWAYS PREFERRED): For any spatial arrangement, creation, or manipulation task
    - MAKE MULTIPLE TOOL CALLS: When creating patterns or grids, calculate positions and call create_shape for each object
    - USE TEXT ONLY WHEN: Truly impossible with available tools (e.g., "delete the database") or genuinely ambiguous (e.g., "that one" with no context)
    - You CAN show visual labels using show_object_labels tool when users ask to see IDs or names

    IMPORTANT: Your job is to EXECUTE, not to explain plans or ask permission. Users expect ACTION, not proposals.

    USER COMMAND: #{command}
    """

    context
  end

  # Generates human-readable display names for objects based on type and creation order
  # Returns list of {object, "Display Name"} tuples
  defp generate_display_names(objects) do
    # Sort by insertion time (oldest first)
    sorted_objects = Enum.sort_by(objects, & &1.inserted_at, DateTime)

    # Group by type and number them
    sorted_objects
    |> Enum.group_by(& &1.type)
    |> Enum.flat_map(fn {type, type_objects} ->
      type_objects
      |> Enum.with_index(1)
      |> Enum.map(fn {obj, index} ->
        display_name = format_display_name(type, index)
        {obj, display_name}
      end)
    end)
    |> Enum.sort_by(fn {obj, _name} -> obj.id end)
  end

  # Formats a display name for an object (e.g., "Rectangle 1", "Circle 2")
  defp format_display_name(type, index) do
    type_str = type |> String.capitalize()
    "#{type_str} #{index}"
  end

  # Enriches tool calls by injecting selected object IDs into arrange_objects calls
  defp enrich_tool_calls(tool_calls, []), do: tool_calls

  defp enrich_tool_calls(tool_calls, selected_ids) when is_list(selected_ids) and length(selected_ids) > 0 do
    Enum.map(tool_calls, fn tool_call ->
      case tool_call.name do
        "arrange_objects" ->
          # If object_ids not provided or empty, use selected_ids (as integers, matching schema)
          input = tool_call.input
          object_ids = Map.get(input, "object_ids", [])

          updated_input = if length(object_ids) == 0 do
            Map.put(input, "object_ids", selected_ids)
          else
            input
          end

          %{tool_call | input: updated_input}

        _ ->
          tool_call
      end
    end)
  end

  # Parses the Claude API response to extract tool calls or text responses.
  #
  # Handles different stop_reason values:
  # - "tool_use" - Response contains tool calls to execute
  # - "end_turn" - Response is text-only (e.g., AI asking for clarification)
  # - other - Logs warning and returns empty list
  #
  # Returns {:ok, tool_calls} list, {:ok, {:text_response, text}}, or {:error, :invalid_response_format}
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
        # Extract text response (AI might be asking for clarification)
        text_items = content
        |> Enum.filter(fn item -> item["type"] == "text" end)
        |> Enum.map(fn item -> item["text"] end)
        |> Enum.join("\n")

        if text_items != "" do
          {:ok, {:text_response, text_items}}
        else
          {:ok, []}
        end

      other ->
        Logger.warning("Unexpected stop_reason: #{other}")
        {:ok, []}
    end
  end

  defp parse_claude_response(response) do
    Logger.error("Unexpected Claude API response format: #{inspect(response)}")
    {:error, :invalid_response_format}
  end

  # Parses OpenAI/Groq API response (OpenAI format) to extract tool calls or text responses.
  #
  # The response format is different from Claude's:
  # - Uses "choices" array with "message" object
  # - Tool calls are in message.tool_calls array
  # - finish_reason can be "tool_calls" or "stop"
  #
  # Returns {:ok, tool_calls} list, {:ok, {:text_response, text}}, or {:error, :invalid_response_format}
  defp parse_openai_response(%{"choices" => [%{"message" => message} | _]}) do
    Logger.debug("Parsing OpenAI/Groq response message: #{inspect(Map.keys(message))}")

    case message do
      %{"tool_calls" => tool_calls} when is_list(tool_calls) ->
        Logger.debug("Found #{length(tool_calls)} tool calls")
        parsed_calls = Enum.map(tool_calls, fn tool_call ->
          %{
            id: tool_call["id"],
            name: tool_call["function"]["name"],
            input: Jason.decode!(tool_call["function"]["arguments"])
          }
        end)
        {:ok, parsed_calls}

      %{"content" => content} when is_binary(content) and content != "" ->
        # AI returned text response (asking for clarification)
        Logger.debug("Found text response: #{String.slice(content, 0, 100)}...")
        {:ok, {:text_response, content}}

      _ ->
        # No tool calls and no text
        Logger.warning("No tool calls or text content in response")
        {:ok, []}
    end
  end

  defp parse_openai_response(response) do
    Logger.error("Unexpected OpenAI API response format: #{inspect(response)}")
    {:error, :invalid_response_format}
  end

  # Executes a create_shape tool call to create a basic shape on the canvas.
  #
  # Supported shape types: rectangle, circle, triangle, etc.
  # Extracts width, height, color from input and creates object at specified x,y position.
  # Uses current_color as default if no color is specified in the input.
  defp execute_tool_call(%{name: "create_shape", input: input}, canvas_id, current_color) do
    # Check for both "fill" (from tool definition) and "color" (for backwards compatibility)
    ai_color = Map.get(input, "fill") || Map.get(input, "color")
    # Convert color names to hex if needed
    final_color = normalize_color(ai_color || current_color)

    Logger.info("create_shape: current_color=#{current_color}, AI provided color=#{inspect(ai_color)}, final_color=#{final_color}")

    data = %{
      width: input["width"],
      height: input["height"],
      color: final_color
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
  # Uses current_color as default if no color is specified in the input.
  defp execute_tool_call(%{name: "create_text", input: input}, canvas_id, current_color) do
    ai_color = Map.get(input, "color")
    # Convert color names to hex if needed
    final_color = normalize_color(ai_color || current_color)

    Logger.info("create_text: current_color=#{current_color}, AI provided color=#{inspect(ai_color)}, final_color=#{final_color}")

    data = %{
      text: input["text"],
      font_size: Map.get(input, "font_size", 16),
      color: final_color
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
  defp execute_tool_call(%{name: "move_shape", input: input}, canvas_id, _current_color) do
    # Get object_id from either shape_id or object_id (for backwards compatibility)
    object_id = input["shape_id"] || input["object_id"]

    attrs = %{
      position: %{
        x: input["x"],
        y: input["y"]
      }
    }

    result = Canvases.update_object(object_id, attrs)

    # Broadcast update to all connected clients for real-time sync
    case result do
      {:ok, updated_object} ->
        Phoenix.PubSub.broadcast(
          CollabCanvas.PubSub,
          "canvas:#{canvas_id}",
          {:object_updated, updated_object}
        )
      _ -> :ok
    end

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
  defp execute_tool_call(%{name: "resize_shape", input: input}, canvas_id, _current_color) do
    # Get object_id from either shape_id or object_id (for backwards compatibility)
    object_id = input["shape_id"] || input["object_id"]

    # First get the existing object to merge data
    case Canvases.get_object(object_id) do
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

        result = Canvases.update_object(object_id, attrs)

        # Broadcast update to all connected clients for real-time sync
        case result do
          {:ok, updated_object} ->
            Phoenix.PubSub.broadcast(
              CollabCanvas.PubSub,
              "canvas:#{canvas_id}",
              {:object_updated, updated_object}
            )
          _ -> :ok
        end

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
  defp execute_tool_call(%{name: "delete_object", input: input}, _canvas_id, _current_color) do
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
  defp execute_tool_call(%{name: "list_objects", input: _input}, canvas_id, _current_color) do
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
  defp execute_tool_call(%{name: "create_component", input: input}, canvas_id, _current_color) do
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
  defp execute_tool_call(%{name: "group_objects", input: input}, _canvas_id, _current_color) do
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
  defp execute_tool_call(%{name: "resize_object", input: input}, canvas_id, _current_color) do
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

        # Broadcast update to all connected clients for real-time sync
        case result do
          {:ok, updated_object} ->
            Phoenix.PubSub.broadcast(
              CollabCanvas.PubSub,
              "canvas:#{canvas_id}",
              {:object_updated, updated_object}
            )
          _ -> :ok
        end

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
  defp execute_tool_call(%{name: "rotate_object", input: input}, canvas_id, _current_color) do
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

        # Broadcast update to all connected clients for real-time sync
        case result do
          {:ok, updated_object} ->
            Phoenix.PubSub.broadcast(
              CollabCanvas.PubSub,
              "canvas:#{canvas_id}",
              {:object_updated, updated_object}
            )
          _ -> :ok
        end

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
  defp execute_tool_call(%{name: "change_style", input: input}, canvas_id, _current_color) do
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

        # Broadcast update to all connected clients for real-time sync
        case result do
          {:ok, updated_object} ->
            Phoenix.PubSub.broadcast(
              CollabCanvas.PubSub,
              "canvas:#{canvas_id}",
              {:object_updated, updated_object}
            )
          _ -> :ok
        end

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
  defp execute_tool_call(%{name: "update_text", input: input}, canvas_id, _current_color) do
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

          # Broadcast update to all connected clients for real-time sync
          case result do
            {:ok, updated_object} ->
              Phoenix.PubSub.broadcast(
                CollabCanvas.PubSub,
                "canvas:#{canvas_id}",
                {:object_updated, updated_object}
              )
            _ -> :ok
          end

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
  defp execute_tool_call(%{name: "move_object", input: input}, canvas_id, _current_color) do
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

        # Broadcast update to all connected clients for real-time sync
        case result do
          {:ok, updated_object} ->
            Phoenix.PubSub.broadcast(
              CollabCanvas.PubSub,
              "canvas:#{canvas_id}",
              {:object_updated, updated_object}
            )
          _ -> :ok
        end

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
  defp execute_tool_call(%{name: "arrange_objects", input: input}, canvas_id, _current_color) do
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

      # Broadcast updates to all connected clients for real-time sync
      Enum.each(results, fn
        {:ok, updated_object} ->
          Phoenix.PubSub.broadcast(
            CollabCanvas.PubSub,
            "canvas:#{canvas_id}",
            {:object_updated, updated_object}
          )
        _ -> :ok
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

  # Executes a show_object_labels tool call to toggle display of visual labels on canvas objects.
  #
  # Returns a special result type that the frontend can handle to show/hide labels.
  defp execute_tool_call(%{name: "show_object_labels", input: input}, _canvas_id, _current_color) do
    show = Map.get(input, "show", true)

    %{
      tool: "show_object_labels",
      input: input,
      result: {:ok, {:toggle_labels, show}}
    }
  end

  # Executes an arrange_objects_with_pattern tool call for flexible programmatic layouts.
  #
  # Supports custom patterns like line, diagonal, wave, arc for arrangements not covered by standard layouts.
  defp execute_tool_call(%{name: "arrange_objects_with_pattern", input: input}, canvas_id, _current_color) do
    object_ids = input["object_ids"]
    pattern = input["pattern"]

    start_time = System.monotonic_time(:millisecond)

    # Fetch all objects to arrange
    objects = Enum.map(object_ids, fn id ->
      case Canvases.get_object(id) do
        nil -> nil
        obj ->
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
        tool: "arrange_objects_with_pattern",
        input: input,
        result: {:error, :no_objects_found}
      }
    else
      # Apply pattern-based layout
      updates = Layout.pattern_layout(objects, pattern, input)

      # Batch update all objects
      results = Enum.map(updates, fn update ->
        attrs = %{position: update.position}
        Canvases.update_object(update.id, attrs)
      end)

      # Broadcast updates to all connected clients for real-time sync
      Enum.each(results, fn
        {:ok, updated_object} ->
          Phoenix.PubSub.broadcast(
            CollabCanvas.PubSub,
            "canvas:#{canvas_id}",
            {:object_updated, updated_object}
          )
        _ -> :ok
      end)

      failed = Enum.any?(results, fn
        {:error, _} -> true
        _ -> false
      end)

      end_time = System.monotonic_time(:millisecond)
      duration_ms = end_time - start_time

      Logger.info("Pattern layout operation completed: #{pattern} for #{length(results)} objects in #{duration_ms}ms")

      if failed do
        %{
          tool: "arrange_objects_with_pattern",
          input: input,
          result: {:error, :partial_update_failure}
        }
      else
        %{
          tool: "arrange_objects_with_pattern",
          input: input,
          result: {:ok, %{updated: length(results), pattern: pattern, duration_ms: duration_ms}}
        }
      end
    end
  end

  # Executes a define_object_relationships tool call for constraint-based positioning.
  #
  # Uses declarative constraints (above, below, left_of, etc.) to calculate object positions.
  defp execute_tool_call(%{name: "define_object_relationships", input: input}, canvas_id, _current_color) do
    relationships = input["relationships"]
    apply_constraints = Map.get(input, "apply_constraints", true)

    start_time = System.monotonic_time(:millisecond)

    # Collect all unique object IDs from relationships
    object_ids = relationships
    |> Enum.flat_map(fn rel ->
      [rel["subject_id"], rel["reference_id"], Map.get(rel, "reference_id_2")]
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()

    # Fetch all objects involved
    objects = Enum.map(object_ids, fn id ->
      case Canvases.get_object(id) do
        nil -> nil
        obj ->
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
        tool: "define_object_relationships",
        input: input,
        result: {:error, :no_objects_found}
      }
    else
      # Apply relationship-based positioning
      updates = Layout.apply_relationships(objects, relationships, apply_constraints)

      # Batch update all objects
      results = Enum.map(updates, fn update ->
        attrs = %{position: update.position}
        Canvases.update_object(update.id, attrs)
      end)

      # Broadcast updates to all connected clients for real-time sync
      Enum.each(results, fn
        {:ok, updated_object} ->
          Phoenix.PubSub.broadcast(
            CollabCanvas.PubSub,
            "canvas:#{canvas_id}",
            {:object_updated, updated_object}
          )
        _ -> :ok
      end)

      failed = Enum.any?(results, fn
        {:error, _} -> true
        _ -> false
      end)

      end_time = System.monotonic_time(:millisecond)
      duration_ms = end_time - start_time

      Logger.info("Relationship layout completed: #{length(relationships)} constraints for #{length(results)} objects in #{duration_ms}ms")

      if failed do
        %{
          tool: "define_object_relationships",
          input: input,
          result: {:error, :partial_update_failure}
        }
      else
        %{
          tool: "define_object_relationships",
          input: input,
          result: {:ok, %{updated: length(results), relationships: length(relationships), duration_ms: duration_ms}}
        }
      end
    end
  end

  # Fallback handler for unknown tool calls.
  #
  # Logs a warning and returns an error result for any unrecognized tool.
  defp execute_tool_call(tool_call, _canvas_id, _current_color) do
    Logger.warning("Unknown tool call: #{inspect(tool_call)}")

    %{
      tool: "unknown",
      input: tool_call,
      result: {:error, :unknown_tool}
    }
  end

  # Normalizes color input from AI - converts color names to hex format.
  #
  # Accepts both hex format (e.g., "#FF0000" or "FF0000") and common color names
  # (e.g., "red", "green", "blue"). Returns a hex color string with "#" prefix.
  #
  # ## Parameters
  #   * `color` - Color string (hex format or color name)
  #
  # ## Returns
  #   * Hex color string with "#" prefix (e.g., "#FF0000")
  #
  # ## Examples
  #
  #     iex> normalize_color("#FF0000")
  #     "#FF0000"
  #
  #     iex> normalize_color("red")
  #     "#FF0000"
  #
  #     iex> normalize_color("green")
  #     "#00FF00"
  defp normalize_color(color) when is_binary(color) do
    # If already in hex format, return as-is (with # prefix)
    cond do
      String.starts_with?(color, "#") ->
        String.upcase(color)

      String.match?(color, ~r/^[0-9A-Fa-f]{6}$/) ->
        "#" <> String.upcase(color)

      true ->
        # Convert color name to hex
        color_name = String.downcase(String.trim(color))
        color_name_to_hex(color_name)
    end
  end

  defp normalize_color(nil), do: "#000000"
  defp normalize_color(_), do: "#000000"

  # Converts common color names to hex format.
  #
  # Provides a comprehensive mapping of color names to their hex representations.
  # Returns black (#000000) for unknown color names.
  defp color_name_to_hex(name) do
    case name do
      # Primary colors
      "red" -> "#FF0000"
      "green" -> "#00FF00"
      "blue" -> "#0000FF"

      # Secondary colors
      "yellow" -> "#FFFF00"
      "cyan" -> "#00FFFF"
      "magenta" -> "#FF00FF"

      # Common colors
      "orange" -> "#FFA500"
      "purple" -> "#800080"
      "pink" -> "#FFC0CB"
      "brown" -> "#A52A2A"
      "gray" -> "#808080"
      "grey" -> "#808080"

      # Light/Dark variants
      "light gray" -> "#D3D3D3"
      "light grey" -> "#D3D3D3"
      "dark gray" -> "#A9A9A9"
      "dark grey" -> "#A9A9A9"
      "light blue" -> "#ADD8E6"
      "dark blue" -> "#00008B"
      "light green" -> "#90EE90"
      "dark green" -> "#006400"
      "light red" -> "#FF6B6B"
      "dark red" -> "#8B0000"

      # Extended colors
      "lime" -> "#00FF00"
      "navy" -> "#000080"
      "teal" -> "#008080"
      "maroon" -> "#800000"
      "olive" -> "#808000"
      "aqua" -> "#00FFFF"
      "fuchsia" -> "#FF00FF"
      "silver" -> "#C0C0C0"
      "gold" -> "#FFD700"
      "indigo" -> "#4B0082"
      "violet" -> "#EE82EE"
      "coral" -> "#FF7F50"
      "salmon" -> "#FA8072"
      "turquoise" -> "#40E0D0"
      "khaki" -> "#F0E68C"
      "plum" -> "#DDA0DD"
      "crimson" -> "#DC143C"

      # Grayscale
      "black" -> "#000000"
      "white" -> "#FFFFFF"

      # Unknown color - default to black
      _ ->
        Logger.warning("Unknown color name: #{name}, defaulting to black")
        "#000000"
    end
  end
end
