defmodule CollabCanvas.AI.BatchProcessor do
  @moduledoc """
  Handles batching of create_* tool calls for efficient bulk object creation.

  This module provides functionality to group create_shape and create_text tool calls
  and execute them as a single atomic batch operation using Canvases.create_objects_batch/2.

  Performance target: 10 objects in <2s, up to 600 objects for demo.
  """

  require Logger
  alias CollabCanvas.Canvases

  @doc """
  Checks if a tool call is a create operation (create_shape or create_text).
  """
  def is_create_tool?(%{name: name}) do
    name in ["create_shape", "create_text"]
  end

  @doc """
  Executes multiple create tool calls as a single atomic batch operation.

  Takes a list of create_* tool calls and transforms them into attributes
  suitable for Canvases.create_objects_batch/2. Handles both create_shape
  and create_text operations, including the count parameter for bulk creation.

  ## Parameters
    * `create_calls` - List of create_* tool call maps
    * `canvas_id` - The canvas ID
    * `current_color` - Default color for objects
    * `normalize_color_fun` - Function to normalize color values

  ## Returns
    * List of result maps (one per tool call), each containing:
      - `:tool` - Tool name ("create_shape" or "create_text")
      - `:input` - Original input parameters
      - `:result` - {:ok, objects} or {:error, reason}
  """
  def execute_batched_creates(create_calls, canvas_id, current_color, normalize_color_fun) do
    # Build list of attributes for all objects to create
    # Each create_* call may generate multiple objects if count > 1
    {all_attrs, call_metadata} = Enum.reduce(create_calls, {[], []}, fn tool_call, {attrs_acc, meta_acc} ->
      # Transform tool call into object attributes
      {new_attrs, object_count} = build_object_attrs_from_tool_call(tool_call, current_color, normalize_color_fun)

      # Track which objects belong to which tool call for result mapping
      metadata = %{
        tool_call: tool_call,
        object_count: object_count,
        start_idx: length(attrs_acc)
      }

      {attrs_acc ++ new_attrs, meta_acc ++ [metadata]}
    end)

    # Execute batch create
    case Canvases.create_objects_batch(canvas_id, all_attrs) do
      {:ok, created_objects} ->
        # Map created objects back to their originating tool calls
        Enum.map(call_metadata, fn %{tool_call: tool_call, object_count: count, start_idx: start_idx} ->
          # Extract objects for this tool call
          objects_for_call = Enum.slice(created_objects, start_idx, count)

          %{
            tool: tool_call.name,
            input: tool_call.input,
            result: if count > 1 do
              {:ok, %{count: length(objects_for_call), total: count, objects: objects_for_call}}
            else
              {:ok, List.first(objects_for_call)}
            end
          }
        end)

      {:error, _failed_operation, _failed_value, _changes_so_far} ->
        # Batch transaction failed - return error for all calls
        Enum.map(create_calls, fn tool_call ->
          %{
            tool: tool_call.name,
            input: tool_call.input,
            result: {:error, :batch_create_failed}
          }
        end)
    end
  end

  @doc """
  Transforms a create_* tool call into a list of object attribute maps.

  Handles create_shape and create_text, including the count parameter for
  creating multiple identical objects. Applies color normalization and
  spacing calculations for multi-object creation.

  ## Parameters
    * `tool_call` - Tool call map with :name and :input keys
    * `current_color` - Default color to use
    * `normalize_color_fun` - Function to normalize color values

  ## Returns
    * {list_of_attrs, object_count} - Tuple with attribute maps and count
  """
  def build_object_attrs_from_tool_call(%{name: "create_shape", input: input}, current_color, normalize_color_fun) do
    # Determine final color (AI-provided or current color)
    ai_color = Map.get(input, "fill") || Map.get(input, "color")
    final_color = normalize_color_fun.(ai_color || current_color)

    # Get count parameter (default to 1)
    count = Map.get(input, "count", 1)

    # Build attributes for each shape
    if count > 1 do
      # Calculate spacing for multiple shapes
      base_width = input["width"] || 50
      default_spacing = base_width * 1.5
      spacing = Map.get(input, "spacing", default_spacing)

      attrs_list = Enum.map(0..(count - 1), fn index ->
        data = %{
          width: input["width"],
          height: input["height"],
          color: final_color
        }

        # Calculate position for this shape
        x_offset = index * (base_width + spacing)

        %{
          type: input["type"],
          position: %{
            x: input["x"] + x_offset,
            y: input["y"]
          },
          data: Jason.encode!(data)
        }
      end)

      {attrs_list, count}
    else
      # Single shape
      data = %{
        width: input["width"],
        height: input["height"],
        color: final_color
      }

      attrs = %{
        type: input["type"],
        position: %{
          x: input["x"],
          y: input["y"]
        },
        data: Jason.encode!(data)
      }

      {[attrs], 1}
    end
  end

  def build_object_attrs_from_tool_call(%{name: "create_text", input: input}, current_color, normalize_color_fun) do
    # Determine final color
    ai_color = Map.get(input, "color")
    final_color = normalize_color_fun.(ai_color || current_color)

    data = %{
      text: input["text"],
      font_size: Map.get(input, "font_size", 16),
      color: final_color
    }

    attrs = %{
      type: "text",
      position: %{
        x: input["x"],
        y: input["y"]
      },
      data: Jason.encode!(data)
    }

    {[attrs], 1}
  end

  @doc """
  Combines batch and individual results back into original tool call order.

  This is critical because the AI expects results in the same order as
  the tool calls it made. We need to interleave batch results (from
  create_* calls) with individual results (from other calls) to match
  the original tool_calls list order.

  ## Parameters
    * `original_tool_calls` - Original (non-normalized) tool calls in order
    * `batch_results` - Results from batched create operations
    * `other_results` - Results from individual non-create operations

  ## Returns
    * List of results in the same order as original_tool_calls
  """
  def combine_results_in_order(original_tool_calls, batch_results, other_results) do
    # Create index maps for O(1) lookup
    batch_indices = batch_results
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {result, idx}, acc ->
      key = {result.tool, inspect(result.input)}
      Map.update(acc, key, [idx], &(&1 ++ [idx]))
    end)

    other_indices = other_results
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {result, idx}, acc ->
      key = {result.tool, inspect(result.input)}
      Map.update(acc, key, [idx], &(&1 ++ [idx]))
    end)

    # Track which indices we've already consumed
    state = %{batch: batch_indices, other: other_indices, batch_results: batch_results, other_results: other_results}

    {results, _} = Enum.reduce(original_tool_calls, {[], state}, fn tool_call, {results_acc, current_state} ->
      key = {tool_call.name, inspect(tool_call.input)}

      if is_create_tool?(tool_call) do
        # Pop from batch results
        case Map.get(current_state.batch, key) do
          [idx | rest] ->
            result = Enum.at(current_state.batch_results, idx)
            updated_state = %{current_state | batch: Map.put(current_state.batch, key, rest)}
            {results_acc ++ [result], updated_state}
          _ ->
            {results_acc, current_state}
        end
      else
        # Pop from other results
        case Map.get(current_state.other, key) do
          [idx | rest] ->
            result = Enum.at(current_state.other_results, idx)
            updated_state = %{current_state | other: Map.put(current_state.other, key, rest)}
            {results_acc ++ [result], updated_state}
          _ ->
            {results_acc, current_state}
        end
      end
    end)

    results
  end
end
