defmodule CollabCanvas.ColorPalettes do
  @moduledoc """
  The ColorPalettes context.

  Manages user color preferences including recent colors, favorite colors, and default colors.
  """

  import Ecto.Query, warn: false
  alias CollabCanvas.Repo
  alias CollabCanvas.ColorPalettes.UserColorPreference
  alias CollabCanvas.ColorPalettes.Palette
  alias CollabCanvas.ColorPalettes.PaletteColor

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
        {:ok, colors} when is_list(colors) ->
          colors

        {:error, reason} ->
          require Logger

          Logger.warning(
            "Failed to decode favorite colors for user #{user_id}: #{inspect(reason)}"
          )

          []

        _ ->
          []
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
        {:ok, colors} when is_list(colors) ->
          colors

        {:error, reason} ->
          require Logger

          Logger.warning(
            "Failed to decode favorite colors for user #{user_id}: #{inspect(reason)}"
          )

          []

        _ ->
          []
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

  @doc """
  Gets whether the user wants to play error sounds.

  ## Parameters
    * `user_id` - The ID of the user

  ## Returns
    * Boolean

  ## Examples

      iex> get_play_error_sound(1)
      true

  """
  def get_play_error_sound(user_id) do
    preferences = get_or_create_preferences(user_id)
    preferences.play_error_sound
  end

  @doc """
  Sets whether the user wants to play error sounds.

  ## Parameters
    * `user_id` - The ID of the user
    * `enabled` - Boolean value

  ## Returns
    * `{:ok, %UserColorPreference{}}` on success
    * `{:error, reason}` on failure

  ## Examples

      iex> set_play_error_sound(1, false)
      {:ok, %UserColorPreference{}}

  """
  def set_play_error_sound(user_id, enabled) when is_boolean(enabled) do
    preferences = get_or_create_preferences(user_id)
    update_preferences(preferences, %{play_error_sound: enabled})
  end

  # Palette Management Functions

  @doc """
  Creates a new color palette for a user.

  ## Parameters
    * `user_id` - The ID of the user
    * `name` - Name for the palette
    * `colors` - List of hex color strings (optional)

  ## Returns
    * `{:ok, %Palette{}}` on success
    * `{:error, %Ecto.Changeset{}}` on validation failure

  ## Examples

      iex> create_palette(1, "My Palette", ["#FF0000", "#00FF00"])
      {:ok, %Palette{}}

  """
  def create_palette(user_id, name, colors \\ []) do
    Repo.transaction(fn ->
      # Create palette
      {:ok, palette} =
        %Palette{}
        |> Palette.changeset(%{name: name, user_id: user_id})
        |> Repo.insert()

      # Add colors if provided
      if length(colors) > 0 do
        Enum.with_index(colors)
        |> Enum.each(fn {color, index} ->
          add_color_to_palette(palette.id, color, index)
        end)
      end

      # Reload palette with colors
      Repo.preload(palette, :colors, force: true)
    end)
  end

  @doc """
  Adds a color to an existing palette.

  ## Parameters
    * `palette_id` - The ID of the palette
    * `color_hex` - Hex color string
    * `position` - Position in palette (optional, defaults to end)

  ## Returns
    * `{:ok, %PaletteColor{}}` on success
    * `{:error, %Ecto.Changeset{}}` on validation failure

  ## Examples

      iex> add_color_to_palette(palette_id, "#FF0000", 0)
      {:ok, %PaletteColor{}}

  """
  def add_color_to_palette(palette_id, color_hex, position \\ nil) do
    # If position not provided, get next position
    position =
      if is_nil(position) do
        query =
          from pc in PaletteColor,
            where: pc.palette_id == ^palette_id,
            select: max(pc.position)

        (Repo.one(query) || -1) + 1
      else
        position
      end

    %PaletteColor{}
    |> PaletteColor.changeset(%{
      palette_id: palette_id,
      color_hex: color_hex,
      position: position
    })
    |> Repo.insert()
  end

  @doc """
  Lists all palettes for a user.

  ## Parameters
    * `user_id` - The ID of the user

  ## Returns
    * List of palette structs with colors preloaded

  ## Examples

      iex> list_user_palettes(1)
      [%Palette{}, %Palette{}]

  """
  def list_user_palettes(user_id) do
    Palette
    |> where([p], p.user_id == ^user_id)
    |> order_by([p], desc: p.updated_at)
    |> preload(:colors)
    |> Repo.all()
  end

  @doc """
  Gets a single palette with colors.

  ## Parameters
    * `palette_id` - The ID of the palette

  ## Returns
    * `%Palette{}` if found
    * `nil` if not found

  ## Examples

      iex> get_palette(palette_id)
      %Palette{colors: [%PaletteColor{}, ...]}

  """
  def get_palette(palette_id) do
    Palette
    |> where([p], p.id == ^palette_id)
    |> preload(:colors)
    |> Repo.one()
  end

  @doc """
  Updates a palette's name.

  ## Parameters
    * `palette_id` - The ID of the palette
    * `name` - New name for the palette

  ## Returns
    * `{:ok, %Palette{}}` on success
    * `{:error, :not_found}` if palette doesn't exist
    * `{:error, %Ecto.Changeset{}}` on validation failure

  ## Examples

      iex> update_palette(palette_id, "New Name")
      {:ok, %Palette{}}

  """
  def update_palette(palette_id, name) do
    case Repo.get(Palette, palette_id) do
      nil ->
        {:error, :not_found}

      palette ->
        palette
        |> Palette.changeset(%{name: name})
        |> Repo.update()
    end
  end

  @doc """
  Deletes a palette and all its colors.

  ## Parameters
    * `palette_id` - The ID of the palette

  ## Returns
    * `{:ok, %Palette{}}` on success
    * `{:error, :not_found}` if palette doesn't exist

  ## Examples

      iex> delete_palette(palette_id)
      {:ok, %Palette{}}

  """
  def delete_palette(palette_id) do
    case Repo.get(Palette, palette_id) do
      nil ->
        {:error, :not_found}

      palette ->
        Repo.delete(palette)
    end
  end

  @doc """
  Removes a color from a palette.

  ## Parameters
    * `color_id` - The ID of the palette color

  ## Returns
    * `{:ok, %PaletteColor{}}` on success
    * `{:error, :not_found}` if color doesn't exist

  ## Examples

      iex> remove_color_from_palette(color_id)
      {:ok, %PaletteColor{}}

  """
  def remove_color_from_palette(color_id) do
    case Repo.get(PaletteColor, color_id) do
      nil ->
        {:error, :not_found}

      color ->
        Repo.delete(color)
    end
  end
end
