defmodule CollabCanvas.Repo.Migrations.CreateComponents do
  use Ecto.Migration

  def change do
    create table(:components) do
      add :name, :string, null: false
      add :description, :text
      add :category, :string
      add :canvas_id, references(:canvases, on_delete: :delete_all), null: false
      add :created_by, references(:users, on_delete: :nilify_all)
      add :is_published, :boolean, default: false, null: false
      add :template_data, :text

      timestamps(type: :utc_datetime)
    end

    create index(:components, [:canvas_id])
    create index(:components, [:created_by])
    create index(:components, [:category])
  end
end
