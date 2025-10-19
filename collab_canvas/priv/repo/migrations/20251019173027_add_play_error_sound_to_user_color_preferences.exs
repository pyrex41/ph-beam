defmodule CollabCanvas.Repo.Migrations.AddPlayErrorSoundToUserColorPreferences do
  use Ecto.Migration

  def change do
    alter table(:user_color_preferences) do
      add :play_error_sound, :boolean, default: true, null: false
    end
  end
end
