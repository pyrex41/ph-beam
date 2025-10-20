defmodule CollabCanvas.AI.CanvasStats do
  @moduledoc """
  Calculates statistical metadata about canvas objects for efficient AI-based filtering.

  Instead of sending thousands of objects to the AI, we send:
  - Size statistics (min, max, median, deciles)
  - Unique colors present
  - Shape types present
  - Total object count

  The AI uses these statistics to determine intelligent filter criteria,
  then we apply the filter server-side.
  """

  require Logger

  @doc """
  Calculate statistical metadata for all objects on a canvas.

  Returns:
  ```elixir
  %{
    size_stats: %{
      min: 20,
      max: 800,
      median: 200,
      p10: 50, p20: 80, p30: 100, p40: 150,
      p50: 200, p60: 250, p70: 350, p80: 450, p90: 500
    },
    colors: ["#FF0000", "#0000FF", "#00FF00"],
    shape_types: ["circle", "rectangle", "text"],
    total_objects: 156
  }
  ```
  """
  def calculate_stats(objects) when is_list(objects) do
    if Enum.empty?(objects) do
      %{
        size_stats: %{
          min: 0,
          max: 0,
          median: 0,
          p10: 0,
          p20: 0,
          p30: 0,
          p40: 0,
          p50: 0,
          p60: 0,
          p70: 0,
          p80: 0,
          p90: 0
        },
        colors: [],
        shape_types: [],
        total_objects: 0
      }
    else
      %{
        size_stats: calculate_size_stats(objects),
        colors: extract_unique_colors(objects),
        shape_types: extract_shape_types(objects),
        total_objects: length(objects)
      }
    end
  end

  @doc """
  Apply filter criteria to a list of objects.

  Filter criteria:
  - `color`: Exact hex color match (e.g., "#FF0000")
  - `size_min`: Minimum size (width or height) in pixels
  - `size_max`: Maximum size (width or height) in pixels
  - `shape_type`: "circle", "rectangle", "square", or "text"
  - `position`: "top", "bottom", "left", "right", "center", etc. (requires viewport)

  Returns list of object IDs that match all criteria.
  """
  def apply_filter(objects, criteria, viewport \\ nil) do
    objects
    |> Enum.filter(&matches_criteria?(&1, criteria, viewport))
    |> Enum.map(& &1.id)
  end

  # Private functions

  defp calculate_size_stats(objects) do
    # Extract sizes (max of width or height for each object)
    sizes =
      objects
      |> Enum.map(&extract_size/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.sort()

    if Enum.empty?(sizes) do
      %{
        min: 0,
        max: 0,
        median: 0,
        p10: 0,
        p20: 0,
        p30: 0,
        p40: 0,
        p50: 0,
        p60: 0,
        p70: 0,
        p80: 0,
        p90: 0
      }
    else
      %{
        min: List.first(sizes),
        max: List.last(sizes),
        median: percentile(sizes, 50),
        p10: percentile(sizes, 10),
        p20: percentile(sizes, 20),
        p30: percentile(sizes, 30),
        p40: percentile(sizes, 40),
        p50: percentile(sizes, 50),
        p60: percentile(sizes, 60),
        p70: percentile(sizes, 70),
        p80: percentile(sizes, 80),
        p90: percentile(sizes, 90)
      }
    end
  end

  defp extract_size(object) do
    data = decode_data(object.data)

    cond do
      is_map(data) and Map.has_key?(data, "width") and Map.has_key?(data, "height") ->
        max(data["width"], data["height"])

      is_map(data) and Map.has_key?(data, "width") ->
        data["width"]

      is_map(data) and Map.has_key?(data, "height") ->
        data["height"]

      true ->
        nil
    end
  end

  defp extract_unique_colors(objects) do
    objects
    |> Enum.map(fn object ->
      data = decode_data(object.data)
      # Use 'fill' field (preferred), fall back to 'color' for backwards compatibility
      Map.get(data, "fill") || Map.get(data, "color")
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp extract_shape_types(objects) do
    objects
    |> Enum.map(& &1.type)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp percentile(sorted_list, p) when p >= 0 and p <= 100 do
    n = length(sorted_list)
    index = trunc(p / 100 * (n - 1))
    Enum.at(sorted_list, index)
  end

  defp decode_data(data) when is_binary(data) do
    case Jason.decode(data) do
      {:ok, decoded} -> decoded
      _ -> %{}
    end
  end

  defp decode_data(data) when is_map(data), do: data
  defp decode_data(_), do: %{}

  defp matches_criteria?(object, criteria, viewport) do
    matches_color?(object, criteria) and
      matches_size?(object, criteria) and
      matches_shape_type?(object, criteria) and
      matches_position?(object, criteria, viewport)
  end

  defp matches_color?(object, %{"color" => color}) when not is_nil(color) do
    data = decode_data(object.data)
    # Use 'fill' field (preferred), fall back to 'color' for backwards compatibility
    object_color = Map.get(data, "fill") || Map.get(data, "color")
    object_color == color
  end

  defp matches_color?(_object, _criteria), do: true

  defp matches_size?(object, criteria) do
    size = extract_size(object)

    if is_nil(size) do
      false
    else
      matches_min = is_nil(criteria["size_min"]) or size >= criteria["size_min"]
      matches_max = is_nil(criteria["size_max"]) or size <= criteria["size_max"]
      matches_min and matches_max
    end
  end

  defp matches_shape_type?(object, %{"shape_type" => "square"}) do
    # Squares are rectangles where |width - height| <= 10
    if object.type == "rectangle" do
      data = decode_data(object.data)
      width = Map.get(data, "width")
      height = Map.get(data, "height")

      if width && height do
        abs(width - height) <= 10
      else
        false
      end
    else
      false
    end
  end

  defp matches_shape_type?(object, %{"shape_type" => shape_type})
       when not is_nil(shape_type) do
    object.type == shape_type
  end

  defp matches_shape_type?(_object, _criteria), do: true

  defp matches_position?(object, %{"position" => position}, viewport)
       when not is_nil(position) and not is_nil(viewport) do
    center_x = viewport["x"] + viewport["width"] / 2
    center_y = viewport["y"] + viewport["height"] / 2

    obj_x = object.position["x"] || object.position[:x]
    obj_y = object.position["y"] || object.position[:y]

    case position do
      "top" -> obj_y < center_y
      "bottom" -> obj_y > center_y
      "left" -> obj_x < center_x
      "right" -> obj_x > center_x
      "center" -> near_center?(obj_x, obj_y, center_x, center_y, viewport)
      "top-left" -> obj_y < center_y and obj_x < center_x
      "top-right" -> obj_y < center_y and obj_x > center_x
      "bottom-left" -> obj_y > center_y and obj_x < center_x
      "bottom-right" -> obj_y > center_y and obj_x > center_x
      _ -> true
    end
  end

  defp matches_position?(_object, _criteria, _viewport), do: true

  defp near_center?(obj_x, obj_y, center_x, center_y, viewport) do
    # Within 20% of canvas dimensions from center
    threshold_x = viewport["width"] * 0.2
    threshold_y = viewport["height"] * 0.2

    abs(obj_x - center_x) <= threshold_x and abs(obj_y - center_y) <= threshold_y
  end
end
