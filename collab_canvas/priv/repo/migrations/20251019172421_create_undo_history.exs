defmodule CollabCanvas.Repo.Migrations.CreateUndoHistory do
  use Ecto.Migration

  def change do
    create table(:undo_history) do
      add :user_id, :string, null: false
      add :canvas_id, references(:canvases, on_delete: :delete_all), null: false
      add :undo_stack, :jsonb, default: "[]", null: false
      add :redo_stack, :jsonb, default: "[]", null: false

      timestamps()
    end

    create unique_index(:undo_history, [:user_id, :canvas_id])
    create index(:undo_history, [:canvas_id])
  end
end
