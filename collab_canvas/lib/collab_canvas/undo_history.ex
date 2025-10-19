defmodule CollabCanvas.UndoHistory do
  @moduledoc """
  Context module for managing per-user undo/redo history.

  Each user has their own undo/redo stacks per canvas, stored in the database
  to survive page refreshes. The system is batch-aware, meaning multi-object
  operations are tracked as atomic units.

  ## Operation Format

  Each operation stored in the undo/redo stacks has this structure:

      %{
        "id" => "uuid-v4",
        "type" => "batch_update" | "create" | "delete" | "style" | "reorder",
        "timestamp" => "2025-10-19T17:18:26Z",
        "objects" => [
          %{
            "id" => 123,
            "before" => %{...},  # Complete object state before operation
            "after" => %{...}     # Complete object state after operation (nil for delete)
          }
        ]
      }

  ## Stack Limits

  Each stack is limited to 50 operations per user per canvas. When pushing
  a new operation to a full stack, the oldest operation is automatically removed.
  """

  import Ecto.Query, warn: false
  alias CollabCanvas.Repo
  alias CollabCanvas.UndoHistory.HistoryEntry

  @max_stack_size 50

  @doc """
  Pushes a new operation onto the undo stack and clears the redo stack.

  This is called whenever a user performs any operation on the canvas.
  The redo stack is cleared because any new action invalidates the redo history.

  ## Parameters

    * `user_id` - The ID of the user performing the operation
    * `canvas_id` - The ID of the canvas being modified
    * `operation` - The operation data (see module doc for format)

  ## Examples

      iex> operation = %{
      ...>   "id" => UUID.uuid4(),
      ...>   "type" => "create",
      ...>   "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      ...>   "objects" => [%{"id" => 123, "before" => nil, "after" => %{...}}]
      ...> }
      iex> push_operation("user123", 1, operation)
      {:ok, %HistoryEntry{}}

  """
  def push_operation(user_id, canvas_id, operation) do
    # Get or create history entry for this user/canvas
    history = get_or_create_history(user_id, canvas_id)

    # Add operation to undo stack (newest first), clear redo stack
    new_undo_stack = [operation | history.undo_stack] |> Enum.take(@max_stack_size)

    history
    |> HistoryEntry.changeset(%{
      undo_stack: new_undo_stack,
      redo_stack: []  # Clear redo on new operation
    })
    |> Repo.update()
  end

  @doc """
  Undoes the last operation for a user on a canvas.

  Pops the most recent operation from the undo stack, pushes it onto the redo stack,
  and returns the operation so the caller can apply the inverse changes.

  ## Returns

    * `{:ok, operation}` - The operation to undo (contains "before" states to restore)
    * `{:error, :empty_undo_stack}` - No operations available to undo

  ## Examples

      iex> undo("user123", 1)
      {:ok, %{"id" => "...", "type" => "create", "objects" => [...]}}

      iex> undo("user_with_no_history", 1)
      {:error, :empty_undo_stack}

  """
  def undo(user_id, canvas_id) do
    history = get_or_create_history(user_id, canvas_id)

    case history.undo_stack do
      [] ->
        {:error, :empty_undo_stack}

      [operation | remaining_undo] ->
        # Move operation from undo to redo
        new_redo_stack = [operation | history.redo_stack] |> Enum.take(@max_stack_size)

        {:ok, _updated} =
          history
          |> HistoryEntry.changeset(%{
            undo_stack: remaining_undo,
            redo_stack: new_redo_stack
          })
          |> Repo.update()

        {:ok, operation}
    end
  end

  @doc """
  Redoes the last undone operation for a user on a canvas.

  Pops the most recent operation from the redo stack, pushes it back onto the undo stack,
  and returns the operation so the caller can reapply the changes.

  ## Returns

    * `{:ok, operation}` - The operation to redo (contains "after" states to restore)
    * `{:error, :empty_redo_stack}` - No operations available to redo

  ## Examples

      iex> redo("user123", 1)
      {:ok, %{"id" => "...", "type" => "create", "objects" => [...]}}

      iex> redo("user_with_no_redo", 1)
      {:error, :empty_redo_stack}

  """
  def redo(user_id, canvas_id) do
    history = get_or_create_history(user_id, canvas_id)

    case history.redo_stack do
      [] ->
        {:error, :empty_redo_stack}

      [operation | remaining_redo] ->
        # Move operation from redo back to undo
        new_undo_stack = [operation | history.undo_stack] |> Enum.take(@max_stack_size)

        {:ok, _updated} =
          history
          |> HistoryEntry.changeset(%{
            undo_stack: new_undo_stack,
            redo_stack: remaining_redo
          })
          |> Repo.update()

        {:ok, operation}
    end
  end

  @doc """
  Gets the current undo and redo stacks for a user on a canvas.

  This is typically called when the LiveView mounts to initialize the
  client-side state with any persisted history.

  ## Returns

      %{
        undo_stack: [...],  # List of operations (newest first)
        redo_stack: [...]   # List of operations (newest first)
      }

  ## Examples

      iex> get_stacks("user123", 1)
      %{undo_stack: [...], redo_stack: [...]}

  """
  def get_stacks(user_id, canvas_id) do
    history = get_or_create_history(user_id, canvas_id)

    %{
      undo_stack: history.undo_stack,
      redo_stack: history.redo_stack
    }
  end

  @doc """
  Clears all undo/redo history for a user on a canvas.

  This might be called when a user explicitly clears their history,
  or when a canvas is reset.

  ## Examples

      iex> clear_history("user123", 1)
      {:ok, %HistoryEntry{undo_stack: [], redo_stack: []}}

  """
  def clear_history(user_id, canvas_id) do
    history = get_or_create_history(user_id, canvas_id)

    history
    |> HistoryEntry.changeset(%{
      undo_stack: [],
      redo_stack: []
    })
    |> Repo.update()
  end

  @doc """
  Creates an operation map from object snapshots.

  Helper function to build properly formatted operations for push_operation/3.

  ## Parameters

    * `type` - Operation type: "create", "delete", "batch_update", "style", "reorder"
    * `objects` - List of %{id: int, before: map | nil, after: map | nil}

  ## Examples

      iex> create_operation("create", [%{id: 123, before: nil, after: %{"width" => 100}}])
      %{
        "id" => "uuid...",
        "type" => "create",
        "timestamp" => "2025-10-19T...",
        "objects" => [%{"id" => 123, "before" => nil, "after" => %{"width" => 100}}]
      }

  """
  def create_operation(type, objects) when is_binary(type) and is_list(objects) do
    %{
      "id" => Ecto.UUID.generate(),
      "type" => type,
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "objects" => Enum.map(objects, &serialize_object_snapshot/1)
    }
  end

  # Private Helpers

  defp get_or_create_history(user_id, canvas_id) do
    case Repo.get_by(HistoryEntry, user_id: user_id, canvas_id: canvas_id) do
      nil ->
        {:ok, history} =
          %HistoryEntry{}
          |> HistoryEntry.changeset(%{
            user_id: user_id,
            canvas_id: canvas_id,
            undo_stack: [],
            redo_stack: []
          })
          |> Repo.insert()

        history

      history ->
        history
    end
  end

  defp serialize_object_snapshot(snapshot) when is_map(snapshot) do
    # Ensure consistent JSON-serializable format
    %{
      "id" => snapshot[:id] || snapshot["id"],
      "before" => serialize_state(snapshot[:before] || snapshot["before"]),
      "after" => serialize_state(snapshot[:after] || snapshot["after"])
    }
  end

  defp serialize_state(nil), do: nil

  defp serialize_state(state) when is_map(state) do
    # Convert all keys to strings for JSON compatibility
    state
    |> Enum.map(fn {k, v} -> {to_string(k), v} end)
    |> Enum.into(%{})
  end
end
