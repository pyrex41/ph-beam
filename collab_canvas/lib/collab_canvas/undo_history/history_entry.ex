defmodule CollabCanvas.UndoHistory.HistoryEntry do
  @moduledoc """
  Schema for undo/redo history entries stored per user per canvas.

  Each entry stores two JSONB stacks:
  - undo_stack: Operations that can be undone (newest first)
  - redo_stack: Operations that can be redone (newest first)

  Each operation in the stack has the format:
  %{
    id: "uuid",
    type: "batch_update" | "create" | "delete" | "style" | "reorder",
    timestamp: "2025-10-19T17:18:26Z",
    objects: [
      %{id: 123, before: {...}, after: {...}}  # Full state capture for restoration
    ]
  }
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "undo_history" do
    field :user_id, :string
    field :canvas_id, :id
    field :undo_stack, {:array, :map}, default: []
    field :redo_stack, {:array, :map}, default: []

    timestamps()
  end

  @doc false
  def changeset(history_entry, attrs) do
    history_entry
    |> cast(attrs, [:user_id, :canvas_id, :undo_stack, :redo_stack])
    |> validate_required([:user_id, :canvas_id])
    |> unique_constraint([:user_id, :canvas_id])
  end
end
