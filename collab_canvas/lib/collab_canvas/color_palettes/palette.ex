defmodule CollabCanvas.ColorPalettes.Palette do
  @moduledoc """
  Palette schema for storing reusable color palettes.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias CollabCanvas.Accounts.User
  alias CollabCanvas.ColorPalettes.PaletteColor

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @derive {Jason.Encoder, only: [:id, :name, :user_id, :colors, :inserted_at, :updated_at]}
  schema "palettes" do
    field :name, :string

    belongs_to :user, User
    has_many :colors, PaletteColor, foreign_key: :palette_id, on_delete: :delete_all

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or updating a palette.

  ## Required fields
    * `:name` - Palette name
    * `:user_id` - ID of the user who owns this palette

  ## Validations
    * Name must be present and between 1-100 characters
    * User ID must be present
  """
  def changeset(palette, attrs) do
    palette
    |> cast(attrs, [:name, :user_id])
    |> validate_required([:name, :user_id])
    |> validate_length(:name, min: 1, max: 100)
    |> foreign_key_constraint(:user_id)
  end
end
