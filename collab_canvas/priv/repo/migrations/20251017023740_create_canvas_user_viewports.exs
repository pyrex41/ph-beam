defmodule CollabCanvas.Repo.Migrations.CreateCanvasUserViewports do
  use Ecto.Migration

  def change do
    create table(:canvas_user_viewports) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :canvas_id, references(:canvases, on_delete: :delete_all), null: false
      add :viewport_x, :float, null: false, default: 0.0
      add :viewport_y, :float, null: false, default: 0.0
      add :zoom, :float, null: false, default: 1.0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:canvas_user_viewports, [:user_id, :canvas_id])
    create index(:canvas_user_viewports, [:canvas_id])
  end
end
