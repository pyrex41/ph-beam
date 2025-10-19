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
  alias CollabCanvas.Canvases.CanvasUserViewport

  # Lock timeout duration in minutes
  # After this period of inactivity, locks automatically expire
  @lock_timeout_minutes 10

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
    |> order_by([o], asc: o.z_index)
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

  Locks automatically expire after #{@lock_timeout_minutes} minutes of inactivity.
  Expired locks are treated as unlocked and can be acquired by any user.

  ## Parameters
    * `id` - The object ID
    * `user_id` - The user ID locking the object

  ## Returns
    * `{:ok, object}` on success
    * `{:error, :not_found}` if object doesn't exist
    * `{:error, :already_locked}` if object is already locked by another user and lock hasn't expired

  ## Examples

      iex> lock_object(1, "user_123")
      {:ok, %Object{}}

      iex> lock_object(1, "user_456")  # Already locked by user_123 (lock not expired)
      {:error, :already_locked}

  """
  def lock_object(id, user_id) do
    case Repo.get(Object, id) do
      nil ->
        {:error, :not_found}

      object ->
        cond do
          object.locked_by == user_id ->
            # Already locked by this user, refresh the lock timestamp
            object
            |> Object.changeset(%{locked_at: DateTime.utc_now()})
            |> Repo.update()

          object.locked_by != nil and object.locked_by != user_id and not lock_expired?(object) ->
            # Locked by another user and lock hasn't expired
            {:error, :already_locked}

          true ->
            # Not locked, or lock expired - acquire lock with current timestamp
            object
            |> Object.changeset(%{locked_by: user_id, locked_at: DateTime.utc_now()})
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
            # Unlock the object and clear timestamp
            object
            |> Object.changeset(%{locked_by: nil, locked_at: nil})
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

  @doc """
  Creates a group for multiple objects by assigning them a shared group_id.

  ## Parameters
    * `object_ids` - List of object IDs to group together

  ## Returns
    * `{:ok, group_id, objects}` on success with the generated group_id and updated objects
    * `{:error, :not_found}` if any object doesn't exist
    * `{:error, :no_objects}` if object_ids list is empty

  ## Examples

      iex> create_group([1, 2, 3])
      {:ok, "550e8400-e29b-41d4-a716-446655440000", [%Object{}, %Object{}, %Object{}]}

      iex> create_group([])
      {:error, :no_objects}

  """
  def create_group(object_ids) when is_list(object_ids) and length(object_ids) > 0 do
    group_id = Ecto.UUID.generate()

    # Fetch all objects first to verify they exist
    objects = Object
    |> where([o], o.id in ^object_ids)
    |> Repo.all()

    if length(objects) == length(object_ids) do
      # Update all objects with the group_id
      Object
      |> where([o], o.id in ^object_ids)
      |> Repo.update_all(set: [group_id: group_id, updated_at: DateTime.utc_now()])

      # Fetch updated objects
      updated_objects = Object
      |> where([o], o.id in ^object_ids)
      |> Repo.all()

      {:ok, group_id, updated_objects}
    else
      {:error, :not_found}
    end
  end

  def create_group(_), do: {:error, :no_objects}

  @doc """
  Ungroups objects by removing their group_id.

  ## Parameters
    * `group_id` - The group UUID to ungroup
    * `object_ids` - Optional list of specific object IDs to ungroup (ungroups all if nil)

  ## Returns
    * `{:ok, objects}` on success with the updated objects
    * `{:error, :not_found}` if no objects found

  ## Examples

      iex> ungroup("550e8400-e29b-41d4-a716-446655440000")
      {:ok, [%Object{}, %Object{}]}

      iex> ungroup("550e8400-e29b-41d4-a716-446655440000", [1, 2])
      {:ok, [%Object{}, %Object{}]}

  """
  def ungroup(group_id, object_ids \\ nil) do
    query = Object
    |> where([o], o.group_id == ^group_id)

    query = if object_ids do
      where(query, [o], o.id in ^object_ids)
    else
      query
    end

    {count, _} = query
    |> Repo.update_all(set: [group_id: nil, updated_at: DateTime.utc_now()])

    if count > 0 do
      updated_objects = Object
      |> where([o], o.id in ^(if object_ids, do: object_ids, else: subquery(query |> select([o], o.id))))
      |> Repo.all()

      {:ok, updated_objects}
    else
      {:error, :not_found}
    end
  end

  @doc """
  Gets all objects in a group.

  ## Parameters
    * `group_id` - The group UUID

  ## Returns
    * List of object structs in the group

  ## Examples

      iex> get_group_objects("550e8400-e29b-41d4-a716-446655440000")
      [%Object{}, %Object{}, %Object{}]

  """
  def get_group_objects(group_id) do
    Object
    |> where([o], o.group_id == ^group_id)
    |> order_by([o], asc: o.z_index)
    |> Repo.all()
  end

  @doc """
  Updates z_index for an object to control layering.

  ## Parameters
    * `id` - The object ID
    * `z_index` - Float value for the new z_index

  ## Returns
    * `{:ok, object}` on success
    * `{:error, :not_found}` if object doesn't exist

  ## Examples

      iex> update_z_index(1, 10.5)
      {:ok, %Object{z_index: 10.5}}

  """
  def update_z_index(id, z_index) when is_number(z_index) do
    update_object(id, %{z_index: z_index})
  end

  @doc """
  Brings an object (or group) to the front by setting its z_index higher than all others.

  ## Parameters
    * `id` - The object ID

  ## Returns
    * `{:ok, objects}` on success (list because it might affect grouped objects)
    * `{:error, :not_found}` if object doesn't exist

  ## Examples

      iex> bring_to_front(1)
      {:ok, [%Object{z_index: 101.0}]}

  """
  def bring_to_front(id) do
    with {:ok, object} <- {:ok, Repo.get(Object, id)},
         false <- is_nil(object) do
      # Get max z_index for the canvas
      max_z = Object
      |> where([o], o.canvas_id == ^object.canvas_id)
      |> select([o], max(o.z_index))
      |> Repo.one()
      |> Kernel.||(0.0)

      new_z = max_z + 1.0

      # Update object and any objects in its group
      ids_to_update = if object.group_id do
        Object
        |> where([o], o.group_id == ^object.group_id)
        |> select([o], o.id)
        |> Repo.all()
      else
        [id]
      end

      Object
      |> where([o], o.id in ^ids_to_update)
      |> Repo.update_all(set: [z_index: new_z, updated_at: DateTime.utc_now()])

      updated_objects = Object
      |> where([o], o.id in ^ids_to_update)
      |> Repo.all()

      {:ok, updated_objects}
    else
      true -> {:error, :not_found}
      error -> error
    end
  end

  @doc """
  Sends an object (or group) to the back by setting its z_index lower than all others.

  ## Parameters
    * `id` - The object ID

  ## Returns
    * `{:ok, objects}` on success (list because it might affect grouped objects)
    * `{:error, :not_found}` if object doesn't exist

  ## Examples

      iex> send_to_back(1)
      {:ok, [%Object{z_index: -1.0}]}

  """
  def send_to_back(id) do
    with {:ok, object} <- {:ok, Repo.get(Object, id)},
         false <- is_nil(object) do
      # Get min z_index for the canvas
      min_z = Object
      |> where([o], o.canvas_id == ^object.canvas_id)
      |> select([o], min(o.z_index))
      |> Repo.one()
      |> Kernel.||(0.0)

      new_z = min_z - 1.0

      # Update object and any objects in its group
      ids_to_update = if object.group_id do
        Object
        |> where([o], o.group_id == ^object.group_id)
        |> select([o], o.id)
        |> Repo.all()
      else
        [id]
      end

      Object
      |> where([o], o.id in ^ids_to_update)
      |> Repo.update_all(set: [z_index: new_z, updated_at: DateTime.utc_now()])

      updated_objects = Object
      |> where([o], o.id in ^ids_to_update)
      |> Repo.all()

      {:ok, updated_objects}
    else
      true -> {:error, :not_found}
      error -> error
    end
  end

  @doc """
  Moves an object (or group) forward one layer by swapping z_index with the next object.

  ## Parameters
    * `id` - The object ID

  ## Returns
    * `{:ok, objects}` on success (list of affected objects)
    * `{:error, :not_found}` if object doesn't exist
    * `{:error, :already_at_front}` if object is already at the front

  ## Examples

      iex> move_forward(1)
      {:ok, [%Object{z_index: 5.5}]}

  """
  def move_forward(id) do
    with {:ok, object} <- {:ok, Repo.get(Object, id)},
         false <- is_nil(object) do
      # Get all objects on canvas ordered by z_index
      canvas_objects = Object
      |> where([o], o.canvas_id == ^object.canvas_id)
      |> order_by([o], asc: o.z_index)
      |> Repo.all()

      # Find objects above this one
      objects_above = Enum.filter(canvas_objects, fn obj -> obj.z_index > object.z_index end)

      if Enum.empty?(objects_above) do
        {:error, :already_at_front}
      else
        # Get the next object above
        next_object = List.first(objects_above)

        # Swap z_index values
        current_z = object.z_index
        next_z = next_object.z_index

        # Update both objects (and their groups if they exist)
        ids_to_update_current = if object.group_id do
          Object
          |> where([o], o.group_id == ^object.group_id)
          |> select([o], o.id)
          |> Repo.all()
        else
          [id]
        end

        Object
        |> where([o], o.id in ^ids_to_update_current)
        |> Repo.update_all(set: [z_index: next_z, updated_at: DateTime.utc_now()])

        Object
        |> where([o], o.id == ^next_object.id)
        |> Repo.update_all(set: [z_index: current_z, updated_at: DateTime.utc_now()])

        # Return all affected objects
        updated_objects = Object
        |> where([o], o.id in ^(ids_to_update_current ++ [next_object.id]))
        |> Repo.all()

        {:ok, updated_objects}
      end
    else
      true -> {:error, :not_found}
      error -> error
    end
  end

  @doc """
  Moves an object (or group) backward one layer by swapping z_index with the previous object.

  ## Parameters
    * `id` - The object ID

  ## Returns
    * `{:ok, objects}` on success (list of affected objects)
    * `{:error, :not_found}` if object doesn't exist
    * `{:error, :already_at_back}` if object is already at the back

  ## Examples

      iex> move_backward(1)
      {:ok, [%Object{z_index: 2.5}]}

  """
  def move_backward(id) do
    with {:ok, object} <- {:ok, Repo.get(Object, id)},
         false <- is_nil(object) do
      # Get all objects on canvas ordered by z_index
      canvas_objects = Object
      |> where([o], o.canvas_id == ^object.canvas_id)
      |> order_by([o], asc: o.z_index)
      |> Repo.all()

      # Find objects below this one
      objects_below = Enum.filter(canvas_objects, fn obj -> obj.z_index < object.z_index end)

      if Enum.empty?(objects_below) do
        {:error, :already_at_back}
      else
        # Get the object directly below
        prev_object = List.last(objects_below)

        # Swap z_index values
        current_z = object.z_index
        prev_z = prev_object.z_index

        # Update both objects (and their groups if they exist)
        ids_to_update_current = if object.group_id do
          Object
          |> where([o], o.group_id == ^object.group_id)
          |> select([o], o.id)
          |> Repo.all()
        else
          [id]
        end

        Object
        |> where([o], o.id in ^ids_to_update_current)
        |> Repo.update_all(set: [z_index: prev_z, updated_at: DateTime.utc_now()])

        Object
        |> where([o], o.id == ^prev_object.id)
        |> Repo.update_all(set: [z_index: current_z, updated_at: DateTime.utc_now()])

        # Return all affected objects
        updated_objects = Object
        |> where([o], o.id in ^(ids_to_update_current ++ [prev_object.id]))
        |> Repo.all()

        {:ok, updated_objects}
      end
    else
      true -> {:error, :not_found}
      error -> error
    end
  end

  # Private helper to check if a lock has expired
  # Locks expire after @lock_timeout_minutes of inactivity
  defp lock_expired?(object) do
    case object.locked_at do
      nil ->
        # No timestamp means lock is from before timeout system - treat as expired
        true

      locked_at ->
        # Check if lock is older than timeout duration
        timeout_seconds = @lock_timeout_minutes * 60
        now = DateTime.utc_now()
        elapsed_seconds = DateTime.diff(now, locked_at, :second)
        elapsed_seconds > timeout_seconds
    end
  end

  @doc """
  Gets a user's saved viewport position for a specific canvas.

  ## Parameters
    * `user_id` - The user ID
    * `canvas_id` - The canvas ID

  ## Returns
    * The viewport struct if found
    * `nil` if not found

  ## Examples

      iex> get_viewport(1, 2)
      %CanvasUserViewport{viewport_x: 100.0, viewport_y: 50.0, zoom: 1.5}

      iex> get_viewport(999, 2)
      nil

  """
  def get_viewport(user_id, canvas_id) do
    CanvasUserViewport
    |> where([v], v.user_id == ^user_id and v.canvas_id == ^canvas_id)
    |> Repo.one()
  end

  @doc """
  Saves or updates a user's viewport position for a specific canvas.

  ## Parameters
    * `user_id` - The user ID
    * `canvas_id` - The canvas ID
    * `attrs` - Map with viewport_x, viewport_y, and zoom

  ## Returns
    * `{:ok, viewport}` on success
    * `{:error, changeset}` on validation failure

  ## Examples

      iex> save_viewport(1, 2, %{viewport_x: 100.0, viewport_y: 50.0, zoom: 1.5})
      {:ok, %CanvasUserViewport{}}

  """
  def save_viewport(user_id, canvas_id, attrs) do
    attrs = Map.merge(attrs, %{user_id: user_id, canvas_id: canvas_id})

    case get_viewport(user_id, canvas_id) do
      nil ->
        %CanvasUserViewport{}
        |> CanvasUserViewport.changeset(attrs)
        |> Repo.insert()

      viewport ->
        viewport
        |> CanvasUserViewport.changeset(attrs)
        |> Repo.update()
    end
  end
end
