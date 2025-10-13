defmodule CollabCanvas.Accounts do
  @moduledoc """
  The Accounts context for managing users.
  Handles user creation, authentication, and retrieval operations.
  """

  import Ecto.Query, warn: false
  alias CollabCanvas.Repo
  alias CollabCanvas.Accounts.User

  @doc """
  Returns the list of users.

  ## Examples

      iex> list_users()
      [%User{}, ...]

  """
  def list_users do
    Repo.all(User)
  end

  @doc """
  Gets a single user by ID or email.

  Returns `nil` if the User does not exist.

  ## Examples

      iex> get_user(123)
      %User{}

      iex> get_user("user@example.com")
      %User{}

      iex> get_user(456)
      nil

  """
  def get_user(id) when is_integer(id) do
    Repo.get(User, id)
  end

  def get_user(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a single user by ID or email, raises if not found.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id) when is_integer(id) do
    Repo.get!(User, id)
  end

  def get_user!(email) when is_binary(email) do
    Repo.get_by!(User, email: email)
  end

  @doc """
  Creates a user.

  ## Examples

      iex> create_user(%{email: "user@example.com", name: "John Doe"})
      {:ok, %User{}}

      iex> create_user(%{email: "invalid"})
      {:error, %Ecto.Changeset{}}

  """
  def create_user(attrs \\ %{}) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a user.

  ## Examples

      iex> update_user(user, %{name: "Jane Doe"})
      {:ok, %User{}}

      iex> update_user(user, %{email: nil})
      {:error, %Ecto.Changeset{}}

  """
  def update_user(%User{} = user, attrs) do
    user
    |> User.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a user.

  ## Examples

      iex> delete_user(user)
      {:ok, %User{}}

      iex> delete_user(user)
      {:error, %Ecto.Changeset{}}

  """
  def delete_user(%User{} = user) do
    Repo.delete(user)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user changes.

  ## Examples

      iex> change_user(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user(%User{} = user, attrs \\ %{}) do
    User.changeset(user, attrs)
  end

  @doc """
  Finds or creates a user based on Auth0 provider data.

  This function is used during OAuth authentication to either find an existing
  user or create a new one based on the provider information.

  ## Parameters

    * `auth_data` - Map containing user data from Auth0 with keys:
      * `:email` - User's email address (required)
      * `:name` - User's display name (optional)
      * `:avatar` or `:picture` - User's avatar URL (optional)
      * `:provider` - OAuth provider name (e.g., "auth0", "google")
      * `:provider_uid` or `:sub` - Unique identifier from the provider

  ## Examples

      iex> find_or_create_user(%{
      ...>   email: "user@example.com",
      ...>   name: "John Doe",
      ...>   picture: "https://example.com/avatar.jpg",
      ...>   provider: "google",
      ...>   sub: "google-oauth2|123456"
      ...> })
      {:ok, %User{}}

  """
  def find_or_create_user(auth_data) do
    # Normalize Auth0 data structure
    provider = Map.get(auth_data, :provider, "auth0")
    provider_uid = Map.get(auth_data, :provider_uid) || Map.get(auth_data, :sub)
    email = Map.get(auth_data, :email)
    name = Map.get(auth_data, :name)
    avatar = Map.get(auth_data, :avatar) || Map.get(auth_data, :picture)

    # Try to find existing user by provider_uid first (more reliable)
    user = if provider_uid do
      Repo.get_by(User, provider: provider, provider_uid: provider_uid)
    else
      nil
    end

    # Fall back to email lookup if provider_uid not found
    user = user || Repo.get_by(User, email: email)

    case user do
      nil ->
        # Create new user
        create_user(%{
          email: email,
          name: name,
          avatar: avatar,
          provider: provider,
          provider_uid: provider_uid,
          last_login: DateTime.utc_now()
        })

      existing_user ->
        # Update last login for existing user
        update_last_login(existing_user)
    end
  end

  @doc """
  Updates the last_login timestamp for a user.

  ## Examples

      iex> update_last_login(user)
      {:ok, %User{}}

  """
  def update_last_login(%User{} = user) do
    user
    |> User.login_changeset(%{last_login: DateTime.utc_now()})
    |> Repo.update()
  end

  def update_last_login(user_id) when is_integer(user_id) do
    case get_user(user_id) do
      nil -> {:error, :not_found}
      user -> update_last_login(user)
    end
  end
end
