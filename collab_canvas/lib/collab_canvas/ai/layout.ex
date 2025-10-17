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
  def distribute_horizontally([single], _spacing), do: [%{id: single.id, position: single.position}]

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

  def arrange_grid(objects, columns, spacing) when is_list(objects) and is_integer(columns) and columns > 0 do
    # Start from the top-left position of the first object
    first_obj = Enum.at(objects, 0)
    start_x = get_position_x(first_obj) |> round()
    start_y = get_position_y(first_obj) |> round()

    # Calculate max width and height for uniform grid cells
    max_width = objects
                |> Enum.map(fn obj -> get_object_width(obj) end)
                |> Enum.max(fn -> 0 end)
                |> round()

    max_height = objects
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
    # Calculate center point based on average position
    center_x = objects
               |> Enum.map(&get_position_x/1)
               |> Enum.sum()
               |> Kernel./(length(objects))
               |> round()

    center_y = objects
               |> Enum.map(&get_position_y/1)
               |> Enum.sum()
               |> Kernel./(length(objects))
               |> round()

    # Distribute objects evenly around the circle
    count = length(objects)
    angle_step = 2 * :math.pi() / count

    objects
    |> Enum.with_index()
    |> Enum.map(fn {obj, index} ->
      angle = index * angle_step

      # Calculate position on circle, accounting for object size to center it
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

  # Private helper functions

  # Distributes objects horizontally with even spacing between them
  defp distribute_horizontally_even(sorted_objects) do
    first = List.first(sorted_objects)
    last = List.last(sorted_objects)

    # Calculate total available space
    first_x = get_position_x(first)
    last_x = get_position_x(last)
    last_width = get_object_width(last)

    total_width = (last_x + last_width) - first_x

    # Calculate total object widths
    total_object_width = sorted_objects
                         |> Enum.map(&get_object_width/1)
                         |> Enum.sum()

    # Calculate even spacing
    total_gap_space = total_width - total_object_width
    gap_count = length(sorted_objects) - 1
    spacing = if gap_count > 0, do: total_gap_space / gap_count, else: 0

    # Position objects with calculated spacing
    {result, _} = Enum.reduce(sorted_objects, {[], first_x}, fn obj, {acc, current_x} ->
      new_position = %{x: round(current_x), y: get_position_y(obj)}
      update = %{id: obj.id, position: new_position}
      next_x = current_x + get_object_width(obj) + spacing

      {acc ++ [update], next_x}
    end)

    result
  end

  # Distributes objects horizontally with fixed spacing
  defp distribute_horizontally_fixed(sorted_objects, spacing) do
    first = List.first(sorted_objects)
    start_x = get_position_x(first)

    {result, _} = Enum.reduce(sorted_objects, {[], start_x}, fn obj, {acc, current_x} ->
      new_position = %{x: round(current_x), y: get_position_y(obj)}
      update = %{id: obj.id, position: new_position}
      next_x = current_x + get_object_width(obj) + spacing

      {acc ++ [update], next_x}
    end)

    result
  end

  # Distributes objects vertically with even spacing between them
  defp distribute_vertically_even(sorted_objects) do
    first = List.first(sorted_objects)
    last = List.last(sorted_objects)

    # Calculate total available space
    first_y = get_position_y(first)
    last_y = get_position_y(last)
    last_height = get_object_height(last)

    total_height = (last_y + last_height) - first_y

    # Calculate total object heights
    total_object_height = sorted_objects
                          |> Enum.map(&get_object_height/1)
                          |> Enum.sum()

    # Calculate even spacing
    total_gap_space = total_height - total_object_height
    gap_count = length(sorted_objects) - 1
    spacing = if gap_count > 0, do: total_gap_space / gap_count, else: 0

    # Position objects with calculated spacing
    {result, _} = Enum.reduce(sorted_objects, {[], first_y}, fn obj, {acc, current_y} ->
      new_position = %{x: get_position_x(obj), y: round(current_y)}
      update = %{id: obj.id, position: new_position}
      next_y = current_y + get_object_height(obj) + spacing

      {acc ++ [update], next_y}
    end)

    result
  end

  # Distributes objects vertically with fixed spacing
  defp distribute_vertically_fixed(sorted_objects, spacing) do
    first = List.first(sorted_objects)
    start_y = get_position_y(first)

    {result, _} = Enum.reduce(sorted_objects, {[], start_y}, fn obj, {acc, current_y} ->
      new_position = %{x: get_position_x(obj), y: round(current_y)}
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
    max_right = objects
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
    centers = Enum.map(objects, fn obj ->
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
    max_bottom = objects
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
    centers = Enum.map(objects, fn obj ->
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
    cond do
      is_map(obj.position) and Map.has_key?(obj.position, :x) ->
        obj.position.x

      is_map(obj.position) and Map.has_key?(obj.position, "x") ->
        obj.position["x"]

      true ->
        0  # Default x position
    end
  end

  defp get_position_y(obj) do
    cond do
      is_map(obj.position) and Map.has_key?(obj.position, :y) ->
        obj.position.y

      is_map(obj.position) and Map.has_key?(obj.position, "y") ->
        obj.position["y"]

      true ->
        0  # Default y position
    end
  end

  defp get_object_width(obj) do
    cond do
      is_map(obj.data) and Map.has_key?(obj.data, :width) ->
        obj.data.width

      is_map(obj.data) and Map.has_key?(obj.data, "width") ->
        obj.data["width"]

      true ->
        50  # Default width
    end
  end

  defp get_object_height(obj) do
    cond do
      is_map(obj.data) and Map.has_key?(obj.data, :height) ->
        obj.data.height

      is_map(obj.data) and Map.has_key?(obj.data, "height") ->
        obj.data["height"]

      true ->
        50  # Default height
    end
  end
end
