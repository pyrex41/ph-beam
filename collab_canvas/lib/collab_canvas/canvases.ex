defmodule CollabCanvas.Canvases do
  @moduledoc """
  The Canvases context.

  This module provides the business logic layer for managing canvases and objects
  in the CollabCanvas application. It serves as the primary interface between
  Phoenix controllers/LiveViews and the database layer.

  ## Canvas and Object Management

  A canvas represents a collaborative drawing workspace that belongs to a user.
  Each canvas can contain multiple objects (shapes like rectangles, circles, etc.)
  that can be manipulated by multiple users in real-time.

  ### Canvas Operations
  - Create canvases for users
  - List canvases (per-user or all canvases for collaboration)
  - Retrieve single canvases with optional preloading
  - Delete canvases (cascades to all objects)

  ### Object Operations
  - Create objects on canvases
  - Update object properties (position, data, etc.)
  - Delete individual objects or all objects on a canvas
  - List objects for a specific canvas

  ## Database Operations (CRUD)

  All functions in this context follow standard CRUD patterns:
  - **Create**: Returns `{:ok, struct}` or `{:error, changeset}`
  - **Read**: Returns struct or `nil` for single records, list for multiple
  - **Update**: Returns `{:ok, struct}` or `{:error, changeset}` or `{:error, :not_found}`
  - **Delete**: Returns `{:ok, struct}` or `{:error, :not_found}`

  ## Relationship Between Canvases and Objects

  Canvases and objects have a parent-child relationship:
  - A canvas has many objects (one-to-many)
  - An object belongs to exactly one canvas
  - When a canvas is deleted, all its objects are automatically deleted
    via `on_delete: :delete_all` in the schema definition

  Database integrity:
  - Canvas deletion cascades to objects
  - Objects cannot exist without a valid canvas (foreign key constraint)
  - User deletion cascades to canvases (and transitively to objects)

  ## Preloading Strategies

  This context provides flexible preloading for associations:

  ### Canvas Preloading
  - `get_canvas/1`: No preloading (lightweight)
  - `get_canvas_with_preloads/2`: Selective preloading
    - Default: preloads both `:user` and `:objects`
    - Custom: pass list of associations to preload (e.g., `[:objects]`)
  - `list_all_canvases/0`: Automatically preloads `:user`

  ### Performance Considerations
  - Use `get_canvas/1` when you only need canvas data
  - Use `get_canvas_with_preloads/2` when you need related data
  - Specify only needed associations to minimize database queries
  - Objects are ordered by insertion time, canvases by update time

  ## Usage Examples

      # Create a canvas and add objects
      {:ok, canvas} = create_canvas(user_id, "My Drawing")
      {:ok, rect} = create_object(canvas.id, "rectangle", %{
        position: %{x: 10, y: 20},
        data: %{width: 100, height: 50}
      })

      # Retrieve canvas with all objects
      canvas = get_canvas_with_preloads(canvas.id)
      # Returns: %Canvas{objects: [...], user: %User{}}

      # Update object position during drag
      {:ok, updated} = update_object(rect.id, %{
        position: %{x: 50, y: 60}
      })

      # Clean up
      delete_canvas(canvas.id)  # Also deletes all objects
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
  Lists all canvases (for collaborative access across all users).

  ## Returns
    * List of all canvas structs with user preloaded

  ## Examples

      iex> list_all_canvases()
      [%Canvas{}, %Canvas{}]

  """
  def list_all_canvases do
    Canvas
    |> order_by([c], desc: c.updated_at)
    |> preload(:user)
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
  Locks an object for editing by a specific user.

  ## Parameters
    * `id` - The object ID
    * `user_id` - The user ID locking the object

  ## Returns
    * `{:ok, object}` on success
    * `{:error, :not_found}` if object doesn't exist
    * `{:error, :already_locked}` if object is already locked by another user

  ## Examples

      iex> lock_object(1, "user_123")
      {:ok, %Object{}}

      iex> lock_object(1, "user_456")  # Already locked by user_123
      {:error, :already_locked}

  """
  def lock_object(id, user_id) do
    case Repo.get(Object, id) do
      nil ->
        {:error, :not_found}

      object ->
        cond do
          object.locked_by == user_id ->
            # Already locked by this user, return success
            {:ok, object}

          object.locked_by != nil and object.locked_by != user_id ->
            # Locked by another user
            {:error, :already_locked}

          true ->
            # Not locked or lock expired, acquire lock
            object
            |> Object.changeset(%{locked_by: user_id})
            |> Repo.update()
        end
    end
  end

  @doc """
  Unlocks an object, allowing other users to edit it.

  ## Parameters
    * `id` - The object ID
    * `user_id` - The user ID unlocking the object (optional, for validation)

  ## Returns
    * `{:ok, object}` on success
    * `{:error, :not_found}` if object doesn't exist
    * `{:error, :not_locked_by_user}` if object is locked by another user

  ## Examples

      iex> unlock_object(1, "user_123")
      {:ok, %Object{}}

      iex> unlock_object(1, "user_456")  # Locked by user_123
      {:error, :not_locked_by_user}

  """
  def unlock_object(id, user_id \\ nil) do
    case Repo.get(Object, id) do
      nil ->
        {:error, :not_found}

      object ->
        cond do
          user_id != nil and object.locked_by != user_id ->
            # Trying to unlock object locked by another user
            {:error, :not_locked_by_user}

          true ->
            # Unlock the object
            object
            |> Object.changeset(%{locked_by: nil})
            |> Repo.update()
        end
    end
  end

  @doc """
  Checks if an object is locked and by whom.

  ## Parameters
    * `id` - The object ID

  ## Returns
    * `{:locked, user_id}` if object is locked
    * `{:unlocked, object}` if object is not locked
    * `{:error, :not_found}` if object doesn't exist

  ## Examples

      iex> check_lock(1)
      {:locked, "user_123"}

      iex> check_lock(2)
      {:unlocked, %Object{}}

  """
  def check_lock(id) do
    case Repo.get(Object, id) do
      nil ->
        {:error, :not_found}

      object ->
        if object.locked_by do
          {:locked, object.locked_by}
        else
          {:unlocked, object}
        end
    end
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
