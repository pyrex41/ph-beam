defmodule CollabCanvas.Repo.Migrations.AddGroupIdAndZIndexToObjects do
  use Ecto.Migration

  def change do
    alter table(:objects) do
      add :group_id, :uuid
      add :z_index, :float, default: 0.0
    end

    create index(:objects, [:group_id])
    create index(:objects, [:z_index])
  end
end
