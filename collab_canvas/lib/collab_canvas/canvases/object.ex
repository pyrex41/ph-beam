defmodule CollabCanvas.Canvases.Object do
  @moduledoc """
  Object schema for the CollabCanvas application.
  Represents a graphical object (rectangle, circle, text, etc.) on a canvas.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias CollabCanvas.Canvases.Canvas

  @derive {Jason.Encoder,
           only: [:id, :type, :data, :position, :canvas_id, :locked_by, :inserted_at, :updated_at]}
  schema "objects" do
    field(:type, :string)
    field(:data, :string)
    field(:position, :map)
    field(:locked_by, :string)

    belongs_to(:canvas, Canvas)

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

  ## Validations
    * Type must be present and one of the allowed types
    * Canvas ID must be present
    * Position must be a valid map with x and y keys when present
  """
  def changeset(object, attrs) do
    object
    |> cast(attrs, [:type, :data, :position, :canvas_id, :locked_by])
    |> validate_required([:type, :canvas_id])
    |> validate_inclusion(:type, ["rectangle", "circle", "ellipse", "text", "line", "path"])
    |> validate_position()
    |> foreign_key_constraint(:canvas_id, name: "objects_canvas_id_fkey")
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
