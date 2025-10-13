defmodule CollabCanvas.AI.Agent do
  @moduledoc """
  AI Agent for executing natural language commands on canvas.
  Integrates with Claude API to process user commands and execute canvas operations.
  """

  require Logger
  alias CollabCanvas.Canvases
  alias CollabCanvas.AI.Tools

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
          create_login_form(canvas_id, x, y, width, height, theme, content)

        "navbar" ->
          create_navbar(canvas_id, x, y, width, height, theme, content)

        "card" ->
          create_card(canvas_id, x, y, width, height, theme, content)

        "button" ->
          create_button_group(canvas_id, x, y, width, height, theme, content)

        "sidebar" ->
          create_sidebar(canvas_id, x, y, width, height, theme, content)

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

  # Complex Component Creation Functions

  defp create_login_form(canvas_id, x, y, width, height, theme, content) do
    colors = get_theme_colors(theme)
    title = Map.get(content, "title", "Login")

    created_objects = []

    # Create background container
    {:ok, bg} = create_shape_for_component(
      canvas_id,
      "rectangle",
      x,
      y,
      width,
      height,
      colors.bg,
      colors.border,
      2
    )
    created_objects = [bg.id | created_objects]

    # Create title text
    {:ok, title_text} = create_text_for_component(
      canvas_id,
      title,
      x + width / 2,
      y + 20,
      24,
      "Arial",
      colors.text_primary,
      "center"
    )
    created_objects = [title_text.id | created_objects]

    # Username label
    {:ok, username_label} = create_text_for_component(
      canvas_id,
      "Username:",
      x + 20,
      y + 60,
      14,
      "Arial",
      colors.text_secondary,
      "left"
    )
    created_objects = [username_label.id | created_objects]

    # Username input box
    {:ok, username_input} = create_shape_for_component(
      canvas_id,
      "rectangle",
      x + 20,
      y + 80,
      width - 40,
      40,
      colors.input_bg,
      colors.input_border,
      1
    )
    created_objects = [username_input.id | created_objects]

    # Password label
    {:ok, password_label} = create_text_for_component(
      canvas_id,
      "Password:",
      x + 20,
      y + 130,
      14,
      "Arial",
      colors.text_secondary,
      "left"
    )
    created_objects = [password_label.id | created_objects]

    # Password input box
    {:ok, password_input} = create_shape_for_component(
      canvas_id,
      "rectangle",
      x + 20,
      y + 150,
      width - 40,
      40,
      colors.input_bg,
      colors.input_border,
      1
    )
    created_objects = [password_input.id | created_objects]

    # Submit button
    {:ok, submit_btn} = create_shape_for_component(
      canvas_id,
      "rectangle",
      x + 20,
      y + 210,
      width - 40,
      45,
      colors.button_bg,
      colors.button_border,
      0
    )
    created_objects = [submit_btn.id | created_objects]

    # Button text
    {:ok, btn_text} = create_text_for_component(
      canvas_id,
      "Sign In",
      x + width / 2,
      y + 225,
      16,
      "Arial",
      colors.button_text,
      "center"
    )
    created_objects = [btn_text.id | created_objects]

    {:ok, %{component_type: "login_form", object_ids: Enum.reverse(created_objects)}}
  end

  defp create_navbar(canvas_id, x, y, width, height, theme, content) do
    colors = get_theme_colors(theme)
    items = Map.get(content, "items", ["Home", "About", "Services", "Contact"])
    title = Map.get(content, "title", "Brand")

    created_objects = []

    # Create navbar background
    {:ok, bg} = create_shape_for_component(
      canvas_id,
      "rectangle",
      x,
      y,
      width,
      height,
      colors.navbar_bg,
      colors.border,
      0
    )
    created_objects = [bg.id | created_objects]

    # Create logo/brand text
    {:ok, logo} = create_text_for_component(
      canvas_id,
      title,
      x + 20,
      y + height / 2 - 10,
      20,
      "Arial",
      colors.text_primary,
      "left"
    )
    created_objects = [logo.id | created_objects]

    # Calculate spacing for menu items
    item_count = length(items)
    available_width = width - 200
    item_spacing = if item_count > 1, do: available_width / (item_count - 1), else: 0

    # Create menu items
    created_objects = items
    |> Enum.with_index()
    |> Enum.reduce(created_objects, fn {item, index}, acc ->
      item_x = x + 200 + index * item_spacing
      {:ok, menu_item} = create_text_for_component(
        canvas_id,
        item,
        item_x,
        y + height / 2 - 8,
        16,
        "Arial",
        colors.text_secondary,
        "center"
      )
      [menu_item.id | acc]
    end)

    {:ok, %{component_type: "navbar", object_ids: Enum.reverse(created_objects)}}
  end

  defp create_card(canvas_id, x, y, width, height, theme, content) do
    colors = get_theme_colors(theme)
    title = Map.get(content, "title", "Card Title")
    subtitle = Map.get(content, "subtitle", "Card description goes here")

    created_objects = []

    # Create shadow effect (slightly offset darker rectangle)
    {:ok, shadow} = create_shape_for_component(
      canvas_id,
      "rectangle",
      x + 4,
      y + 4,
      width,
      height,
      colors.shadow,
      colors.shadow,
      0
    )
    created_objects = [shadow.id | created_objects]

    # Create card background
    {:ok, bg} = create_shape_for_component(
      canvas_id,
      "rectangle",
      x,
      y,
      width,
      height,
      colors.card_bg,
      colors.border,
      1
    )
    created_objects = [bg.id | created_objects]

    # Create header section
    {:ok, header} = create_shape_for_component(
      canvas_id,
      "rectangle",
      x,
      y,
      width,
      60,
      colors.card_header_bg,
      colors.border,
      0
    )
    created_objects = [header.id | created_objects]

    # Create title text
    {:ok, title_text} = create_text_for_component(
      canvas_id,
      title,
      x + 20,
      y + 20,
      18,
      "Arial",
      colors.text_primary,
      "left"
    )
    created_objects = [title_text.id | created_objects]

    # Create content area text
    {:ok, content_text} = create_text_for_component(
      canvas_id,
      subtitle,
      x + 20,
      y + 80,
      14,
      "Arial",
      colors.text_secondary,
      "left"
    )
    created_objects = [content_text.id | created_objects]

    # Create footer section
    footer_y = y + height - 50
    {:ok, footer} = create_shape_for_component(
      canvas_id,
      "rectangle",
      x,
      footer_y,
      width,
      50,
      colors.card_footer_bg,
      colors.border,
      0
    )
    created_objects = [footer.id | created_objects]

    {:ok, %{component_type: "card", object_ids: Enum.reverse(created_objects)}}
  end

  defp create_button_group(canvas_id, x, y, width, height, theme, content) do
    colors = get_theme_colors(theme)
    items = Map.get(content, "items", ["Button 1", "Button 2", "Button 3"])

    created_objects = []
    button_width = (width - 20 * (length(items) - 1)) / length(items)

    created_objects = items
    |> Enum.with_index()
    |> Enum.reduce(created_objects, fn {label, index}, acc ->
      btn_x = x + index * (button_width + 20)

      # Button background
      {:ok, btn} = create_shape_for_component(
        canvas_id,
        "rectangle",
        btn_x,
        y,
        button_width,
        height,
        colors.button_bg,
        colors.button_border,
        1
      )
      acc = [btn.id | acc]

      # Button text
      {:ok, btn_text} = create_text_for_component(
        canvas_id,
        label,
        btn_x + button_width / 2,
        y + height / 2 - 8,
        14,
        "Arial",
        colors.button_text,
        "center"
      )
      [btn_text.id | acc]
    end)

    {:ok, %{component_type: "button_group", object_ids: Enum.reverse(created_objects)}}
  end

  defp create_sidebar(canvas_id, x, y, width, height, theme, content) do
    colors = get_theme_colors(theme)
    items = Map.get(content, "items", ["Dashboard", "Profile", "Settings", "Logout"])
    title = Map.get(content, "title", "Menu")

    created_objects = []

    # Create sidebar background
    {:ok, bg} = create_shape_for_component(
      canvas_id,
      "rectangle",
      x,
      y,
      width,
      height,
      colors.sidebar_bg,
      colors.border,
      1
    )
    created_objects = [bg.id | created_objects]

    # Create title
    {:ok, title_text} = create_text_for_component(
      canvas_id,
      title,
      x + 20,
      y + 20,
      20,
      "Arial",
      colors.text_primary,
      "left"
    )
    created_objects = [title_text.id | created_objects]

    # Create menu items
    created_objects = items
    |> Enum.with_index()
    |> Enum.reduce(created_objects, fn {item, index}, acc ->
      item_y = y + 60 + index * 50

      # Menu item background (hover state)
      {:ok, item_bg} = create_shape_for_component(
        canvas_id,
        "rectangle",
        x + 10,
        item_y,
        width - 20,
        40,
        colors.sidebar_item_bg,
        colors.sidebar_item_border,
        1
      )
      acc = [item_bg.id | acc]

      # Menu item text
      {:ok, item_text} = create_text_for_component(
        canvas_id,
        item,
        x + 25,
        item_y + 12,
        14,
        "Arial",
        colors.text_secondary,
        "left"
      )
      [item_text.id | acc]
    end)

    {:ok, %{component_type: "sidebar", object_ids: Enum.reverse(created_objects)}}
  end

  # Helper functions for component creation

  defp create_shape_for_component(canvas_id, type, x, y, width, height, fill, stroke, stroke_width) do
    data = %{
      width: width,
      height: height,
      fill: fill,
      stroke: stroke,
      stroke_width: stroke_width
    }

    attrs = %{
      position: %{x: x, y: y},
      data: Jason.encode!(data)
    }

    Canvases.create_object(canvas_id, type, attrs)
  end

  defp create_text_for_component(canvas_id, text, x, y, font_size, font_family, color, align) do
    data = %{
      text: text,
      font_size: font_size,
      font_family: font_family,
      color: color,
      align: align
    }

    attrs = %{
      position: %{x: x, y: y},
      data: Jason.encode!(data)
    }

    Canvases.create_object(canvas_id, "text", attrs)
  end

  defp get_theme_colors(theme) do
    case theme do
      "dark" ->
        %{
          bg: "#1f2937",
          border: "#374151",
          text_primary: "#f9fafb",
          text_secondary: "#d1d5db",
          input_bg: "#374151",
          input_border: "#4b5563",
          button_bg: "#3b82f6",
          button_border: "#2563eb",
          button_text: "#ffffff",
          navbar_bg: "#111827",
          card_bg: "#1f2937",
          card_header_bg: "#374151",
          card_footer_bg: "#374151",
          shadow: "#00000066",
          sidebar_bg: "#1f2937",
          sidebar_item_bg: "#374151",
          sidebar_item_border: "#4b5563"
        }

      "blue" ->
        %{
          bg: "#eff6ff",
          border: "#93c5fd",
          text_primary: "#1e3a8a",
          text_secondary: "#3b82f6",
          input_bg: "#ffffff",
          input_border: "#93c5fd",
          button_bg: "#3b82f6",
          button_border: "#2563eb",
          button_text: "#ffffff",
          navbar_bg: "#3b82f6",
          card_bg: "#ffffff",
          card_header_bg: "#dbeafe",
          card_footer_bg: "#f0f9ff",
          shadow: "#3b82f633",
          sidebar_bg: "#dbeafe",
          sidebar_item_bg: "#bfdbfe",
          sidebar_item_border: "#93c5fd"
        }

      "green" ->
        %{
          bg: "#f0fdf4",
          border: "#86efac",
          text_primary: "#14532d",
          text_secondary: "#16a34a",
          input_bg: "#ffffff",
          input_border: "#86efac",
          button_bg: "#22c55e",
          button_border: "#16a34a",
          button_text: "#ffffff",
          navbar_bg: "#22c55e",
          card_bg: "#ffffff",
          card_header_bg: "#dcfce7",
          card_footer_bg: "#f0fdf4",
          shadow: "#22c55e33",
          sidebar_bg: "#dcfce7",
          sidebar_item_bg: "#bbf7d0",
          sidebar_item_border: "#86efac"
        }

      _ -> # "light" or default
        %{
          bg: "#ffffff",
          border: "#e5e7eb",
          text_primary: "#111827",
          text_secondary: "#6b7280",
          input_bg: "#ffffff",
          input_border: "#d1d5db",
          button_bg: "#3b82f6",
          button_border: "#2563eb",
          button_text: "#ffffff",
          navbar_bg: "#f9fafb",
          card_bg: "#ffffff",
          card_header_bg: "#f9fafb",
          card_footer_bg: "#f9fafb",
          shadow: "#00000026",
          sidebar_bg: "#f9fafb",
          sidebar_item_bg: "#ffffff",
          sidebar_item_border: "#e5e7eb"
        }
    end
  end
end
