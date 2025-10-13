defmodule CollabCanvas.Accounts.User do
  @moduledoc """
  User schema for the CollabCanvas application.
  Represents authenticated users with OAuth provider information.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :email, :string
    field :name, :string
    field :avatar, :string
    field :provider, :string
    field :provider_uid, :string
    field :last_login, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or updating a user.

  ## Required fields
    * `:email` - Must be a valid email format and unique

  ## Optional fields
    * `:name` - User's display name
    * `:avatar` - URL to user's avatar image
    * `:provider` - OAuth provider name (e.g., "auth0", "google", "github")
    * `:provider_uid` - Unique identifier from the OAuth provider
    * `:last_login` - Timestamp of user's last login
  """
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :name, :avatar, :provider, :provider_uid, :last_login])
    |> validate_required([:email])
    |> validate_email()
    |> unique_constraint(:email)
    |> unique_constraint([:provider, :provider_uid])
  end

  @doc """
  Changeset specifically for updating last login timestamp.
  Only allows updating the last_login field.
  """
  def login_changeset(user, attrs) do
    user
    |> cast(attrs, [:last_login])
    |> validate_required([:last_login])
  end

  # Private helper to validate email format
  defp validate_email(changeset) do
    changeset
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must be a valid email address")
    |> validate_length(:email, max: 160)
  end
end
