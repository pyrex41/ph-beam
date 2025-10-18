defmodule CollabCanvas.Repo.Migrations.CreatePalettes do
  use Ecto.Migration

  def change do
    create table(:palettes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :user_id, references(:users, on_delete: :delete_all, type: :binary_id), null: false

      timestamps(type: :utc_datetime)
    end

    create table(:palette_colors, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :palette_id, references(:palettes, on_delete: :delete_all, type: :binary_id), null: false
      add :color_hex, :string, null: false
      add :position, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:palettes, [:user_id])
    create index(:palette_colors, [:palette_id])
  end
end
