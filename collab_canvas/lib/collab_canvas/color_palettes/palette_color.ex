defmodule CollabCanvas.ColorPalettes.PaletteColor do
  @moduledoc """
  PaletteColor schema for storing individual colors within a palette.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias CollabCanvas.ColorPalettes.Palette

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @derive {Jason.Encoder,
           only: [:id, :palette_id, :color_hex, :position, :inserted_at, :updated_at]}
  schema "palette_colors" do
    field :color_hex, :string
    field :position, :integer

    belongs_to :palette, Palette

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or updating a palette color.

  ## Required fields
    * `:color_hex` - Hex color code (e.g., "#FF0000")
    * `:position` - Position in palette (0-indexed)
    * `:palette_id` - ID of the parent palette

  ## Validations
    * Color hex must be a valid hex color code
    * Position must be a non-negative integer
    * Palette ID must be present
  """
  def changeset(palette_color, attrs) do
    palette_color
    |> cast(attrs, [:color_hex, :position, :palette_id])
    |> validate_required([:color_hex, :position, :palette_id])
    |> validate_format(:color_hex, ~r/^#[0-9A-Fa-f]{6}$/,
      message: "must be a valid hex color code (e.g., #FF0000)"
    )
    |> validate_number(:position, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:palette_id)
  end
end
