defmodule CollabCanvas.Styles.Style do
  @moduledoc """
  Style schema for the CollabCanvas application.

  Represents a reusable design style (color, text, effect) that can be applied
  to multiple objects on a canvas. Styles support design token export and
  real-time synchronization across collaborators.

  ## Style Types

  - `color` - Color definitions with RGB/RGBA values
  - `text` - Typography styles (font, size, weight, line-height)
  - `effect` - Visual effects (shadow, blur, etc.)

  ## Categories

  Categories help organize styles within their type:
  - Color: primary, secondary, accent, neutral, etc.
  - Text: heading, body, caption, etc.
  - Effect: shadow, blur, etc.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias CollabCanvas.Canvases.Canvas
  alias CollabCanvas.Accounts.User

  @valid_types ~w(color text effect)
  @valid_color_categories ~w(primary secondary accent neutral)
  @valid_text_categories ~w(heading body caption)
  @valid_effect_categories ~w(shadow blur)

  schema "styles" do
    field :name, :string
    field :type, :string
    field :category, :string
    field :definition, :string

    belongs_to :canvas, Canvas
    belongs_to :creator, User, foreign_key: :created_by

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or updating a style.

  ## Required fields
    * `:name` - Style name (e.g., "Primary Blue", "Heading 1")
    * `:type` - Style type (color, text, effect)
    * `:definition` - JSON string containing style properties
    * `:canvas_id` - ID of the canvas this style belongs to

  ## Optional fields
    * `:category` - Style category for organization
    * `:created_by` - User ID who created the style

  ## Validations
    * Name must be present and between 1-255 characters
    * Type must be one of: color, text, effect
    * Definition must be valid JSON
    * Category must be valid for the given type
  """
  def changeset(style, attrs) do
    # Pre-process definition field to handle maps
    attrs = normalize_definition(attrs)

    style
    |> cast(attrs, [:name, :type, :category, :definition, :canvas_id, :created_by])
    |> validate_required([:name, :type, :definition, :canvas_id])
    |> validate_length(:name, min: 1, max: 255)
    |> validate_inclusion(:type, @valid_types)
    |> validate_json_definition()
    |> validate_category()
    |> foreign_key_constraint(:canvas_id, name: "styles_canvas_id_fkey")
    |> foreign_key_constraint(:created_by, name: "styles_created_by_fkey")
    |> unique_constraint([:name, :canvas_id], name: "styles_name_canvas_id_index")
  end

  # Normalize definition field: convert maps to JSON strings
  defp normalize_definition(attrs) when is_map(attrs) do
    cond do
      Map.has_key?(attrs, :definition) ->
        normalize_definition_key(attrs, :definition)

      Map.has_key?(attrs, "definition") ->
        normalize_definition_key(attrs, "definition")

      true ->
        attrs
    end
  end

  defp normalize_definition(attrs), do: attrs

  defp normalize_definition_key(attrs, key) do
    case Map.get(attrs, key) do
      definition when is_map(definition) ->
        case Jason.encode(definition) do
          {:ok, json} ->
            Map.put(attrs, key, json)

          {:error, _} ->
            # Leave as-is, will be caught by validation
            attrs
        end

      definition when is_binary(definition) ->
        # Already a string, keep it as-is (will be validated later)
        attrs

      _ ->
        attrs
    end
  end

  @doc """
  Validates that the definition field contains valid JSON.
  """
  defp validate_json_definition(changeset) do
    case get_change(changeset, :definition) do
      nil ->
        changeset

      definition when is_binary(definition) ->
        case Jason.decode(definition) do
          {:ok, _} ->
            changeset

          {:error, _} ->
            add_error(changeset, :definition, "must be valid JSON")
        end

      _ ->
        add_error(changeset, :definition, "must be a JSON string")
    end
  end

  @doc """
  Validates that the category is appropriate for the style type.
  """
  defp validate_category(changeset) do
    type = get_field(changeset, :type)
    category = get_change(changeset, :category)

    case {type, category} do
      {_, nil} ->
        # Category is optional
        changeset

      {"color", category} ->
        validate_inclusion(changeset, :category, @valid_color_categories)

      {"text", category} ->
        validate_inclusion(changeset, :category, @valid_text_categories)

      {"effect", category} ->
        validate_inclusion(changeset, :category, @valid_effect_categories)

      _ ->
        changeset
    end
  end

  @doc """
  Decodes the JSON definition into a map.
  Returns the parsed map or an empty map if parsing fails.
  """
  def decode_definition(%__MODULE__{definition: definition}) when is_binary(definition) do
    case Jason.decode(definition) do
      {:ok, parsed} -> parsed
      {:error, _} -> %{}
    end
  end

  def decode_definition(_), do: %{}
end
