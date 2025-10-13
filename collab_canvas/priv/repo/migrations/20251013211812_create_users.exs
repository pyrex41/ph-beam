defmodule CollabCanvas.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :email, :string, null: false
      add :name, :string
      add :avatar, :text
      add :provider, :string
      add :provider_uid, :string
      add :last_login, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:email])
    create unique_index(:users, [:provider, :provider_uid])
  end
end
