defmodule CollabCanvas.Repo.Migrations.AddLockedAtToObjects do
  use Ecto.Migration

  def change do
    alter table(:objects) do
      add(:locked_at, :utc_datetime)
    end

    create(index(:objects, [:locked_at]))
  end
end
