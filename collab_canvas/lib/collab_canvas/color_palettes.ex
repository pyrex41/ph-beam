defmodule CollabCanvas.ColorPalettes do
  @moduledoc """
  The ColorPalettes context.

  Manages user color preferences including recent colors, favorite colors, and default colors.
  """

  import Ecto.Query, warn: false
  alias CollabCanvas.Repo
  alias CollabCanvas.ColorPalettes.UserColorPreference

  @doc """
  Gets user color preferences for a specific user.
  Creates default preferences if none exist.

  ## Parameters
    * `user_id` - The ID of the user

  ## Returns
    * `%UserColorPreference{}` - The user's color preferences

  ## Examples

      iex> get_or_create_preferences(1)
      %UserColorPreference{user_id: 1, recent_colors: "[]", ...}

  """
  def get_or_create_preferences(user_id) do
    case Repo.get_by(UserColorPreference, user_id: user_id) do
      nil ->
        # Create default preferences
        {:ok, preferences} = create_preferences(%{user_id: user_id})
        preferences

      preferences ->
        preferences
    end
  end

  @doc """
  Gets user color preferences by user ID.

  ## Parameters
    * `user_id` - The ID of the user

  ## Returns
    * `%UserColorPreference{}` if found
    * `nil` if not found

  ## Examples

      iex> get_preferences(1)
      %UserColorPreference{}

      iex> get_preferences(999)
      nil

  """
  def get_preferences(user_id) do
    Repo.get_by(UserColorPreference, user_id: user_id)
  end

  @doc """
  Creates user color preferences.

  ## Parameters
    * `attrs` - Map of attributes including :user_id

  ## Returns
    * `{:ok, %UserColorPreference{}}` on success
    * `{:error, %Ecto.Changeset{}}` on validation failure

  ## Examples

      iex> create_preferences(%{user_id: 1})
      {:ok, %UserColorPreference{}}

      iex> create_preferences(%{})
      {:error, %Ecto.Changeset{}}

  """
  def create_preferences(attrs \\ %{}) do
    %UserColorPreference{}
    |> UserColorPreference.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates user color preferences.

  ## Parameters
    * `preference` - The preference struct to update
    * `attrs` - Map of attributes to update

  ## Returns
    * `{:ok, %UserColorPreference{}}` on success
    * `{:error, %Ecto.Changeset{}}` on validation failure

  ## Examples

      iex> update_preferences(preference, %{default_color: "#FF0000"})
      {:ok, %UserColorPreference{}}

  """
  def update_preferences(%UserColorPreference{} = preference, attrs) do
    preference
    |> UserColorPreference.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Adds a color to the user's recent colors list.
  Automatically manages the LIFO queue (max 8 colors).

  ## Parameters
    * `user_id` - The ID of the user
    * `color` - Hex color string (e.g., "#FF0000")

  ## Returns
    * `{:ok, %UserColorPreference{}}` on success
    * `{:error, reason}` on failure

  ## Examples

      iex> add_recent_color(1, "#FF0000")
      {:ok, %UserColorPreference{}}

  """
  def add_recent_color(user_id, color) when is_binary(color) do
    preferences = get_or_create_preferences(user_id)
    updated_recent_colors = UserColorPreference.add_to_recent(preferences.recent_colors, color)

    update_preferences(preferences, %{recent_colors: updated_recent_colors})
  end

  @doc """
  Adds a color to the user's favorite colors list.

  ## Parameters
    * `user_id` - The ID of the user
    * `color` - Hex color string (e.g., "#FF0000")

  ## Returns
    * `{:ok, %UserColorPreference{}}` on success
    * `{:error, reason}` on failure

  ## Examples

      iex> add_favorite_color(1, "#FF0000")
      {:ok, %UserColorPreference{}}

  """
  def add_favorite_color(user_id, color) when is_binary(color) do
    preferences = get_or_create_preferences(user_id)

    favorite_colors =
      case Jason.decode(preferences.favorite_colors) do
        {:ok, colors} when is_list(colors) -> colors
        {:error, reason} ->
          require Logger
          Logger.warning("Failed to decode favorite colors for user #{user_id}: #{inspect(reason)}")
          []
        _ -> []
      end

    # Don't add duplicates
    if color in favorite_colors do
      {:ok, preferences}
    else
      # Check if we've reached the maximum favorite colors limit
      max_favorites = 20

      if length(favorite_colors) >= max_favorites do
        {:error, :max_favorites_reached}
      else
        updated_favorites = Jason.encode!([color | favorite_colors])
        update_preferences(preferences, %{favorite_colors: updated_favorites})
      end
    end
  end

  @doc """
  Removes a color from the user's favorite colors list.

  ## Parameters
    * `user_id` - The ID of the user
    * `color` - Hex color string to remove

  ## Returns
    * `{:ok, %UserColorPreference{}}` on success
    * `{:error, reason}` on failure

  ## Examples

      iex> remove_favorite_color(1, "#FF0000")
      {:ok, %UserColorPreference{}}

  """
  def remove_favorite_color(user_id, color) when is_binary(color) do
    preferences = get_or_create_preferences(user_id)

    favorite_colors =
      case Jason.decode(preferences.favorite_colors) do
        {:ok, colors} when is_list(colors) -> colors
        {:error, reason} ->
          require Logger
          Logger.warning("Failed to decode favorite colors for user #{user_id}: #{inspect(reason)}")
          []
        _ -> []
      end

    updated_favorites =
      favorite_colors
      |> Enum.reject(&(&1 == color))
      |> Jason.encode!()

    update_preferences(preferences, %{favorite_colors: updated_favorites})
  end

  @doc """
  Sets the user's default color for new objects.

  ## Parameters
    * `user_id` - The ID of the user
    * `color` - Hex color string

  ## Returns
    * `{:ok, %UserColorPreference{}}` on success
    * `{:error, reason}` on failure

  ## Examples

      iex> set_default_color(1, "#0000FF")
      {:ok, %UserColorPreference{}}

  """
  def set_default_color(user_id, color) when is_binary(color) do
    preferences = get_or_create_preferences(user_id)
    update_preferences(preferences, %{default_color: color})
  end

  @doc """
  Gets the user's recent colors as a list.

  ## Parameters
    * `user_id` - The ID of the user

  ## Returns
    * List of hex color strings

  ## Examples

      iex> get_recent_colors(1)
      ["#FF0000", "#00FF00", "#0000FF"]

  """
  def get_recent_colors(user_id) do
    preferences = get_or_create_preferences(user_id)
    UserColorPreference.decode_recent_colors(preferences)
  end

  @doc """
  Gets the user's favorite colors as a list.

  ## Parameters
    * `user_id` - The ID of the user

  ## Returns
    * List of hex color strings

  ## Examples

      iex> get_favorite_colors(1)
      ["#FF0000", "#00FF00"]

  """
  def get_favorite_colors(user_id) do
    preferences = get_or_create_preferences(user_id)
    UserColorPreference.decode_favorite_colors(preferences)
  end

  @doc """
  Gets the user's default color.

  ## Parameters
    * `user_id` - The ID of the user

  ## Returns
    * Hex color string

  ## Examples

      iex> get_default_color(1)
      "#000000"

  """
  def get_default_color(user_id) do
    preferences = get_or_create_preferences(user_id)
    preferences.default_color
  end
end
