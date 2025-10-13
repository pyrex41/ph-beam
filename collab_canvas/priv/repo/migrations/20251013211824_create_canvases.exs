defmodule CollabCanvas.Repo.Migrations.CreateCanvases do
  use Ecto.Migration

  def change do
    create table(:canvases) do
      add :name, :string, null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:canvases, [:user_id])
  end
end
