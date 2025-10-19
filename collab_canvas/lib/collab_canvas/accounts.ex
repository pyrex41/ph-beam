defmodule CollabCanvas.Accounts do
  @moduledoc """
  The Accounts context for managing user account operations in CollabCanvas.

  This module provides a comprehensive API for user account management, including:

  ## User Account Management
  - Creating, reading, updating, and deleting user accounts
  - Listing all users in the system
  - Tracking user metadata such as name, email, and avatar

  ## User Authentication and Retrieval
  - Retrieving users by ID or email address
  - Both soft retrieval (returns `nil` if not found) and strict retrieval (raises exception)
  - Updating last login timestamps for tracking user activity

  ## OAuth Provider Integration (Auth0)
  - Seamless integration with Auth0 OAuth authentication
  - Finding or creating users based on OAuth provider data
  - Support for multiple OAuth providers (Google, Auth0, etc.)
  - Mapping provider-specific fields (sub, picture) to user attributes
  - Automatic user creation on first login via OAuth
  - Provider-specific identifiers for reliable user matching

  ## Database Operations for Users
  - All operations are backed by PostgreSQL via Ecto
  - Uses changesets for data validation and casting
  - Supports transactional operations through Ecto.Repo
  - Handles both successful operations (`{:ok, user}`) and errors (`{:error, changeset}`)

  ## Usage Examples

  Basic user operations:

      # Create a new user
      {:ok, user} = Accounts.create_user(%{
        email: "user@example.com",
        name: "John Doe"
      })

      # Retrieve by ID or email
      user = Accounts.get_user(123)
      user = Accounts.get_user("user@example.com")

      # Update user information
      {:ok, updated_user} = Accounts.update_user(user, %{name: "Jane Doe"})

  OAuth authentication flow:

      # Find or create user from Auth0 data
      {:ok, user} = Accounts.find_or_create_user(%{
        email: "oauth_user@example.com",
        name: "OAuth User",
        picture: "https://example.com/avatar.jpg",
        provider: "google",
        sub: "google-oauth2|123456789"
      })
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
    user =
      if provider_uid do
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
  Updates the last_login timestamp for a user to the current UTC time.

  This function is typically called during authentication to track when a user
  last accessed the system. It accepts either a User struct or a user ID.

  ## Parameters

    * `user` - A `%User{}` struct to update
    * `user_id` - An integer ID of the user to update

  ## Returns

    * `{:ok, %User{}}` - Successfully updated user with new last_login timestamp
    * `{:error, %Ecto.Changeset{}}` - Validation or database error
    * `{:error, :not_found}` - User with the given ID does not exist

  ## Examples

      # Update using User struct
      iex> update_last_login(user)
      {:ok, %User{last_login: ~U[2024-01-15 10:30:00Z]}}

      # Update using user ID
      iex> update_last_login(123)
      {:ok, %User{last_login: ~U[2024-01-15 10:30:00Z]}}

      # Non-existent user
      iex> update_last_login(999)
      {:error, :not_found}

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
