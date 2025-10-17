defmodule CollabCanvas.Canvases.CanvasUserViewport do
  @moduledoc """
  Schema for tracking a user's viewport position and zoom level on a specific canvas.
  This allows users to return to their last viewing position when they reload or revisit a canvas.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias CollabCanvas.Accounts.User
  alias CollabCanvas.Canvases.Canvas

  schema "canvas_user_viewports" do
    field :viewport_x, :float
    field :viewport_y, :float
    field :zoom, :float

    belongs_to :user, User
    belongs_to :canvas, Canvas

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or updating a canvas user viewport.

  ## Fields
    * `:user_id` - ID of the user (required)
    * `:canvas_id` - ID of the canvas (required)
    * `:viewport_x` - X coordinate of viewport center (defaults to 0.0)
    * `:viewport_y` - Y coordinate of viewport center (defaults to 0.0)
    * `:zoom` - Zoom level (defaults to 1.0)
  """
  def changeset(viewport, attrs) do
    viewport
    |> cast(attrs, [:user_id, :canvas_id, :viewport_x, :viewport_y, :zoom])
    |> validate_required([:user_id, :canvas_id, :viewport_x, :viewport_y, :zoom])
    |> validate_number(:zoom, greater_than: 0)
    |> unique_constraint([:user_id, :canvas_id])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:canvas_id)
  end
end
