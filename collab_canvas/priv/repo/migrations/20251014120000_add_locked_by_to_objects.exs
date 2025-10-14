defmodule CollabCanvas.Repo.Migrations.AddLockedByToObjects do
  use Ecto.Migration

  def change do
    alter table(:objects) do
      add(:locked_by, :string)
    end

    create(index(:objects, [:locked_by]))
  end
end
