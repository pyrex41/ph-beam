defmodule CollabCanvas.AI.Layout do
  @moduledoc """
  AI-powered layout algorithms for arranging and aligning canvas objects.

  This module provides intelligent layout functions that can be triggered by AI commands
  to organize selected objects on the canvas. All algorithms are designed to meet
  performance requirements of <500ms for up to 50 objects.

  ## Available Layout Functions

  - `distribute_horizontally/2` - Distribute objects evenly along the X-axis
  - `distribute_vertically/2` - Distribute objects evenly along the Y-axis
  - `arrange_grid/3` - Arrange objects in a grid pattern
  - `align_objects/2` - Align objects to a common edge or center
  - `circular_layout/2` - Arrange objects in a circular pattern

  ## Layout Precision

  All layout calculations maintain precision within ±1px to ensure pixel-perfect
  alignment and spacing.

  ## Input Format

  Objects should be provided as a list of maps with the following structure:

      %{
        id: "object-uuid",
        position: %{x: 100, y: 200},
        data: %{width: 50, height: 50}  # or decoded JSON string
      }

  ## Output Format

  Functions return a list of update maps that can be applied to objects:

      [
        %{id: "object-1-uuid", position: %{x: 100, y: 200}},
        %{id: "object-2-uuid", position: %{x: 150, y: 200}}
      ]
  """

  @doc """
  Distributes objects horizontally with even spacing.

  ## Parameters
    * `objects` - List of object maps with id, position, and data
    * `spacing` - Spacing option:
      - `:even` - Calculate even spacing based on available space (default)
      - number - Use fixed spacing in pixels

  ## Returns
    List of update maps with new positions

  ## Examples

      iex> objects = [
      ...>   %{id: "1", position: %{x: 0, y: 100}, data: %{width: 50, height: 50}},
      ...>   %{id: "2", position: %{x: 100, y: 100}, data: %{width: 50, height: 50}}
      ...> ]
      iex> distribute_horizontally(objects, 20)
      [
        %{id: "1", position: %{x: 0, y: 100}},
        %{id: "2", position: %{x: 70, y: 100}}
      ]
  """
  def distribute_horizontally(objects, spacing \\ :even)

  def distribute_horizontally([], _spacing), do: []

  def distribute_horizontally([single], _spacing),
    do: [%{id: single.id, position: single.position}]

  def distribute_horizontally(objects, spacing) when is_list(objects) do
    # Sort objects by X position
    sorted_objects = Enum.sort_by(objects, &get_position_x/1)

    case spacing do
      :even ->
        distribute_horizontally_even(sorted_objects)

      spacing_value when is_number(spacing_value) ->
        distribute_horizontally_fixed(sorted_objects, spacing_value)

      _ ->
        distribute_horizontally_even(sorted_objects)
    end
  end

  @doc """
  Distributes objects vertically with even spacing.

  ## Parameters
    * `objects` - List of object maps with id, position, and data
    * `spacing` - Spacing option:
      - `:even` - Calculate even spacing based on available space (default)
      - number - Use fixed spacing in pixels

  ## Returns
    List of update maps with new positions

  ## Examples

      iex> objects = [
      ...>   %{id: "1", position: %{x: 100, y: 0}, data: %{width: 50, height: 50}},
      ...>   %{id: "2", position: %{x: 100, y: 100}, data: %{width: 50, height: 50}}
      ...> ]
      iex> distribute_vertically(objects, 20)
      [
        %{id: "1", position: %{x: 100, y: 0}},
        %{id: "2", position: %{x: 100, y: 70}}
      ]
  """
  def distribute_vertically(objects, spacing \\ :even)

  def distribute_vertically([], _spacing), do: []
  def distribute_vertically([single], _spacing), do: [%{id: single.id, position: single.position}]

  def distribute_vertically(objects, spacing) when is_list(objects) do
    # Sort objects by Y position
    sorted_objects = Enum.sort_by(objects, &get_position_y/1)

    case spacing do
      :even ->
        distribute_vertically_even(sorted_objects)

      spacing_value when is_number(spacing_value) ->
        distribute_vertically_fixed(sorted_objects, spacing_value)

      _ ->
        distribute_vertically_even(sorted_objects)
    end
  end

  @doc """
  Arranges objects in a grid layout.

  ## Parameters
    * `objects` - List of object maps with id, position, and data
    * `columns` - Number of columns in the grid
    * `spacing` - Spacing between objects in pixels (default: 20)

  ## Returns
    List of update maps with new positions

  ## Examples

      iex> objects = [
      ...>   %{id: "1", position: %{x: 0, y: 0}, data: %{width: 50, height: 50}},
      ...>   %{id: "2", position: %{x: 100, y: 0}, data: %{width: 50, height: 50}},
      ...>   %{id: "3", position: %{x: 200, y: 0}, data: %{width: 50, height: 50}}
      ...> ]
      iex> arrange_grid(objects, 2, 10)
      [
        %{id: "1", position: %{x: 0, y: 0}},
        %{id: "2", position: %{x: 60, y: 0}},
        %{id: "3", position: %{x: 0, y: 60}}
      ]
  """
  def arrange_grid(objects, columns, spacing \\ 20)

  def arrange_grid([], _columns, _spacing), do: []

  def arrange_grid(objects, columns, spacing)
      when is_list(objects) and is_integer(columns) and columns > 0 do
    # Start from the top-left position of the first object
    first_obj = Enum.at(objects, 0)
    start_x = get_position_x(first_obj) |> round()
    start_y = get_position_y(first_obj) |> round()

    # Calculate max width and height for uniform grid cells
    max_width =
      objects
      |> Enum.map(fn obj -> get_object_width(obj) end)
      |> Enum.max(fn -> 0 end)
      |> round()

    max_height =
      objects
      |> Enum.map(fn obj -> get_object_height(obj) end)
      |> Enum.max(fn -> 0 end)
      |> round()

    # Place objects in grid
    objects
    |> Enum.with_index()
    |> Enum.map(fn {obj, index} ->
      row = div(index, columns)
      col = rem(index, columns)

      new_x = start_x + col * (max_width + spacing)
      new_y = start_y + row * (max_height + spacing)

      %{
        id: obj.id,
        position: %{x: new_x, y: new_y}
      }
    end)
  end

  @doc """
  Aligns objects to a common edge or center.

  ## Parameters
    * `objects` - List of object maps with id, position, and data
    * `alignment` - Alignment type:
      - `"left"` - Align left edges
      - `"right"` - Align right edges
      - `"center"` - Align horizontal centers
      - `"top"` - Align top edges
      - `"bottom"` - Align bottom edges
      - `"middle"` - Align vertical centers

  ## Returns
    List of update maps with new positions

  ## Examples

      iex> objects = [
      ...>   %{id: "1", position: %{x: 0, y: 0}, data: %{width: 50, height: 50}},
      ...>   %{id: "2", position: %{x: 100, y: 50}, data: %{width: 50, height: 50}}
      ...> ]
      iex> align_objects(objects, "left")
      [
        %{id: "1", position: %{x: 0, y: 0}},
        %{id: "2", position: %{x: 0, y: 50}}
      ]
  """
  def align_objects([], _alignment), do: []
  def align_objects([single], _alignment), do: [%{id: single.id, position: single.position}]

  def align_objects(objects, alignment) when is_list(objects) do
    case alignment do
      "left" -> align_left(objects)
      "right" -> align_right(objects)
      "center" -> align_center_horizontal(objects)
      "top" -> align_top(objects)
      "bottom" -> align_bottom(objects)
      "middle" -> align_middle_vertical(objects)
      _ -> Enum.map(objects, fn obj -> %{id: obj.id, position: obj.position} end)
    end
  end

  @doc """
  Arranges objects in a circular pattern.

  ## Parameters
    * `objects` - List of object maps with id, position, and data
    * `radius` - Radius of the circle in pixels

  ## Returns
    List of update maps with new positions

  ## Examples

      iex> objects = [
      ...>   %{id: "1", position: %{x: 0, y: 0}, data: %{width: 50, height: 50}},
      ...>   %{id: "2", position: %{x: 100, y: 0}, data: %{width: 50, height: 50}}
      ...> ]
      iex> circular_layout(objects, 100)
      [
        %{id: "1", position: %{x: 100, y: 0}},
        %{id: "2", position: %{x: 0, y: 100}}
      ]
  """
  def circular_layout([], _radius), do: []
  def circular_layout([single], _radius), do: [%{id: single.id, position: single.position}]

  def circular_layout(objects, radius) when is_list(objects) and is_number(radius) do
    require Logger

    # Calculate center point based on average position
    position_x_values = Enum.map(objects, &get_position_x/1)
    Logger.debug("Position X values: #{inspect(position_x_values)}")

    center_x =
      position_x_values
      |> Enum.sum()
      |> Kernel./(length(objects))
      |> round()

    Logger.debug("Center X: #{inspect(center_x)}, is_number: #{is_number(center_x)}")

    position_y_values = Enum.map(objects, &get_position_y/1)
    Logger.debug("Position Y values: #{inspect(position_y_values)}")

    center_y =
      position_y_values
      |> Enum.sum()
      |> Kernel./(length(objects))
      |> round()

    Logger.debug("Center Y: #{inspect(center_y)}, is_number: #{is_number(center_y)}")

    # Distribute objects evenly around the circle
    count = length(objects)
    angle_step = 2 * :math.pi() / count

    Logger.debug(
      "Radius: #{inspect(radius)}, Count: #{count}, Angle step: #{inspect(angle_step)}"
    )

    objects
    |> Enum.with_index()
    |> Enum.map(fn {obj, index} ->
      angle = index * angle_step

      Logger.debug("Object #{index}: angle=#{inspect(angle)}")

      # Calculate position on circle, accounting for object size to center it
      obj_width = get_object_width(obj)
      obj_height = get_object_height(obj)

      Logger.debug(
        "Object #{index}: width=#{inspect(obj_width)} (is_number: #{is_number(obj_width)}), height=#{inspect(obj_height)} (is_number: #{is_number(obj_height)})"
      )

      cos_value = :math.cos(angle)
      sin_value = :math.sin(angle)

      Logger.debug(
        "Object #{index}: cos(#{angle})=#{inspect(cos_value)}, sin(#{angle})=#{inspect(sin_value)}"
      )

      radius_cos = radius * cos_value

      Logger.debug(
        "Object #{index}: radius * cos = #{inspect(radius_cos)} (is_number: #{is_number(radius_cos)})"
      )

      width_half = obj_width / 2

      Logger.debug(
        "Object #{index}: width / 2 = #{inspect(width_half)} (is_number: #{is_number(width_half)})"
      )

      offset_x = radius_cos - width_half

      Logger.debug(
        "Object #{index}: offset_x = #{inspect(offset_x)} (is_number: #{is_number(offset_x)})"
      )

      new_x = center_x + round(offset_x)
      new_y = center_y + round(radius * sin_value - obj_height / 2)

      Logger.debug("Object #{index}: new_x=#{inspect(new_x)}, new_y=#{inspect(new_y)}")

      %{
        id: obj.id,
        position: %{x: new_x, y: new_y}
      }
    end)
  end

  # Private helper functions

  # Distributes objects horizontally with even spacing between them
  # Auto-aligns objects to the average Y position (center-aligned vertically)
  defp distribute_horizontally_even(sorted_objects) do
    first = List.first(sorted_objects)
    last = List.last(sorted_objects)

    # Calculate total available space
    first_x = get_position_x(first)
    last_x = get_position_x(last)
    last_width = get_object_width(last)

    total_width = last_x + last_width - first_x

    # Calculate total object widths
    total_object_width =
      sorted_objects
      |> Enum.map(&get_object_width/1)
      |> Enum.sum()

    # Calculate even spacing
    total_gap_space = total_width - total_object_width
    gap_count = length(sorted_objects) - 1
    spacing = if gap_count > 0, do: total_gap_space / gap_count, else: 0

    # Calculate average Y position for vertical alignment
    avg_y =
      sorted_objects
      |> Enum.map(&get_position_y/1)
      |> Enum.sum()
      |> Kernel./(length(sorted_objects))
      |> round()

    # Position objects with calculated spacing
    {result, _} =
      Enum.reduce(sorted_objects, {[], first_x}, fn obj, {acc, current_x} ->
        # Use average Y for proper row alignment instead of preserving original Y
        new_position = %{x: round(current_x), y: avg_y}
        update = %{id: obj.id, position: new_position}
        next_x = current_x + get_object_width(obj) + spacing

        {acc ++ [update], next_x}
      end)

    result
  end

  # Distributes objects horizontally with fixed spacing
  # Auto-aligns objects to the average Y position (center-aligned vertically)
  defp distribute_horizontally_fixed(sorted_objects, spacing) do
    first = List.first(sorted_objects)
    start_x = get_position_x(first)

    # Calculate average Y position for vertical alignment
    avg_y =
      sorted_objects
      |> Enum.map(&get_position_y/1)
      |> Enum.sum()
      |> Kernel./(length(sorted_objects))
      |> round()

    {result, _} =
      Enum.reduce(sorted_objects, {[], start_x}, fn obj, {acc, current_x} ->
        # Use average Y for proper row alignment instead of preserving original Y
        new_position = %{x: round(current_x), y: avg_y}
        update = %{id: obj.id, position: new_position}
        next_x = current_x + get_object_width(obj) + spacing

        {acc ++ [update], next_x}
      end)

    result
  end

  # Distributes objects vertically with even spacing between them
  # Auto-aligns objects to the average X position (center-aligned horizontally)
  defp distribute_vertically_even(sorted_objects) do
    first = List.first(sorted_objects)
    last = List.last(sorted_objects)

    # Calculate total available space
    first_y = get_position_y(first)
    last_y = get_position_y(last)
    last_height = get_object_height(last)

    total_height = last_y + last_height - first_y

    # Calculate total object heights
    total_object_height =
      sorted_objects
      |> Enum.map(&get_object_height/1)
      |> Enum.sum()

    # Calculate even spacing
    total_gap_space = total_height - total_object_height
    gap_count = length(sorted_objects) - 1
    spacing = if gap_count > 0, do: total_gap_space / gap_count, else: 0

    # Calculate average X position for horizontal alignment
    avg_x =
      sorted_objects
      |> Enum.map(&get_position_x/1)
      |> Enum.sum()
      |> Kernel./(length(sorted_objects))
      |> round()

    # Position objects with calculated spacing
    {result, _} =
      Enum.reduce(sorted_objects, {[], first_y}, fn obj, {acc, current_y} ->
        # Use average X for proper column alignment instead of preserving original X
        new_position = %{x: avg_x, y: round(current_y)}
        update = %{id: obj.id, position: new_position}
        next_y = current_y + get_object_height(obj) + spacing

        {acc ++ [update], next_y}
      end)

    result
  end

  # Distributes objects vertically with fixed spacing
  # Auto-aligns objects to the average X position (center-aligned horizontally)
  defp distribute_vertically_fixed(sorted_objects, spacing) do
    first = List.first(sorted_objects)
    start_y = get_position_y(first)

    # Calculate average X position for horizontal alignment
    avg_x =
      sorted_objects
      |> Enum.map(&get_position_x/1)
      |> Enum.sum()
      |> Kernel./(length(sorted_objects))
      |> round()

    {result, _} =
      Enum.reduce(sorted_objects, {[], start_y}, fn obj, {acc, current_y} ->
        # Use average X for proper column alignment instead of preserving original X
        new_position = %{x: avg_x, y: round(current_y)}
        update = %{id: obj.id, position: new_position}
        next_y = current_y + get_object_height(obj) + spacing

        {acc ++ [update], next_y}
      end)

    result
  end

  # Alignment helper functions

  defp align_left(objects) do
    min_x = objects |> Enum.map(&get_position_x/1) |> Enum.min() |> round()

    Enum.map(objects, fn obj ->
      %{id: obj.id, position: %{x: min_x, y: get_position_y(obj)}}
    end)
  end

  defp align_right(objects) do
    max_right =
      objects
      |> Enum.map(fn obj -> get_position_x(obj) + get_object_width(obj) end)
      |> Enum.max()
      |> round()

    Enum.map(objects, fn obj ->
      width = get_object_width(obj)
      new_x = max_right - width
      %{id: obj.id, position: %{x: round(new_x), y: get_position_y(obj)}}
    end)
  end

  defp align_center_horizontal(objects) do
    centers =
      Enum.map(objects, fn obj ->
        get_position_x(obj) + get_object_width(obj) / 2
      end)

    avg_center = Enum.sum(centers) / length(centers)

    Enum.map(objects, fn obj ->
      width = get_object_width(obj)
      new_x = avg_center - width / 2
      %{id: obj.id, position: %{x: round(new_x), y: get_position_y(obj)}}
    end)
  end

  defp align_top(objects) do
    min_y = objects |> Enum.map(&get_position_y/1) |> Enum.min() |> round()

    Enum.map(objects, fn obj ->
      %{id: obj.id, position: %{x: get_position_x(obj), y: min_y}}
    end)
  end

  defp align_bottom(objects) do
    max_bottom =
      objects
      |> Enum.map(fn obj -> get_position_y(obj) + get_object_height(obj) end)
      |> Enum.max()
      |> round()

    Enum.map(objects, fn obj ->
      height = get_object_height(obj)
      new_y = max_bottom - height
      %{id: obj.id, position: %{x: get_position_x(obj), y: round(new_y)}}
    end)
  end

  defp align_middle_vertical(objects) do
    centers =
      Enum.map(objects, fn obj ->
        get_position_y(obj) + get_object_height(obj) / 2
      end)

    avg_center = Enum.sum(centers) / length(centers)

    Enum.map(objects, fn obj ->
      height = get_object_height(obj)
      new_y = avg_center - height / 2
      %{id: obj.id, position: %{x: get_position_x(obj), y: round(new_y)}}
    end)
  end

  # Utility functions to safely extract dimensions and positions

  defp get_position_x(obj) do
    x =
      cond do
        is_map(obj.position) and Map.has_key?(obj.position, :x) ->
          obj.position.x

        is_map(obj.position) and Map.has_key?(obj.position, "x") ->
          obj.position["x"]

        true ->
          # Default x position
          0
      end

    # Ensure we always return a number
    case x do
      val when is_number(val) -> val
      _ -> 0
    end
  end

  defp get_position_y(obj) do
    y =
      cond do
        is_map(obj.position) and Map.has_key?(obj.position, :y) ->
          obj.position.y

        is_map(obj.position) and Map.has_key?(obj.position, "y") ->
          obj.position["y"]

        true ->
          # Default y position
          0
      end

    # Ensure we always return a number
    case y do
      val when is_number(val) -> val
      _ -> 0
    end
  end

  defp get_object_width(obj) do
    width =
      cond do
        is_map(obj.data) and Map.has_key?(obj.data, :width) ->
          obj.data.width

        is_map(obj.data) and Map.has_key?(obj.data, "width") ->
          obj.data["width"]

        true ->
          # Default width
          50
      end

    # Ensure we always return a number
    case width do
      w when is_number(w) -> w
      _ -> 50
    end
  end

  defp get_object_height(obj) do
    height =
      cond do
        is_map(obj.data) and Map.has_key?(obj.data, :height) ->
          obj.data.height

        is_map(obj.data) and Map.has_key?(obj.data, "height") ->
          obj.data["height"]

        true ->
          # Default height
          50
      end

    # Ensure we always return a number
    case height do
      h when is_number(h) -> h
      _ -> 50
    end
  end

  @doc """
  Applies flexible programmatic pattern-based layout to objects.

  ## Parameters
    * `objects` - List of object maps with id, position, and data
    * `pattern` - Pattern type: "line", "diagonal", "wave", "arc", "custom"
    * `params` - Map of pattern-specific parameters (spacing, direction, start_x, start_y, etc.)

  ## Returns
    List of update maps with new positions

  ## Examples

      iex> objects = [%{id: "1", position: %{x: 0, y: 0}, data: %{width: 50, height: 50}}]
      iex> params = %{"direction" => "vertical", "spacing" => 50}
      iex> pattern_layout(objects, "line", params)
      [%{id: "1", position: %{x: 0, y: 0}}]
  """
  def pattern_layout([], _pattern, _params), do: []

  def pattern_layout(objects, pattern, params) when is_list(objects) do
    # Sort objects if specified
    sorted_objects =
      case Map.get(params, "sort_by", "none") do
        "x" ->
          Enum.sort_by(objects, &get_position_x/1)

        "y" ->
          Enum.sort_by(objects, &get_position_y/1)

        "size" ->
          Enum.sort_by(objects, fn obj ->
            get_object_width(obj) * get_object_height(obj)
          end)

        "id" ->
          Enum.sort_by(objects, & &1.id)

        _ ->
          objects
      end

    # Apply pattern-specific layout
    case pattern do
      "line" ->
        apply_line_pattern(sorted_objects, params)

      "diagonal" ->
        apply_diagonal_pattern(sorted_objects, params)

      "wave" ->
        apply_wave_pattern(sorted_objects, params)

      "arc" ->
        apply_arc_pattern(sorted_objects, params)

      "custom" ->
        # For custom patterns, just return objects as-is
        # (AI would need to specify exact positions via relationships)
        Enum.map(sorted_objects, fn obj ->
          %{id: obj.id, position: obj.position}
        end)

      _ ->
        Enum.map(sorted_objects, fn obj ->
          %{id: obj.id, position: obj.position}
        end)
    end
  end

  @doc """
  Applies relationship-based constraint positioning to objects.

  ## Parameters
    * `objects` - List of object maps with id, position, and data
    * `relationships` - List of constraint maps with subject_id, relation, reference_id, spacing
    * `apply_constraints` - Whether to apply full constraint solving (true) or sequential application (false)

  ## Returns
    List of update maps with new positions

  ## Examples

      iex> objects = [
      ...>   %{id: 1, position: %{x: 0, y: 0}, data: %{width: 50, height: 50}},
      ...>   %{id: 2, position: %{x: 100, y: 0}, data: %{width: 50, height: 50}}
      ...> ]
      iex> relationships = [%{"subject_id" => 2, "relation" => "below", "reference_id" => 1, "spacing" => 20}]
      iex> apply_relationships(objects, relationships, true)
      [
        %{id: 1, position: %{x: 0, y: 0}},
        %{id: 2, position: %{x: 0, y: 70}}
      ]
  """
  def apply_relationships([], _relationships, _apply_constraints), do: []

  def apply_relationships(objects, relationships, _apply_constraints) when is_list(objects) do
    # Build a map of object IDs to objects for quick lookup
    objects_map = Enum.into(objects, %{}, fn obj -> {obj.id, obj} end)

    # Start with current positions
    initial_positions =
      Enum.into(objects, %{}, fn obj ->
        {obj.id, obj.position}
      end)

    # Apply each relationship constraint sequentially
    final_positions =
      Enum.reduce(relationships, initial_positions, fn rel, positions ->
        apply_single_relationship(rel, positions, objects_map)
      end)

    # Convert back to list of updates
    Enum.map(objects, fn obj ->
      %{
        id: obj.id,
        position: Map.get(final_positions, obj.id, obj.position)
      }
    end)
  end

  # Private helper functions for pattern layouts

  defp apply_line_pattern(objects, params) do
    direction = Map.get(params, "direction", "horizontal")
    spacing = Map.get(params, "spacing", 50)
    start_x = Map.get(params, "start_x", get_position_x(List.first(objects)))
    start_y = Map.get(params, "start_y", get_position_y(List.first(objects)))

    case direction do
      "vertical" ->
        {result, _} =
          Enum.reduce(objects, {[], start_y}, fn obj, {acc, current_y} ->
            update = %{id: obj.id, position: %{x: round(start_x), y: round(current_y)}}
            next_y = current_y + get_object_height(obj) + spacing
            {acc ++ [update], next_y}
          end)

        result

      "horizontal" ->
        {result, _} =
          Enum.reduce(objects, {[], start_x}, fn obj, {acc, current_x} ->
            update = %{id: obj.id, position: %{x: round(current_x), y: round(start_y)}}
            next_x = current_x + get_object_width(obj) + spacing
            {acc ++ [update], next_x}
          end)

        result

      _ ->
        # Default to horizontal
        {result, _} =
          Enum.reduce(objects, {[], start_x}, fn obj, {acc, current_x} ->
            update = %{id: obj.id, position: %{x: round(current_x), y: round(start_y)}}
            next_x = current_x + get_object_width(obj) + spacing
            {acc ++ [update], next_x}
          end)

        result
    end
  end

  defp apply_diagonal_pattern(objects, params) do
    direction = Map.get(params, "direction", "diagonal-right")
    spacing = Map.get(params, "spacing", 50)
    start_x = Map.get(params, "start_x", get_position_x(List.first(objects)))
    start_y = Map.get(params, "start_y", get_position_y(List.first(objects)))

    {dx, dy} =
      case direction do
        "diagonal-right" -> {1, 1}
        "diagonal-left" -> {-1, 1}
        _ -> {1, 1}
      end

    objects
    |> Enum.with_index()
    |> Enum.map(fn {obj, index} ->
      offset = index * spacing
      new_x = start_x + dx * offset
      new_y = start_y + dy * offset

      %{id: obj.id, position: %{x: round(new_x), y: round(new_y)}}
    end)
  end

  defp apply_wave_pattern(objects, params) do
    spacing = Map.get(params, "spacing", 50)
    amplitude = Map.get(params, "amplitude", 100)
    frequency = Map.get(params, "frequency", 2)
    start_x = Map.get(params, "start_x", get_position_x(List.first(objects)))
    start_y = Map.get(params, "start_y", get_position_y(List.first(objects)))

    count = length(objects)

    objects
    |> Enum.with_index()
    |> Enum.map(fn {obj, index} ->
      x_offset = index * spacing
      # Wave function: y = amplitude * sin(frequency * x / total_width * 2π)
      progress = index / max(count - 1, 1)
      y_offset = amplitude * :math.sin(frequency * progress * 2 * :math.pi())

      new_x = start_x + x_offset
      new_y = start_y + y_offset

      %{id: obj.id, position: %{x: round(new_x), y: round(new_y)}}
    end)
  end

  defp apply_arc_pattern(objects, params) do
    amplitude = Map.get(params, "amplitude", 100)
    spacing = Map.get(params, "spacing", 50)
    start_x = Map.get(params, "start_x", get_position_x(List.first(objects)))
    start_y = Map.get(params, "start_y", get_position_y(List.first(objects)))

    count = length(objects)

    objects
    |> Enum.with_index()
    |> Enum.map(fn {obj, index} ->
      x_offset = index * spacing
      # Arc function: parabola y = -a * (x - w/2)^2 + h
      progress = index / max(count - 1, 1)
      # -1 to 1
      normalized = (progress - 0.5) * 2
      y_offset = amplitude * (1 - normalized * normalized)

      new_x = start_x + x_offset
      new_y = start_y - y_offset

      %{id: obj.id, position: %{x: round(new_x), y: round(new_y)}}
    end)
  end

  defp apply_single_relationship(rel, positions, objects_map) do
    subject_id = rel["subject_id"]
    relation = rel["relation"]
    reference_id = rel["reference_id"]
    spacing = Map.get(rel, "spacing", 20)

    subject_obj = Map.get(objects_map, subject_id)
    reference_obj = Map.get(objects_map, reference_id)

    if is_nil(subject_obj) or is_nil(reference_obj) do
      positions
    else
      reference_pos = Map.get(positions, reference_id, reference_obj.position)

      new_position =
        case relation do
          "below" ->
            ref_y = get_position_value(reference_pos, :y)
            ref_height = get_object_height(reference_obj)

            %{
              x: get_position_value(reference_pos, :x),
              y: round(ref_y + ref_height + spacing)
            }

          "above" ->
            ref_y = get_position_value(reference_pos, :y)
            subject_height = get_object_height(subject_obj)

            %{
              x: get_position_value(reference_pos, :x),
              y: round(ref_y - subject_height - spacing)
            }

          "right_of" ->
            ref_x = get_position_value(reference_pos, :x)
            ref_width = get_object_width(reference_obj)

            %{
              x: round(ref_x + ref_width + spacing),
              y: get_position_value(reference_pos, :y)
            }

          "left_of" ->
            ref_x = get_position_value(reference_pos, :x)
            subject_width = get_object_width(subject_obj)

            %{
              x: round(ref_x - subject_width - spacing),
              y: get_position_value(reference_pos, :y)
            }

          "aligned_horizontally_with" ->
            %{
              x: get_position_value(Map.get(positions, subject_id, subject_obj.position), :x),
              y: get_position_value(reference_pos, :y)
            }

          "aligned_vertically_with" ->
            %{
              x: get_position_value(reference_pos, :x),
              y: get_position_value(Map.get(positions, subject_id, subject_obj.position), :y)
            }

          "centered_between" ->
            # For centered_between, we need reference_id_2
            reference_id_2 = Map.get(rel, "reference_id_2")

            if reference_id_2 do
              reference_obj_2 = Map.get(objects_map, reference_id_2)
              reference_pos_2 = Map.get(positions, reference_id_2, reference_obj_2.position)

              ref1_x = get_position_value(reference_pos, :x)
              ref2_x = get_position_value(reference_pos_2, :x)
              ref1_y = get_position_value(reference_pos, :y)
              ref2_y = get_position_value(reference_pos_2, :y)

              center_x = (ref1_x + ref2_x) / 2
              center_y = (ref1_y + ref2_y) / 2

              %{x: round(center_x), y: round(center_y)}
            else
              Map.get(positions, subject_id, subject_obj.position)
            end

          _ ->
            # Unknown relation, keep current position
            Map.get(positions, subject_id, subject_obj.position)
        end

      Map.put(positions, subject_id, new_position)
    end
  end

  defp get_position_value(position, key) do
    cond do
      is_map(position) and Map.has_key?(position, key) ->
        Map.get(position, key)

      is_map(position) and Map.has_key?(position, to_string(key)) ->
        Map.get(position, to_string(key))

      true ->
        0
    end
  end

  @doc """
  Arranges objects in a star pattern.

  ## Parameters
    * `objects` - List of object maps with id, position, and data
    * `points` - Number of star points (default: 5)
    * `outer_radius` - Radius to outer points in pixels (default: 300)
    * `inner_radius` - Radius to inner points in pixels (default: outer_radius * 0.4)

  ## Returns
    List of update maps with new positions

  ## Examples

      iex> objects = [%{id: "1", position: %{x: 0, y: 0}, data: %{width: 50, height: 50}}]
      iex> star_layout(objects, 5, 300, 120)
      [%{id: "1", position: %{x: 300, y: 0}}]
  """
  def star_layout(objects, points \\ 5, outer_radius \\ 300, inner_radius \\ nil)

  def star_layout([], _points, _outer_radius, _inner_radius), do: []
  def star_layout([single], _points, _outer_radius, _inner_radius),
    do: [%{id: single.id, position: single.position}]

  def star_layout(objects, points, outer_radius, inner_radius)
      when is_list(objects) and is_integer(points) and points >= 3 do
    # Calculate center point based on average position
    center_x =
      objects
      |> Enum.map(&get_position_x/1)
      |> Enum.sum()
      |> Kernel./(length(objects))
      |> round()

    center_y =
      objects
      |> Enum.map(&get_position_y/1)
      |> Enum.sum()
      |> Kernel./(length(objects))
      |> round()

    # Default inner radius to 40% of outer radius if not specified
    actual_inner_radius = inner_radius || round(outer_radius * 0.4)

    # Calculate angle between points
    angle_step = :math.pi() / points  # Half the circle division for star points

    # Total number of positions in star (outer + inner points)
    total_positions = points * 2

    # Distribute objects across all star points
    objects
    |> Enum.with_index()
    |> Enum.map(fn {obj, index} ->
      # Determine if this is an outer or inner point
      is_outer = rem(index, 2) == 0
      radius = if is_outer, do: outer_radius, else: actual_inner_radius

      # Calculate angle (start from top and go clockwise)
      angle = index * angle_step - :math.pi() / 2

      # Calculate position on star point
      obj_width = get_object_width(obj)
      obj_height = get_object_height(obj)

      new_x = center_x + round(radius * :math.cos(angle) - obj_width / 2)
      new_y = center_y + round(radius * :math.sin(angle) - obj_height / 2)

      %{
        id: obj.id,
        position: %{x: new_x, y: new_y}
      }
    end)
  end

  @doc """
  Arranges objects along a defined path (line, arc, bezier curve).

  ## Parameters
    * `objects` - List of object maps with id, position, and data
    * `path_type` - Type of path: "line", "arc", "bezier", "spiral"
    * `params` - Map of path-specific parameters

  ## Path Types and Parameters

  ### Line
    * `start_x`, `start_y` - Starting point
    * `end_x`, `end_y` - Ending point

  ### Arc
    * `center_x`, `center_y` - Center of arc
    * `radius` - Arc radius
    * `start_angle` - Starting angle in degrees
    * `end_angle` - Ending angle in degrees

  ### Bezier
    * `start_x`, `start_y` - Starting point
    * `end_x`, `end_y` - Ending point
    * `control1_x`, `control1_y` - First control point
    * `control2_x`, `control2_y` - Second control point (optional, for cubic)

  ### Spiral
    * `center_x`, `center_y` - Center of spiral
    * `start_radius` - Starting radius
    * `end_radius` - Ending radius
    * `rotations` - Number of rotations (default: 2)

  ## Returns
    List of update maps with new positions

  ## Examples

      iex> objects = [%{id: "1", position: %{x: 0, y: 0}, data: %{width: 50, height: 50}}]
      iex> params = %{"start_x" => 0, "start_y" => 0, "end_x" => 100, "end_y" => 100}
      iex> arrange_along_path(objects, "line", params)
      [%{id: "1", position: %{x: 0, y: 0}}]
  """
  def arrange_along_path([], _path_type, _params), do: []

  def arrange_along_path(objects, path_type, params) when is_list(objects) do
    count = length(objects)

    case path_type do
      "line" ->
        arrange_along_line(objects, params, count)

      "arc" ->
        arrange_along_arc(objects, params, count)

      "bezier" ->
        arrange_along_bezier(objects, params, count)

      "spiral" ->
        arrange_along_spiral(objects, params, count)

      _ ->
        # Unknown path type, return objects unchanged
        Enum.map(objects, fn obj -> %{id: obj.id, position: obj.position} end)
    end
  end

  # Private helper functions for path arrangements

  defp arrange_along_line(objects, params, count) do
    start_x = Map.get(params, "start_x", 0)
    start_y = Map.get(params, "start_y", 0)
    end_x = Map.get(params, "end_x", 100)
    end_y = Map.get(params, "end_y", 100)

    objects
    |> Enum.with_index()
    |> Enum.map(fn {obj, index} ->
      # Calculate position along line (0.0 to 1.0)
      t = if count > 1, do: index / (count - 1), else: 0.5

      # Linear interpolation
      x = start_x + (end_x - start_x) * t
      y = start_y + (end_y - start_y) * t

      # Center object on point
      obj_width = get_object_width(obj)
      obj_height = get_object_height(obj)

      %{
        id: obj.id,
        position: %{x: round(x - obj_width / 2), y: round(y - obj_height / 2)}
      }
    end)
  end

  defp arrange_along_arc(objects, params, count) do
    center_x = Map.get(params, "center_x", 0)
    center_y = Map.get(params, "center_y", 0)
    radius = Map.get(params, "radius", 200)
    start_angle = Map.get(params, "start_angle", 0)
    end_angle = Map.get(params, "end_angle", 180)

    # Convert degrees to radians
    start_rad = start_angle * :math.pi() / 180
    end_rad = end_angle * :math.pi() / 180

    objects
    |> Enum.with_index()
    |> Enum.map(fn {obj, index} ->
      # Calculate position along arc (0.0 to 1.0)
      t = if count > 1, do: index / (count - 1), else: 0.5

      # Interpolate angle
      angle = start_rad + (end_rad - start_rad) * t

      # Calculate position on arc
      x = center_x + radius * :math.cos(angle)
      y = center_y + radius * :math.sin(angle)

      # Center object on point
      obj_width = get_object_width(obj)
      obj_height = get_object_height(obj)

      %{
        id: obj.id,
        position: %{x: round(x - obj_width / 2), y: round(y - obj_height / 2)}
      }
    end)
  end

  defp arrange_along_bezier(objects, params, count) do
    start_x = Map.get(params, "start_x", 0)
    start_y = Map.get(params, "start_y", 0)
    end_x = Map.get(params, "end_x", 100)
    end_y = Map.get(params, "end_y", 100)
    control1_x = Map.get(params, "control1_x", 25)
    control1_y = Map.get(params, "control1_y", -25)
    control2_x = Map.get(params, "control2_x", 75)
    control2_y = Map.get(params, "control2_y", -25)

    objects
    |> Enum.with_index()
    |> Enum.map(fn {obj, index} ->
      # Calculate position along curve (0.0 to 1.0)
      t = if count > 1, do: index / (count - 1), else: 0.5

      # Cubic Bezier formula: B(t) = (1-t)³P₀ + 3(1-t)²tP₁ + 3(1-t)t²P₂ + t³P₃
      one_minus_t = 1 - t
      one_minus_t_sq = one_minus_t * one_minus_t
      one_minus_t_cu = one_minus_t_sq * one_minus_t
      t_sq = t * t
      t_cu = t_sq * t

      x =
        one_minus_t_cu * start_x +
          3 * one_minus_t_sq * t * control1_x +
          3 * one_minus_t * t_sq * control2_x +
          t_cu * end_x

      y =
        one_minus_t_cu * start_y +
          3 * one_minus_t_sq * t * control1_y +
          3 * one_minus_t * t_sq * control2_y +
          t_cu * end_y

      # Center object on point
      obj_width = get_object_width(obj)
      obj_height = get_object_height(obj)

      %{
        id: obj.id,
        position: %{x: round(x - obj_width / 2), y: round(y - obj_height / 2)}
      }
    end)
  end

  defp arrange_along_spiral(objects, params, count) do
    center_x = Map.get(params, "center_x", 0)
    center_y = Map.get(params, "center_y", 0)
    start_radius = Map.get(params, "start_radius", 50)
    end_radius = Map.get(params, "end_radius", 300)
    rotations = Map.get(params, "rotations", 2)

    objects
    |> Enum.with_index()
    |> Enum.map(fn {obj, index} ->
      # Calculate position along spiral (0.0 to 1.0)
      t = if count > 1, do: index / (count - 1), else: 0.5

      # Interpolate radius
      radius = start_radius + (end_radius - start_radius) * t

      # Calculate angle (multiple rotations)
      angle = t * rotations * 2 * :math.pi()

      # Calculate position on spiral
      x = center_x + radius * :math.cos(angle)
      y = center_y + radius * :math.sin(angle)

      # Center object on point
      obj_width = get_object_width(obj)
      obj_height = get_object_height(obj)

      %{
        id: obj.id,
        position: %{x: round(x - obj_width / 2), y: round(y - obj_height / 2)}
      }
    end)
  end
end
