defmodule CollabCanvas.AI.Tools.ArrangeObjects do
  @moduledoc """
  AI tool for arranging multiple objects in layout patterns.

  This tool allows the AI to organize selected objects using various layout
  algorithms including horizontal/vertical distribution, grids, circular patterns,
  and stacks with alignment.

  ## Supported Layouts

  - **horizontal** - Distribute objects evenly along the X-axis
  - **vertical** - Distribute objects evenly along the Y-axis
  - **grid** - Arrange objects in a grid pattern (specify columns)
  - **circular** - Arrange objects in a circle (specify radius)
  - **stack** - Stack objects vertically with optional alignment

  ## Performance

  Layout operations are optimized to complete in <500ms for up to 50 objects
  (per PRD requirement). Performance metrics are logged for monitoring.

  ## Examples

      # Horizontal layout with fixed spacing
      execute(%{
        "object_ids" => [1, 2, 3],
        "layout_type" => "horizontal",
        "spacing" => 30
      }, %{canvas_id: 1})

      # Grid layout
      execute(%{
        "object_ids" => [1, 2, 3, 4, 5, 6],
        "layout_type" => "grid",
        "columns" => 3,
        "spacing" => 20
      }, %{canvas_id: 1})

      # Circular layout
      execute(%{
        "object_ids" => [1, 2, 3, 4, 5],
        "layout_type" => "circular",
        "radius" => 200
      }, %{canvas_id: 1})
  """

  @behaviour CollabCanvas.AI.Tool

  require Logger
  alias CollabCanvas.Canvases
  alias CollabCanvas.AI.Layout

  @impl true
  def definition do
    %{
      name: "arrange_objects",
      description:
        "Arranges selected objects in standard layout patterns. Use this for CIRCULAR, horizontal, vertical, grid, and stack layouts. For circular layouts, objects are distributed evenly around a circle at a specified radius. For custom patterns like diagonal lines, waves, or arcs, use arrange_objects_with_pattern instead.",
      input_schema: %{
        type: "object",
        properties: %{
          object_ids: %{
            type: "array",
            items: %{type: "integer"},
            description: "IDs of objects to arrange"
          },
          layout_type: %{
            type: "string",
            enum: ["horizontal", "vertical", "grid", "circular", "stack"],
            description: "Type of layout to apply"
          },
          spacing: %{
            type: "number",
            description: "Spacing between objects in pixels (default: 20)",
            default: 20
          },
          alignment: %{
            type: "string",
            enum: ["left", "center", "right", "top", "middle", "bottom"],
            description: "Alignment for objects (used with stack layout or separately)"
          },
          columns: %{
            type: "number",
            description: "Number of columns for grid layout",
            default: 3
          },
          radius: %{
            type: "number",
            description: "Radius in pixels for circular layout",
            default: 200
          }
        },
        required: ["object_ids", "layout_type"]
      }
    }
  end

  @impl true
  def execute(%{"object_ids" => object_ids, "layout_type" => layout_type} = params, %{
        canvas_id: canvas_id
      }) do
    # Start performance timer
    start_time = System.monotonic_time(:millisecond)

    # Fetch all objects to arrange
    objects =
      object_ids
      |> Enum.map(&fetch_object/1)
      |> Enum.reject(&is_nil/1)

    if length(objects) == 0 do
      {:error, :no_objects_found}
    else
      # Apply layout algorithm based on type
      updates = apply_layout(layout_type, objects, params)

      # Apply alignment if specified and not already applied
      final_updates =
        if Map.has_key?(params, "alignment") and layout_type != "stack" do
          aligned_objects = reconstruct_objects_with_positions(objects, updates)
          Layout.align_objects(aligned_objects, params["alignment"])
        else
          updates
        end

      # Batch update all objects atomically
      results = Enum.map(final_updates, &update_object_position/1)

      # Broadcast updates to all connected clients
      broadcast_updates(results, canvas_id)

      # Check if any updates failed
      failed = Enum.any?(results, fn
        {:error, _} -> true
        _ -> false
      end)

      # Calculate and log performance metrics
      duration_ms = System.monotonic_time(:millisecond) - start_time

      Logger.info(
        "Layout operation completed: #{layout_type} layout for #{length(results)} objects in #{duration_ms}ms"
      )

      if duration_ms > 500 do
        Logger.warning(
          "Layout operation exceeded 500ms target: #{duration_ms}ms for #{length(results)} objects"
        )
      end

      if failed do
        {:error, :partial_update_failure}
      else
        {:ok, %{updated: length(results), layout: layout_type, duration_ms: duration_ms}}
      end
    end
  end

  # Private helper functions

  defp fetch_object(id) do
    case Canvases.get_object(id) do
      nil ->
        nil

      obj ->
        # Decode data if it's a JSON string
        data =
          if is_binary(obj.data) do
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
  end

  defp apply_layout("horizontal", objects, params) do
    spacing = Map.get(params, "spacing", :even)
    Layout.distribute_horizontally(objects, spacing)
  end

  defp apply_layout("vertical", objects, params) do
    spacing = Map.get(params, "spacing", :even)
    Layout.distribute_vertically(objects, spacing)
  end

  defp apply_layout("grid", objects, params) do
    columns = Map.get(params, "columns", 3)
    spacing = Map.get(params, "spacing", 20)
    Layout.arrange_grid(objects, columns, spacing)
  end

  defp apply_layout("circular", objects, params) do
    radius = Map.get(params, "radius", 200)
    Layout.circular_layout(objects, radius)
  end

  defp apply_layout("stack", objects, params) do
    # Stack is vertical distribution with optional alignment
    alignment = Map.get(params, "alignment")
    distributed = Layout.distribute_vertically(objects, Map.get(params, "spacing", 20))

    if alignment do
      # Apply alignment after stacking
      aligned_objects = reconstruct_objects_with_positions(objects, distributed)
      Layout.align_objects(aligned_objects, alignment)
    else
      distributed
    end
  end

  defp apply_layout(_unknown, _objects, _params) do
    []
  end

  defp reconstruct_objects_with_positions(objects, updates) do
    Enum.map(updates, fn update ->
      obj = Enum.find(objects, fn o -> o.id == update.id end)
      %{obj | position: update.position}
    end)
  end

  defp update_object_position(update) do
    attrs = %{position: update.position}
    Canvases.update_object(update.id, attrs)
  end

  defp broadcast_updates(results, canvas_id) do
    Enum.each(results, fn
      {:ok, updated_object} ->
        Phoenix.PubSub.broadcast(
          CollabCanvas.PubSub,
          "canvas:#{canvas_id}",
          {:object_updated, updated_object}
        )

      _ ->
        :ok
    end)
  end
end
