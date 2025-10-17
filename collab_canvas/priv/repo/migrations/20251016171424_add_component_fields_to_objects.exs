defmodule CollabCanvas.Repo.Migrations.AddComponentFieldsToObjects do
  use Ecto.Migration

  def change do
    alter table(:objects) do
      add :component_id, references(:components, on_delete: :nilify_all)
      add :is_main_component, :boolean, default: false, null: false
      add :instance_overrides, :text
    end

    create index(:objects, [:component_id])
  end
end
