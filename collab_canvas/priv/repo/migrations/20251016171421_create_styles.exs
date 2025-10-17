defmodule CollabCanvas.Repo.Migrations.CreateStyles do
  use Ecto.Migration

  def change do
    create table(:styles) do
      add :name, :string, null: false
      add :type, :string, null: false
      add :category, :string
      add :definition, :text, null: false
      add :canvas_id, references(:canvases, on_delete: :delete_all), null: false
      add :created_by, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:styles, [:canvas_id])
    create index(:styles, [:created_by])
    create index(:styles, [:type])
    create index(:styles, [:category])
  end
end
