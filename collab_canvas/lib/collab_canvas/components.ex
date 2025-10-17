defmodule CollabCanvas.Components do
  @moduledoc """
  The Components context.

  This module provides the business logic layer for managing reusable components
  in the CollabCanvas application. It serves as the primary interface between
  Phoenix controllers/LiveViews and the database layer for component operations.

  ## Reusable Component System

  A component represents a reusable design element that can be instantiated
  multiple times across canvases. When a component is created, it stores a
  template of objects. When instantiated, it creates copies of those objects
  that remain linked to the main component.

  ### Component Operations
  - Create components from existing objects
  - Instantiate components to create linked copies
  - Update components and propagate changes to all instances
  - Manage component versioning and nested components

  ### Instance Management
  - Component instances are regular objects with `component_id` set
  - Main component objects have `is_main_component: true`
  - Instance overrides are stored in `instance_overrides` field
  - Updates to main component propagate to all instances

  ## Database Operations (CRUD)

  All functions in this context follow standard CRUD patterns:
  - **Create**: Returns `{:ok, struct}` or `{:error, changeset}`
  - **Read**: Returns struct or `nil` for single records, list for multiple
  - **Update**: Returns `{:ok, struct}` or `{:error, changeset}` or `{:error, :not_found}`
  - **Delete**: Returns `{:ok, struct}` or `{:error, :not_found}`

  ## Real-time Updates

  Component changes are broadcast via Phoenix.PubSub to enable real-time
  collaboration. Clients can subscribe to:
  - `component:updated` - When a component is updated
  - `component:instantiated` - When a component is instantiated
  - `component:deleted` - When a component is deleted

  ## Usage Examples

      # Create a component from existing objects
      {:ok, component} = create_component([obj1.id, obj2.id], "Button", "button",
        canvas_id: canvas.id,
        created_by: user.id,
        description: "Primary button component"
      )

      # Instantiate the component at a specific position
      {:ok, instances} = instantiate_component(component.id, %{x: 100, y: 200},
        canvas_id: target_canvas.id
      )

      # Update the component (propagates to all instances)
      {:ok, updated} = update_component(component.id, %{
        description: "Updated button style"
      })
  """

  import Ecto.Query, warn: false
  alias CollabCanvas.Repo

  alias CollabCanvas.Components.Component
  alias CollabCanvas.Canvases.Object
  alias CollabCanvas.Canvases

  require Logger

  @doc """
  Creates a new component from a list of objects.

  This function takes existing objects, marks them as the main component objects,
  and creates a component record that stores their configuration as a template.

  ## Parameters
    * `object_ids` - List of object IDs to include in the component
    * `name` - The name of the component
    * `category` - The category of the component (e.g., "button", "card")
    * `opts` - Additional options (keyword list):
      - `:canvas_id` - Canvas ID where the component is defined (required)
      - `:created_by` - User ID of the component creator
      - `:description` - Component description
      - `:is_published` - Whether to publish the component (default: false)

  ## Returns
    * `{:ok, component}` on success
    * `{:error, changeset}` on validation failure
    * `{:error, :objects_not_found}` if any object IDs are invalid

  ## Examples

      iex> create_component([1, 2], "Button", "button",
      ...>   canvas_id: 5, created_by: 10)
      {:ok, %Component{}}

      iex> create_component([], "Empty", "custom", canvas_id: 5)
      {:error, %Ecto.Changeset{}}
  """
  def create_component(object_ids, name, category, opts \\ []) do
    canvas_id = Keyword.fetch!(opts, :canvas_id)
    created_by = Keyword.get(opts, :created_by)
    description = Keyword.get(opts, :description)
    is_published = Keyword.get(opts, :is_published, false)

    # Validate that all objects exist and belong to the same canvas
    objects = Repo.all(from o in Object, where: o.id in ^object_ids)

    if length(objects) != length(object_ids) do
      {:error, :objects_not_found}
    else
      # Check all objects belong to the same canvas
      if Enum.all?(objects, &(&1.canvas_id == canvas_id)) do
        # Start a transaction to create component and update objects
        Ecto.Multi.new()
        |> Ecto.Multi.insert(:component, fn _ ->
          %Component{}
          |> Component.changeset(%{
            name: name,
            category: category,
            canvas_id: canvas_id,
            created_by: created_by,
            description: description,
            is_published: is_published,
            template_data: encode_template_data(objects)
          })
        end)
        |> Ecto.Multi.run(:mark_objects, fn _repo, %{component: component} ->
          # Mark all objects as main component objects
          updates =
            Enum.map(objects, fn obj ->
              case Canvases.update_object(obj.id, %{
                     component_id: component.id,
                     is_main_component: true
                   }) do
                {:ok, _updated} -> :ok
                error -> error
              end
            end)

          if Enum.all?(updates, &(&1 == :ok)) do
            {:ok, component}
          else
            {:error, :failed_to_mark_objects}
          end
        end)
        |> Repo.transaction()
        |> case do
          {:ok, %{component: component}} ->
            # Broadcast component creation
            broadcast_component_change(:created, component)
            {:ok, component}

          {:error, _step, changeset, _changes} ->
            {:error, changeset}
        end
      else
        {:error, :objects_must_belong_to_same_canvas}
      end
    end
  end

  @doc """
  Instantiates a component at a specific position.

  Creates copies of all objects in the component template, linked to the
  original component. The new instances will have the same relative positions
  and properties as the template objects, offset by the given position.

  ## Parameters
    * `component_id` - The component ID to instantiate
    * `position` - Map with `:x` and `:y` coordinates for the instance position
    * `opts` - Additional options (keyword list):
      - `:canvas_id` - Canvas ID where to instantiate (required)
      - `:overrides` - Map of property overrides for instances (optional)

  ## Returns
    * `{:ok, [objects]}` - List of created object instances on success
    * `{:error, :not_found}` if component doesn't exist
    * `{:error, reason}` on failure

  ## Examples

      iex> instantiate_component(1, %{x: 100, y: 200}, canvas_id: 5)
      {:ok, [%Object{}, %Object{}]}

      iex> instantiate_component(999, %{x: 0, y: 0}, canvas_id: 5)
      {:error, :not_found}
  """
  def instantiate_component(component_id, position, opts \\ []) do
    canvas_id = Keyword.fetch!(opts, :canvas_id)
    overrides = Keyword.get(opts, :overrides, %{})

    case get_component(component_id) do
      nil ->
        {:error, :not_found}

      component ->
        # Decode template data
        template_objects = decode_template_data(component.template_data)

        # Calculate offset based on the first object's position
        base_position = calculate_base_position(template_objects)
        offset_x = position.x - base_position.x
        offset_y = position.y - base_position.y

        # Create instances
        instances =
          Enum.map(template_objects, fn template_obj ->
            new_position = %{
              x: template_obj.position.x + offset_x,
              y: template_obj.position.y + offset_y
            }

            attrs = %{
              type: template_obj.type,
              data: template_obj.data,
              position: new_position,
              component_id: component_id,
              is_main_component: false,
              instance_overrides: Jason.encode!(overrides)
            }

            Canvases.create_object(canvas_id, template_obj.type, attrs)
          end)

        # Check if all instances were created successfully
        if Enum.all?(instances, &match?({:ok, _}, &1)) do
          created_objects = Enum.map(instances, fn {:ok, obj} -> obj end)

          # Broadcast instantiation
          broadcast_component_change(:instantiated, component, %{
            instances: created_objects,
            canvas_id: canvas_id
          })

          {:ok, created_objects}
        else
          # Find the first error
          error = Enum.find(instances, &match?({:error, _}, &1))
          error
        end
    end
  end

  @doc """
  Updates a component and optionally propagates changes to all instances.

  When a component is updated, the changes can be propagated to all its
  instances (objects with `component_id` set to this component and
  `is_main_component: false`).

  ## Parameters
    * `component_id` - The component ID to update
    * `changes` - Map of changes to apply
    * `opts` - Additional options (keyword list):
      - `:propagate` - Whether to propagate changes to instances (default: true)
      - `:skip_fields` - List of fields to skip during propagation

  ## Returns
    * `{:ok, component}` on success
    * `{:error, :not_found}` if component doesn't exist
    * `{:error, changeset}` on validation failure

  ## Examples

      iex> update_component(1, %{description: "Updated"})
      {:ok, %Component{}}

      iex> update_component(999, %{description: "Updated"})
      {:error, :not_found}
  """
  def update_component(component_id, changes, opts \\ []) do
    propagate = Keyword.get(opts, :propagate, true)
    skip_fields = Keyword.get(opts, :skip_fields, [])

    case get_component(component_id) do
      nil ->
        {:error, :not_found}

      component ->
        changeset = Component.changeset(component, changes)

        case Repo.update(changeset) do
          {:ok, updated_component} ->
            # Propagate changes to instances if requested
            if propagate do
              propagate_to_instances(component_id, changes, skip_fields)
            end

            # Broadcast update
            broadcast_component_change(:updated, updated_component)

            {:ok, updated_component}

          {:error, changeset} ->
            {:error, changeset}
        end
    end
  end

  @doc """
  Gets a single component by ID.

  ## Parameters
    * `id` - The component ID

  ## Returns
    * The component struct if found
    * `nil` if not found

  ## Examples

      iex> get_component(123)
      %Component{}

      iex> get_component(456)
      nil
  """
  def get_component(id) do
    Repo.get(Component, id)
  end

  @doc """
  Gets a component with its main objects preloaded.

  ## Parameters
    * `id` - The component ID

  ## Returns
    * The component with objects if found
    * `nil` if not found

  ## Examples

      iex> get_component_with_objects(123)
      %Component{main_objects: [%Object{}, %Object{}]}
  """
  def get_component_with_objects(id) do
    case get_component(id) do
      nil ->
        nil

      component ->
        main_objects =
          Object
          |> where([o], o.component_id == ^id and o.is_main_component == true)
          |> Repo.all()

        Map.put(component, :main_objects, main_objects)
    end
  end

  @doc """
  Lists all instances of a component.

  ## Parameters
    * `component_id` - The component ID

  ## Returns
    * List of object structs that are instances of this component

  ## Examples

      iex> list_component_instances(1)
      [%Object{}, %Object{}]
  """
  def list_component_instances(component_id) do
    Object
    |> where([o], o.component_id == ^component_id and o.is_main_component == false)
    |> Repo.all()
  end

  @doc """
  Lists all published components.

  ## Returns
    * List of published component structs

  ## Examples

      iex> list_published_components()
      [%Component{}, %Component{}]
  """
  def list_published_components do
    Component
    |> where([c], c.is_published == true)
    |> order_by([c], desc: c.updated_at)
    |> Repo.all()
  end

  @doc """
  Lists all components for a specific canvas.

  ## Parameters
    * `canvas_id` - The canvas ID

  ## Returns
    * List of component structs

  ## Examples

      iex> list_canvas_components(1)
      [%Component{}, %Component{}]
  """
  def list_canvas_components(canvas_id) do
    Component
    |> where([c], c.canvas_id == ^canvas_id)
    |> order_by([c], desc: c.updated_at)
    |> Repo.all()
  end

  @doc """
  Deletes a component and optionally its instances.

  ## Parameters
    * `id` - The component ID
    * `opts` - Options (keyword list):
      - `:delete_instances` - Whether to delete all instances (default: false)
      - `:unlink_instances` - Whether to unlink instances instead (default: true)

  ## Returns
    * `{:ok, component}` on success
    * `{:error, :not_found}` if component doesn't exist

  ## Examples

      iex> delete_component(1)
      {:ok, %Component{}}

      iex> delete_component(1, delete_instances: true)
      {:ok, %Component{}}
  """
  def delete_component(id, opts \\ []) do
    delete_instances = Keyword.get(opts, :delete_instances, false)
    unlink_instances = Keyword.get(opts, :unlink_instances, true)

    case get_component(id) do
      nil ->
        {:error, :not_found}

      component ->
        # Handle instances
        if delete_instances do
          # Delete all instances
          Object
          |> where([o], o.component_id == ^id and o.is_main_component == false)
          |> Repo.delete_all()
        else
          if unlink_instances do
            # Unlink instances (set component_id to nil)
            Object
            |> where([o], o.component_id == ^id and o.is_main_component == false)
            |> Repo.update_all(set: [component_id: nil])
          end
        end

        # Delete or unlink main component objects
        Object
        |> where([o], o.component_id == ^id and o.is_main_component == true)
        |> Repo.update_all(set: [component_id: nil, is_main_component: false])

        # Delete the component
        case Repo.delete(component) do
          {:ok, deleted} ->
            broadcast_component_change(:deleted, deleted)
            {:ok, deleted}

          error ->
            error
        end
    end
  end

  # Private functions

  defp encode_template_data(objects) do
    template =
      Enum.map(objects, fn obj ->
        %{
          id: obj.id,
          type: obj.type,
          data: obj.data,
          position: obj.position
        }
      end)

    Jason.encode!(template)
  end

  defp decode_template_data(nil), do: []

  defp decode_template_data(template_data) when is_binary(template_data) do
    case Jason.decode(template_data) do
      {:ok, data} ->
        Enum.map(data, fn obj ->
          %{
            id: obj["id"],
            type: obj["type"],
            data: obj["data"],
            position: %{
              x: obj["position"]["x"] || 0,
              y: obj["position"]["y"] || 0
            }
          }
        end)

      {:error, _} ->
        []
    end
  end

  defp calculate_base_position([]), do: %{x: 0, y: 0}

  defp calculate_base_position(template_objects) do
    # Use the first object's position as the base
    first = List.first(template_objects)
    first.position
  end

  defp propagate_to_instances(component_id, changes, skip_fields) do
    # Get all instances
    instances = list_component_instances(component_id)

    # Get main component objects for template update
    main_objects =
      Object
      |> where([o], o.component_id == ^component_id and o.is_main_component == true)
      |> Repo.all()

    # Update template data if it exists
    if Enum.any?(main_objects) do
      template_data = encode_template_data(main_objects)

      # Apply template changes to instances
      # Filter out changes that should be skipped
      instance_changes =
        changes
        |> Map.drop(skip_fields)
        |> Map.drop([:name, :description, :category, :is_published])

      # Update each instance that doesn't have overrides for these fields
      Enum.each(instances, fn instance ->
        # Check instance overrides
        overrides =
          case instance.instance_overrides do
            nil -> %{}
            override_str -> Jason.decode!(override_str)
          end

        # Only apply changes for fields not in overrides
        applicable_changes =
          instance_changes
          |> Enum.filter(fn {key, _value} ->
            !Map.has_key?(overrides, Atom.to_string(key))
          end)
          |> Map.new()

        if map_size(applicable_changes) > 0 do
          Canvases.update_object(instance.id, applicable_changes)
        end
      end)
    end

    :ok
  end

  defp broadcast_component_change(event, component, metadata \\ %{}) do
    Phoenix.PubSub.broadcast(
      CollabCanvas.PubSub,
      "component:#{event}",
      {event, component, metadata}
    )
  end
end
