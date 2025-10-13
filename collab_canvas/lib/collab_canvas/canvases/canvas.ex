defmodule CollabCanvas.Canvases.Canvas do
  @moduledoc """
  Canvas schema for the CollabCanvas application.
  Represents a collaborative canvas workspace owned by a user.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias CollabCanvas.Accounts.User
  alias CollabCanvas.Canvases.Object

  schema "canvases" do
    field :name, :string

    belongs_to :user, User
    has_many :objects, Object

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or updating a canvas.

  ## Required fields
    * `:name` - Canvas name/title
    * `:user_id` - ID of the user who owns this canvas

  ## Validations
    * Name must be present and between 1-255 characters
    * User ID must be present
  """
  def changeset(canvas, attrs) do
    canvas
    |> cast(attrs, [:name, :user_id])
    |> validate_required([:name, :user_id])
    |> validate_length(:name, min: 1, max: 255)
    |> foreign_key_constraint(:user_id, name: "canvases_user_id_fkey")
  end
end
