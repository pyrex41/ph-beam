defmodule CollabCanvas.Canvases.Object do
  @moduledoc """
  Object schema for the CollabCanvas application.
  Represents a graphical object (rectangle, circle, text, etc.) on a canvas.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias CollabCanvas.Canvases.Canvas
  alias CollabCanvas.Components.Component

  @derive {Jason.Encoder,
           only: [
             :id,
             :type,
             :data,
             :position,
             :canvas_id,
             :locked_by,
             :locked_at,
             :component_id,
             :is_main_component,
             :instance_overrides,
             :group_id,
             :z_index,
             :inserted_at,
             :updated_at
           ]}
  schema "objects" do
    field(:type, :string)
    field(:data, :string)
    field(:position, :map)
    field(:locked_by, :string)
    field(:locked_at, :utc_datetime)
    field(:is_main_component, :boolean, default: false)
    field(:instance_overrides, :string)
    field(:group_id, :binary_id)
    field(:z_index, :float, default: 0.0)

    belongs_to(:canvas, Canvas)
    belongs_to(:component, Component)

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or updating an object.

  ## Required fields
    * `:type` - Object type (e.g., "rectangle", "circle", "text")
    * `:canvas_id` - ID of the canvas this object belongs to

  ## Optional fields
    * `:data` - JSON string containing object-specific data (color, size, text content, etc.)
    * `:position` - Map containing x and y coordinates
    * `:locked_by` - User ID string indicating which user has locked this object for editing
    * `:component_id` - ID of the component this object belongs to (for component instances)
    * `:is_main_component` - Boolean indicating if this is a main component object
    * `:instance_overrides` - JSON string containing instance-specific overrides
    * `:group_id` - UUID indicating which group this object belongs to (for grouping)
    * `:z_index` - Float value indicating the layer order (higher values are in front)

  ## Validations
    * Type must be present and one of the allowed types
    * Canvas ID must be present
    * Position must be a valid map with x and y keys when present
  """
  def changeset(object, attrs) do
    object
    |> cast(attrs, [
      :type,
      :data,
      :position,
      :canvas_id,
      :locked_by,
      :locked_at,
      :component_id,
      :is_main_component,
      :instance_overrides,
      :group_id,
      :z_index
    ])
    |> validate_required([:type, :canvas_id])
    |> validate_inclusion(:type, ["rectangle", "circle", "ellipse", "text", "line", "path", "star", "triangle", "polygon"])
    |> validate_position()
    |> foreign_key_constraint(:canvas_id, name: "objects_canvas_id_fkey")
    |> foreign_key_constraint(:component_id, name: "objects_component_id_fkey")
  end

  # Private helper to validate position map structure
  defp validate_position(changeset) do
    case get_change(changeset, :position) do
      nil ->
        changeset

      position when is_map(position) ->
        x = Map.get(position, "x") || Map.get(position, :x)
        y = Map.get(position, "y") || Map.get(position, :y)

        cond do
          not is_number(x) ->
            add_error(changeset, :position, "must contain numeric x coordinate")

          not is_number(y) ->
            add_error(changeset, :position, "must contain numeric y coordinate")

          true ->
            changeset
        end

      _ ->
        add_error(changeset, :position, "must be a map with x and y coordinates")
    end
  end
end
