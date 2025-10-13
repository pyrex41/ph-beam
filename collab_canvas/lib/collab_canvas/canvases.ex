defmodule CollabCanvas.Canvases do
  @moduledoc """
  The Canvases context.
  Handles business logic for canvas and object management.
  """

  import Ecto.Query, warn: false
  alias CollabCanvas.Repo

  alias CollabCanvas.Canvases.Canvas
  alias CollabCanvas.Canvases.Object

  @doc """
  Creates a new canvas for a user.

  ## Parameters
    * `user_id` - The ID of the user creating the canvas
    * `name` - The name of the canvas

  ## Returns
    * `{:ok, canvas}` on success
    * `{:error, changeset}` on validation failure

  ## Examples

      iex> create_canvas(1, "My Canvas")
      {:ok, %Canvas{}}

      iex> create_canvas(1, "")
      {:error, %Ecto.Changeset{}}

  """
  def create_canvas(user_id, name) do
    %Canvas{}
    |> Canvas.changeset(%{user_id: user_id, name: name})
    |> Repo.insert()
  end

  @doc """
  Gets a single canvas by ID.

  ## Parameters
    * `id` - The canvas ID

  ## Returns
    * The canvas struct if found
    * `nil` if not found

  ## Examples

      iex> get_canvas(123)
      %Canvas{}

      iex> get_canvas(456)
      nil

  """
  def get_canvas(id) do
    Repo.get(Canvas, id)
  end

  @doc """
  Gets a single canvas by ID and preloads associations.

  ## Parameters
    * `id` - The canvas ID
    * `preloads` - List of associations to preload (default: [:user, :objects])

  ## Returns
    * The canvas struct with preloaded associations if found
    * `nil` if not found

  ## Examples

      iex> get_canvas_with_preloads(123)
      %Canvas{user: %User{}, objects: [%Object{}]}

      iex> get_canvas_with_preloads(123, [:objects])
      %Canvas{objects: [%Object{}]}

  """
  def get_canvas_with_preloads(id, preloads \\ [:user, :objects]) do
    case get_canvas(id) do
      nil -> nil
      canvas -> Repo.preload(canvas, preloads)
    end
  end

  @doc """
  Lists all canvases for a specific user.

  ## Parameters
    * `user_id` - The user ID

  ## Returns
    * List of canvas structs

  ## Examples

      iex> list_user_canvases(1)
      [%Canvas{}, %Canvas{}]

      iex> list_user_canvases(999)
      []

  """
  def list_user_canvases(user_id) do
    Canvas
    |> where([c], c.user_id == ^user_id)
    |> order_by([c], desc: c.updated_at)
    |> Repo.all()
  end

  @doc """
  Creates a new object on a canvas.

  ## Parameters
    * `canvas_id` - The ID of the canvas
    * `type` - The object type (e.g., "rectangle", "circle")
    * `attrs` - Additional attributes (data, position)

  ## Returns
    * `{:ok, object}` on success
    * `{:error, changeset}` on validation failure

  ## Examples

      iex> create_object(1, "rectangle", %{position: %{x: 10, y: 20}})
      {:ok, %Object{}}

      iex> create_object(1, "invalid_type", %{})
      {:error, %Ecto.Changeset{}}

  """
  def create_object(canvas_id, type, attrs \\ %{}) do
    attrs =
      attrs
      |> Map.put(:canvas_id, canvas_id)
      |> Map.put(:type, type)

    %Object{}
    |> Object.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an existing object.

  ## Parameters
    * `id` - The object ID
    * `attrs` - Map of attributes to update

  ## Returns
    * `{:ok, object}` on success
    * `{:error, changeset}` on validation failure
    * `{:error, :not_found}` if object doesn't exist

  ## Examples

      iex> update_object(1, %{position: %{x: 100, y: 200}})
      {:ok, %Object{}}

      iex> update_object(999, %{position: %{x: 100, y: 200}})
      {:error, :not_found}

  """
  def update_object(id, attrs) do
    case Repo.get(Object, id) do
      nil ->
        {:error, :not_found}

      object ->
        object
        |> Object.changeset(attrs)
        |> Repo.update()
    end
  end

  @doc """
  Deletes an object.

  ## Parameters
    * `id` - The object ID

  ## Returns
    * `{:ok, object}` on success
    * `{:error, :not_found}` if object doesn't exist

  ## Examples

      iex> delete_object(1)
      {:ok, %Object{}}

      iex> delete_object(999)
      {:error, :not_found}

  """
  def delete_object(id) do
    case Repo.get(Object, id) do
      nil ->
        {:error, :not_found}

      object ->
        Repo.delete(object)
    end
  end

  @doc """
  Lists all objects for a specific canvas.

  ## Parameters
    * `canvas_id` - The canvas ID

  ## Returns
    * List of object structs

  ## Examples

      iex> list_objects(1)
      [%Object{}, %Object{}]

      iex> list_objects(999)
      []

  """
  def list_objects(canvas_id) do
    Object
    |> where([o], o.canvas_id == ^canvas_id)
    |> order_by([o], asc: o.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets a single object by ID.

  ## Parameters
    * `id` - The object ID

  ## Returns
    * The object struct if found
    * `nil` if not found

  ## Examples

      iex> get_object(1)
      %Object{}

      iex> get_object(999)
      nil

  """
  def get_object(id) do
    Repo.get(Object, id)
  end

  @doc """
  Deletes all objects from a canvas.

  ## Parameters
    * `canvas_id` - The canvas ID

  ## Returns
    * `{count, nil}` where count is the number of deleted objects

  ## Examples

      iex> delete_canvas_objects(1)
      {5, nil}

  """
  def delete_canvas_objects(canvas_id) do
    Object
    |> where([o], o.canvas_id == ^canvas_id)
    |> Repo.delete_all()
  end

  @doc """
  Deletes a canvas and all its objects.

  ## Parameters
    * `id` - The canvas ID

  ## Returns
    * `{:ok, canvas}` on success
    * `{:error, :not_found}` if canvas doesn't exist

  ## Examples

      iex> delete_canvas(1)
      {:ok, %Canvas{}}

      iex> delete_canvas(999)
      {:error, :not_found}

  """
  def delete_canvas(id) do
    case Repo.get(Canvas, id) do
      nil ->
        {:error, :not_found}

      canvas ->
        # Objects will be deleted automatically due to on_delete: :delete_all
        Repo.delete(canvas)
    end
  end
end
