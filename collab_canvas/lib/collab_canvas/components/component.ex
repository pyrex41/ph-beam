defmodule CollabCanvas.Components.Component do
  @moduledoc """
  Component schema for the CollabCanvas application.
  Represents a reusable component that can be instantiated multiple times on canvases.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias CollabCanvas.Canvases.Canvas
  alias CollabCanvas.Accounts.User

  @derive {Jason.Encoder,
           only: [
             :id,
             :name,
             :description,
             :category,
             :canvas_id,
             :created_by,
             :is_published,
             :template_data,
             :inserted_at,
             :updated_at
           ]}
  schema "components" do
    field(:name, :string)
    field(:description, :string)
    field(:category, :string)
    field(:is_published, :boolean, default: false)
    field(:template_data, :string)

    belongs_to(:canvas, Canvas)
    belongs_to(:creator, User, foreign_key: :created_by)

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or updating a component.

  ## Required fields
    * `:name` - Component name
    * `:canvas_id` - ID of the canvas this component belongs to

  ## Optional fields
    * `:description` - Component description
    * `:category` - Component category (e.g., "button", "card", "form")
    * `:created_by` - User ID of the component creator
    * `:is_published` - Whether the component is published for reuse
    * `:template_data` - JSON string containing the component's template data

  ## Validations
    * Name must be present and at least 1 character
    * Canvas ID must be present
    * Category must be one of the allowed categories when present
  """
  def changeset(component, attrs) do
    component
    |> cast(attrs, [
      :name,
      :description,
      :category,
      :canvas_id,
      :created_by,
      :is_published,
      :template_data
    ])
    |> validate_required([:name, :canvas_id])
    |> validate_length(:name, min: 1, max: 255)
    |> validate_inclusion(:category, [
      "button",
      "card",
      "form",
      "navigation",
      "layout",
      "icon",
      "custom"
    ])
    |> foreign_key_constraint(:canvas_id, name: "components_canvas_id_fkey")
    |> foreign_key_constraint(:created_by, name: "components_created_by_fkey")
  end
end
