defmodule CollabCanvas.Repo.Migrations.CreateObjects do
  use Ecto.Migration

  def change do
    create table(:objects) do
      add :canvas_id, references(:canvases, on_delete: :delete_all), null: false
      add :type, :string, null: false
      add :data, :text
      add :position, :map

      timestamps(type: :utc_datetime)
    end

    create index(:objects, [:canvas_id])
  end
end
