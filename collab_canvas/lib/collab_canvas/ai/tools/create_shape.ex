defmodule CollabCanvas.AI.Tools.CreateShape do
  @moduledoc """
  AI tool for creating basic shapes (rectangles and circles) on the canvas.

  This tool allows the AI to create shapes with customizable dimensions, colors,
  and stroke styling. It supports both explicit color values and uses the current
  color picker selection as a default.

  ## Examples

      # Create a red rectangle
      execute(%{
        "type" => "rectangle",
        "x" => 100,
        "y" => 100,
        "width" => 150,
        "height" => 100,
        "fill" => "#FF0000"
      }, %{canvas_id: 1, current_color: "#000000"})

      # Create a circle using current color
      execute(%{
        "type" => "circle",
        "x" => 200,
        "y" => 200,
        "width" => 80
      }, %{canvas_id: 1, current_color: "#00FF00"})
  """

  @behaviour CollabCanvas.AI.Tool

  alias CollabCanvas.Canvases

  @impl true
  def definition do
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
    }
  end

  @impl true
  def execute(params, %{canvas_id: canvas_id, current_color: current_color}) do
    # Check for both "fill" (from tool definition) and "color" (for backwards compatibility)
    ai_color = Map.get(params, "fill") || Map.get(params, "color")
    # Convert color names to hex if needed
    final_color = normalize_color(ai_color || current_color)

    data = %{
      width: params["width"],
      height: params["height"],
      color: final_color
    }

    attrs = %{
      position: %{
        x: params["x"],
        y: params["y"]
      },
      data: Jason.encode!(data)
    }

    case Canvases.create_object(canvas_id, params["type"], attrs) do
      {:ok, object} = success ->
        # Broadcast to all connected clients
        Phoenix.PubSub.broadcast(
          CollabCanvas.PubSub,
          "canvas:#{canvas_id}",
          {:object_created, object}
        )

        success

      error ->
        error
    end
  end

  # Private helper functions

  # Normalizes color input from AI - converts color names to hex format.
  defp normalize_color(color) when is_binary(color) do
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

  # Converts common color names to hex format
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
      # Grayscale
      "black" -> "#000000"
      "white" -> "#FFFFFF"
      # Unknown color - default to black
      _ -> "#000000"
    end
  end
end
