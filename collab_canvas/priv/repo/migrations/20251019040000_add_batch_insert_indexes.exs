defmodule CollabCanvas.Repo.Migrations.AddBatchInsertIndexes do
  use Ecto.Migration

  @moduledoc """
  Adds database indexes to optimize batch object insertion performance.

  These indexes support the create_objects_batch/2 function which can create
  up to 600 objects in a single transaction for AI-powered canvas features.

  Performance targets:
  - 100 objects in <1s
  - 500 objects in <2s
  - 600 objects for demo scenarios
  """

  def up do
    # Composite index for canvas_id + z_index (used in list_objects ordering)
    # Speeds up queries like: ORDER BY z_index when filtering by canvas_id
    create_if_not_exists index(:objects, [:canvas_id, :z_index])

    # Index on group_id for group operations
    # Speeds up queries that filter/update objects by group_id
    create_if_not_exists index(:objects, [:group_id])

    # Index on type for AI queries that filter by object type
    # Speeds up queries like: WHERE type = 'rectangle'
    create_if_not_exists index(:objects, [:type])

    # Composite index for canvas_id + inserted_at (insertion order)
    # Helps with temporal queries and batch operation tracking
    create_if_not_exists index(:objects, [:canvas_id, :inserted_at])
  end

  def down do
    drop_if_exists index(:objects, [:canvas_id, :inserted_at])
    drop_if_exists index(:objects, [:type])
    drop_if_exists index(:objects, [:group_id])
    drop_if_exists index(:objects, [:canvas_id, :z_index])
  end
end
