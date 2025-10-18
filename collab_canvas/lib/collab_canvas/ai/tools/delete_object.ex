defmodule CollabCanvas.AI.Tools.DeleteObject do
  @moduledoc """
  AI tool for deleting objects from the canvas.

  This tool allows the AI to remove objects by their ID. It's a simple operation
  that demonstrates the basic tool pattern for single-object operations.

  ## Examples

      # Delete an object
      execute(%{
        "object_id" => 123
      }, %{canvas_id: 1})
  """

  @behaviour CollabCanvas.AI.Tool

  alias CollabCanvas.Canvases

  @impl true
  def definition do
    %{
      name: "delete_object",
      description: "Delete an object from the canvas",
      input_schema: %{
        type: "object",
        properties: %{
          object_id: %{
            type: "integer",
            description: "ID of the object to delete"
          }
        },
        required: ["object_id"]
      }
    }
  end

  @impl true
  def execute(%{"object_id" => object_id}, %{canvas_id: canvas_id}) do
    case Canvases.delete_object(object_id) do
      {:ok, _deleted_object} = success ->
        # Broadcast deletion to all connected clients
        Phoenix.PubSub.broadcast(
          CollabCanvas.PubSub,
          "canvas:#{canvas_id}",
          {:object_deleted, object_id}
        )

        success

      error ->
        error
    end
  end
end
