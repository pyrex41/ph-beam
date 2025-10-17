defmodule CollabCanvas.ColorPalettes.UserColorPreference do
  @moduledoc """
  Schema for user color preferences.

  Tracks a user's color history, favorites, and default color for canvas objects.
  Each user can have:
  - Up to 8 recent colors (automatically managed LIFO queue)
  - Unlimited favorite colors (manually pinned)
  - One default color for new objects
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias CollabCanvas.Accounts.User

  @max_recent_colors 8

  schema "user_color_preferences" do
    belongs_to :user, User
    field :recent_colors, :string, default: "[]"  # JSON array of hex colors
    field :favorite_colors, :string, default: "[]"  # JSON array of hex colors
    field :default_color, :string, default: "#000000"

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for user color preferences.

  Validates:
  - user_id is required
  - recent_colors is valid JSON array with max 8 hex color strings
  - favorite_colors is valid JSON array of hex color strings
  - default_color is a valid hex color string
  """
  def changeset(preference, attrs) do
    preference
    |> cast(attrs, [:user_id, :recent_colors, :favorite_colors, :default_color])
    |> validate_required([:user_id])
    |> validate_color_format(:default_color)
    |> validate_json_color_array(:recent_colors, @max_recent_colors)
    |> validate_json_color_array(:favorite_colors)
    |> unique_constraint(:user_id)
  end

  # Validates that a field contains a valid hex color (#RRGGBB or #RRGGBBAA)
  defp validate_color_format(changeset, field) do
    validate_change(changeset, field, fn ^field, value ->
      if valid_hex_color?(value) do
        []
      else
        [{field, "must be a valid hex color (#RRGGBB or #RRGGBBAA)"}]
      end
    end)
  end

  # Validates that a field contains a valid JSON array of hex colors
  defp validate_json_color_array(changeset, field, max_count \\ nil) do
    validate_change(changeset, field, fn ^field, value ->
      case Jason.decode(value) do
        {:ok, colors} when is_list(colors) ->
          cond do
            max_count && length(colors) > max_count ->
              [{field, "can contain at most #{max_count} colors"}]

            not Enum.all?(colors, &valid_hex_color?/1) ->
              [{field, "must contain only valid hex colors"}]

            true ->
              []
          end

        {:ok, _} ->
          [{field, "must be a JSON array"}]

        {:error, _} ->
          [{field, "must be valid JSON"}]
      end
    end)
  end

  # Checks if a string is a valid hex color
  defp valid_hex_color?(color) when is_binary(color) do
    Regex.match?(~r/^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$/, color)
  end

  defp valid_hex_color?(_), do: false

  @doc """
  Decodes recent colors from JSON string to list.
  """
  def decode_recent_colors(preference) do
    case Jason.decode(preference.recent_colors) do
      {:ok, colors} -> colors
      {:error, _} -> []
    end
  end

  @doc """
  Decodes favorite colors from JSON string to list.
  """
  def decode_favorite_colors(preference) do
    case Jason.decode(preference.favorite_colors) do
      {:ok, colors} -> colors
      {:error, _} -> []
    end
  end

  @doc """
  Adds a color to recent colors (LIFO queue with max 8 items).
  Removes duplicates and moves existing color to front.
  """
  def add_to_recent(recent_colors_json, new_color) when is_binary(recent_colors_json) and is_binary(new_color) do
    recent_colors =
      case Jason.decode(recent_colors_json) do
        {:ok, colors} when is_list(colors) -> colors
        _ -> []
      end

    # Remove existing instance of this color and prepend it
    updated_colors =
      [new_color | Enum.reject(recent_colors, &(&1 == new_color))]
      |> Enum.take(@max_recent_colors)

    Jason.encode!(updated_colors)
  end
end
