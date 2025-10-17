defmodule CollabCanvas.Repo.Migrations.CreateUserColorPreferences do
  use Ecto.Migration

  def change do
    create table(:user_color_preferences) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :recent_colors, :text, default: "[]", null: false  # JSON array of up to 8 recent hex colors
      add :favorite_colors, :text, default: "[]", null: false  # JSON array of pinned favorite hex colors
      add :default_color, :string, default: "#000000", null: false  # Default color for new objects

      timestamps(type: :utc_datetime)
    end

    create unique_index(:user_color_preferences, [:user_id])
  end
end
