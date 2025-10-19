defmodule CollabCanvasWeb.ComponentsPanelLive do
  @moduledoc """
  LiveComponent for displaying and managing the component library.

  This component provides a comprehensive interface for working with reusable components,
  including browsing, searching, filtering, and instantiating components via drag-and-drop.

  ## Features

  ### Component Library Display
  - Displays all published components with thumbnails
  - Shows component metadata (name, category, description)
  - Organizes components by category folders
  - Provides preview thumbnails generated from template data

  ### Search and Filter
  - Real-time search by component name or description
  - Filter by category (button, card, form, navigation, layout, icon, custom)
  - Case-insensitive search with debouncing
  - Combined search and filter functionality

  ### Drag-and-Drop Instantiation
  - Drag components from panel to canvas
  - Visual feedback during drag operations
  - Drop position determines instance placement
  - Automatically creates instances on the target canvas

  ### Real-Time Updates
  - Subscribes to component:created, component:updated, component:deleted events
  - Automatically updates component list when changes occur
  - Reflects changes from other users in real-time
  - Maintains search/filter state during updates

  ### Component Management
  - Create new components from selected objects
  - Update component properties (name, description, category)
  - Delete components with confirmation
  - Toggle component publishing status

  ## State Management

  The component assigns include:
  - `:id` - Unique identifier for this LiveComponent instance
  - `:canvas_id` - Canvas ID for subscribing to component events
  - `:components` - List of all published components
  - `:filtered_components` - Filtered list based on search/category
  - `:search_query` - Current search text
  - `:selected_category` - Current category filter (nil = all)
  - `:expanded_categories` - Set of expanded folder categories
  - `:dragging_component` - Component currently being dragged (if any)

  ## Event Flow

  1. User searches or filters components
  2. Client sends event to LiveComponent
  3. LiveComponent updates filtered_components
  4. UI re-renders with filtered results

  For drag-and-drop:
  1. User starts dragging a component
  2. JavaScript hook sends drag_start event
  3. User drops component on canvas
  4. JavaScript hook sends instantiate_component event
  5. LiveComponent calls Components.instantiate_component/3
  6. New instances are created and broadcast via PubSub
  """

  use CollabCanvasWeb, :live_component

  alias CollabCanvas.Components
  alias CollabCanvas.Components.Component

  require Logger

  @doc """
  Mounts the LiveComponent and initializes component library state.

  ## Responsibilities

  1. Subscribes to component events (created, updated, deleted, instantiated)
  2. Loads all published components from the database
  3. Initializes search and filter state
  4. Sets up default expanded categories

  ## Returns

  `{:ok, socket}` with initialized assigns
  """
  @impl true
  def mount(socket) do
    # Subscribe to component events
    Phoenix.PubSub.subscribe(CollabCanvas.PubSub, "component:created")
    Phoenix.PubSub.subscribe(CollabCanvas.PubSub, "component:updated")
    Phoenix.PubSub.subscribe(CollabCanvas.PubSub, "component:deleted")
    Phoenix.PubSub.subscribe(CollabCanvas.PubSub, "component:instantiated")

    {:ok, socket}
  end

  @doc """
  Updates the LiveComponent with new assigns.

  Called when parent LiveView passes new assigns to this component.
  Loads and filters components based on canvas_id and current search/filter state.

  ## Parameters

  - `assigns` - Map containing:
    - `:id` - Component instance ID
    - `:canvas_id` - Canvas ID for component context
  """
  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:search_query, fn -> "" end)
      |> assign_new(:selected_category, fn -> nil end)
      |> assign_new(:expanded_categories, fn -> MapSet.new(["button", "card"]) end)
      |> assign_new(:dragging_component, fn -> nil end)

    # Load components
    components = load_components(socket.assigns.canvas_id)

    socket =
      socket
      |> assign(:components, components)
      |> apply_filters()

    {:ok, socket}
  end

  @doc """
  Handles search query input from the client.

  Updates the search query and re-filters the component list based on
  name and description matching.

  ## Parameters

  - `params` - Map containing "value" key with search text

  ## Returns

  `{:noreply, socket}` with updated search_query and filtered_components
  """
  @impl true
  def handle_event("search", %{"value" => query}, socket) do
    socket =
      socket
      |> assign(:search_query, String.downcase(query))
      |> apply_filters()

    {:noreply, socket}
  end

  @doc """
  Handles category filter selection from the client.

  Updates the category filter and re-filters the component list.

  ## Parameters

  - `params` - Map containing "category" key (or nil for all)

  ## Returns

  `{:noreply, socket}` with updated selected_category and filtered_components
  """
  @impl true
  def handle_event("filter_category", %{"category" => category}, socket) do
    category = if category == "", do: nil, else: category

    socket =
      socket
      |> assign(:selected_category, category)
      |> apply_filters()

    {:noreply, socket}
  end

  @doc """
  Handles category folder expand/collapse toggle.

  Toggles whether a category folder is expanded or collapsed in the UI.

  ## Parameters

  - `params` - Map containing "category" key

  ## Returns

  `{:noreply, socket}` with updated expanded_categories
  """
  @impl true
  def handle_event("toggle_category", %{"category" => category}, socket) do
    expanded = socket.assigns.expanded_categories

    expanded =
      if MapSet.member?(expanded, category) do
        MapSet.delete(expanded, category)
      else
        MapSet.put(expanded, category)
      end

    {:noreply, assign(socket, :expanded_categories, expanded)}
  end

  @doc """
  Handles drag start event from the client.

  Records which component is being dragged for reference during drop.

  ## Parameters

  - `params` - Map containing "component_id" key

  ## Returns

  `{:noreply, socket}` with updated dragging_component
  """
  @impl true
  def handle_event("drag_start", %{"component_id" => component_id}, socket) do
    component_id =
      if is_binary(component_id), do: String.to_integer(component_id), else: component_id

    component = Enum.find(socket.assigns.components, &(&1.id == component_id))

    {:noreply, assign(socket, :dragging_component, component)}
  end

  @doc """
  Handles drag end event from the client.

  Clears the dragging component reference.

  ## Returns

  `{:noreply, socket}` with cleared dragging_component
  """
  @impl true
  def handle_event("drag_end", _params, socket) do
    {:noreply, assign(socket, :dragging_component, nil)}
  end

  # Note: instantiate_component event is handled by parent LiveView (CanvasLive)
  # The drag-and-drop hook sends the event directly to the parent

  @doc """
  Handles component creation from selected objects.

  Creates a new reusable component from the given object IDs.

  ## Parameters

  - `params` - Map containing:
    - "object_ids" - List of object IDs to include in component
    - "name" - Component name
    - "category" - Component category
    - "description" - Optional description

  ## Returns

  `{:noreply, socket}` with flash message (success or error)
  """
  @impl true
  def handle_event("create_component", params, socket) do
    object_ids = params["object_ids"] || []
    name = params["name"]
    category = params["category"] || "custom"
    description = params["description"]

    # Get current user from parent
    user_id = get_current_user_id(socket)

    case Components.create_component(object_ids, name, category,
           canvas_id: socket.assigns.canvas_id,
           created_by: user_id,
           description: description,
           is_published: true
         ) do
      {:ok, component} ->
        # Component will be added via PubSub broadcast
        {:noreply, put_flash(socket, :info, "Component '#{component.name}' created successfully")}

      {:error, :objects_not_found} ->
        {:noreply, put_flash(socket, :error, "Some objects were not found")}

      {:error, :objects_must_belong_to_same_canvas} ->
        {:noreply, put_flash(socket, :error, "All objects must belong to the same canvas")}

      {:error, changeset} ->
        errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
        error_msg = "Failed to create component: #{inspect(errors)}"
        {:noreply, put_flash(socket, :error, error_msg)}
    end
  end

  @doc """
  Handles component update requests.

  Updates component properties (name, description, category).

  ## Parameters

  - `params` - Map containing:
    - "component_id" - ID of component to update
    - Other fields to update (name, description, category, is_published)

  ## Returns

  `{:noreply, socket}` with flash message (success or error)
  """
  @impl true
  def handle_event("update_component", params, socket) do
    component_id = params["component_id"]

    component_id =
      if is_binary(component_id), do: String.to_integer(component_id), else: component_id

    changes =
      params
      |> Map.drop(["component_id"])
      |> Map.new(fn {k, v} -> {String.to_atom(k), v} end)

    case Components.update_component(component_id, changes) do
      {:ok, component} ->
        # Component will be updated via PubSub broadcast
        {:noreply, put_flash(socket, :info, "Component '#{component.name}' updated successfully")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Component not found")}

      {:error, changeset} ->
        errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
        error_msg = "Failed to update component: #{inspect(errors)}"
        {:noreply, put_flash(socket, :error, error_msg)}
    end
  end

  @doc """
  Handles instance property override requests.

  Allows overriding specific properties of a component instance without affecting
  the main component or other instances.

  ## Parameters

  - `params` - Map containing:
    - "instance_id" - ID of the instance object to override
    - "property" - Property name to override
    - "value" - New value for the property

  ## Returns

  `{:noreply, socket}` with flash message (success or error)
  """
  @impl true
  def handle_event("override_instance_property", params, socket) do
    instance_id = params["instance_id"]
    instance_id = if is_binary(instance_id), do: String.to_integer(instance_id), else: instance_id

    property = params["property"]
    value = params["value"]

    # Load current instance to get existing overrides
    case CollabCanvas.Canvases.get_object(instance_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Instance not found")}

      instance ->
        # Parse existing overrides
        overrides =
          case instance.instance_overrides do
            nil -> %{}
            json when is_binary(json) -> Jason.decode!(json)
            map when is_map(map) -> map
          end

        # Add new override
        overrides = Map.put(overrides, property, value)

        # Update instance
        case CollabCanvas.Canvases.update_object(instance_id, %{
               instance_overrides: Jason.encode!(overrides)
             }) do
          {:ok, _updated} ->
            {:noreply, put_flash(socket, :info, "Instance property overridden successfully")}

          {:error, :not_found} ->
            {:noreply, put_flash(socket, :error, "Instance not found")}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, "Failed to override instance property")}
        end
    end
  end

  @doc """
  Handles component:created broadcasts from PubSub.

  Adds newly created components to the library.

  ## Parameters

  - `{:created, component, _metadata}` - Tuple with component struct

  ## Returns

  `{:noreply, socket}` with updated components list
  """
  @impl true
  def handle_info({:created, component, _metadata}, socket) do
    # Only show published components
    if component.is_published do
      components = [component | socket.assigns.components]

      socket =
        socket
        |> assign(:components, components)
        |> apply_filters()

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @doc """
  Handles component:updated broadcasts from PubSub.

  Updates component in the library list.

  ## Parameters

  - `{:updated, component, _metadata}` - Tuple with updated component struct

  ## Returns

  `{:noreply, socket}` with updated components list
  """
  @impl true
  def handle_info({:updated, component, _metadata}, socket) do
    components =
      Enum.map(socket.assigns.components, fn c ->
        if c.id == component.id, do: component, else: c
      end)

    socket =
      socket
      |> assign(:components, components)
      |> apply_filters()

    {:noreply, socket}
  end

  @doc """
  Handles component:deleted broadcasts from PubSub.

  Removes deleted component from the library list.

  ## Parameters

  - `{:deleted, component, _metadata}` - Tuple with deleted component struct

  ## Returns

  `{:noreply, socket}` with updated components list
  """
  @impl true
  def handle_info({:deleted, component, _metadata}, socket) do
    components = Enum.reject(socket.assigns.components, fn c -> c.id == component.id end)

    socket =
      socket
      |> assign(:components, components)
      |> apply_filters()

    {:noreply, socket}
  end

  @doc """
  Handles component:instantiated broadcasts from PubSub.

  Can be used to show notifications or update UI when components are instantiated.

  ## Returns

  `{:noreply, socket}` - Currently no-op, can be extended for notifications
  """
  @impl true
  def handle_info({:instantiated, _component, _metadata}, socket) do
    {:noreply, socket}
  end

  # Private helper functions

  defp load_components(_canvas_id) do
    # Load all published components
    Components.list_published_components()
  end

  defp apply_filters(socket) do
    components = socket.assigns.components
    query = socket.assigns.search_query
    category = socket.assigns.selected_category

    filtered =
      components
      |> filter_by_search(query)
      |> filter_by_category(category)

    assign(socket, :filtered_components, filtered)
  end

  defp filter_by_search(components, ""), do: components

  defp filter_by_search(components, query) do
    query = String.downcase(query)

    Enum.filter(components, fn component ->
      name_match = String.contains?(String.downcase(component.name), query)

      description_match =
        if component.description do
          String.contains?(String.downcase(component.description), query)
        else
          false
        end

      name_match || description_match
    end)
  end

  defp filter_by_category(components, nil), do: components

  defp filter_by_category(components, category) do
    Enum.filter(components, fn component ->
      component.category == category
    end)
  end

  defp get_current_user_id(socket) do
    # Try to get user_id from parent assigns
    case socket.assigns do
      %{current_user: %{id: id}} -> id
      %{user_id: user_id} -> user_id
      _ -> nil
    end
  end

  defp generate_thumbnail_url(component) do
    # Generate a simple SVG thumbnail based on template data
    # In a real implementation, this could render a preview of the component
    template_data = component.template_data || "{}"

    case Jason.decode(template_data) do
      {:ok, objects} when is_list(objects) and length(objects) > 0 ->
        # Generate SVG from first object
        first_object = List.first(objects)
        type = first_object["type"]

        case type do
          "rectangle" -> generate_rectangle_svg()
          "circle" -> generate_circle_svg()
          "text" -> generate_text_svg()
          _ -> generate_default_svg()
        end

      _ ->
        generate_default_svg()
    end
  end

  defp generate_rectangle_svg do
    "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'%3E%3Crect x='10' y='20' width='80' height='60' fill='%233b82f6' rx='4'/%3E%3C/svg%3E"
  end

  defp generate_circle_svg do
    "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'%3E%3Ccircle cx='50' cy='50' r='40' fill='%2310b981'/%3E%3C/svg%3E"
  end

  defp generate_text_svg do
    "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'%3E%3Ctext x='50' y='55' text-anchor='middle' font-size='32' fill='%236b7280'%3ET%3C/text%3E%3C/svg%3E"
  end

  defp generate_default_svg do
    "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'%3E%3Crect x='20' y='20' width='60' height='60' fill='%23e5e7eb' rx='8'/%3E%3C/svg%3E"
  end

  defp group_components_by_category(components) do
    Enum.group_by(components, fn component ->
      component.category || "custom"
    end)
  end

  defp category_icon(category) do
    case category do
      "button" -> "cursor-arrow-rays"
      "card" -> "rectangle-stack"
      "form" -> "document-text"
      "navigation" -> "bars-3"
      "layout" -> "squares-2x2"
      "icon" -> "star"
      "custom" -> "cube"
      _ -> "cube"
    end
  end

  defp category_color(category) do
    case category do
      "button" -> "blue"
      "card" -> "green"
      "form" -> "purple"
      "navigation" -> "orange"
      "layout" -> "pink"
      "icon" -> "yellow"
      "custom" -> "gray"
      _ -> "gray"
    end
  end

  @doc """
  Renders the components panel UI.

  The template includes:
  - Search bar for filtering components
  - Category filter dropdown
  - Folder-organized component list with expand/collapse
  - Component thumbnails with drag-and-drop support
  - Component metadata (name, category, description)
  """
  @impl true
  def render(assigns) do
    ~H"""
    <div class="h-full flex flex-col bg-white border-l border-gray-200">
      <!-- Header -->
      <div class="p-4 border-b border-gray-200">
        <h2 class="text-lg font-semibold text-gray-800">Components</h2>
        <p class="text-sm text-gray-500 mt-1">Drag to canvas to instantiate</p>
      </div>
      <!-- Search and Filter -->
      <div class="p-4 space-y-3 border-b border-gray-200">
        <!-- Search Input -->
        <div class="relative">
          <input
            type="text"
            phx-change="search"
            phx-target={@myself}
            phx-value-value={@search_query}
            phx-debounce="300"
            value={@search_query}
            placeholder="Search components..."
            class="w-full pl-10 pr-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
          />
          <svg
            class="absolute left-3 top-2.5 w-5 h-5 text-gray-400"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"
            />
          </svg>
        </div>
        <!-- Category Filter -->
        <div>
          <select
            phx-change="filter_category"
            phx-target={@myself}
            phx-value-category={@selected_category || ""}
            class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
          >
            <option value="">All Categories</option>
            <option value="button">Buttons</option>
            <option value="card">Cards</option>
            <option value="form">Forms</option>
            <option value="navigation">Navigation</option>
            <option value="layout">Layouts</option>
            <option value="icon">Icons</option>
            <option value="custom">Custom</option>
          </select>
        </div>
      </div>
      <!-- Component List -->
      <div class="flex-1 overflow-y-auto p-4">
        <%= if Enum.empty?(@filtered_components) do %>
          <div class="text-center py-8 text-gray-500">
            <svg
              class="mx-auto w-12 h-12 text-gray-400 mb-2"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M20 13V6a2 2 0 00-2-2H6a2 2 0 00-2 2v7m16 0v5a2 2 0 01-2 2H6a2 2 0 01-2-2v-5m16 0h-2.586a1 1 0 00-.707.293l-2.414 2.414a1 1 0 01-.707.293h-3.172a1 1 0 01-.707-.293l-2.414-2.414A1 1 0 006.586 13H4"
              />
            </svg>
            <p class="text-sm">No components found</p>
            <%= if @search_query != "" || @selected_category do %>
              <p class="text-xs mt-1">Try adjusting your search or filter</p>
            <% end %>
          </div>
        <% else %>
          <%= for {category, components} <- group_components_by_category(@filtered_components) do %>
            <div class="mb-4">
              <!-- Category Header -->
              <button
                phx-click="toggle_category"
                phx-target={@myself}
                phx-value-category={category}
                class="w-full flex items-center justify-between px-3 py-2 bg-gray-50 rounded-lg hover:bg-gray-100 transition-colors mb-2"
              >
                <div class="flex items-center gap-2">
                  <svg
                    class={"w-5 h-5 text-#{category_color(category)}-600 transition-transform #{if MapSet.member?(@expanded_categories, category), do: "rotate-90", else: ""}"}
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M9 5l7 7-7 7"
                    />
                  </svg>
                  <span class="font-medium text-gray-700 capitalize">{category}</span>
                  <span class="text-xs text-gray-500">({length(components)})</span>
                </div>
              </button>
              <!-- Component Cards -->
              <%= if MapSet.member?(@expanded_categories, category) do %>
                <div class="space-y-2 pl-2">
                  <%= for component <- components do %>
                    <div
                      id={"component-#{component.id}"}
                      draggable="true"
                      phx-hook="ComponentDraggable"
                      data-component-id={component.id}
                      class="group relative bg-white border border-gray-200 rounded-lg p-3 hover:border-blue-400 hover:shadow-md transition-all cursor-move"
                    >
                      <!-- Thumbnail -->
                      <div class="flex items-start gap-3">
                        <div class="flex-shrink-0 w-16 h-16 bg-gray-100 rounded-lg overflow-hidden border border-gray-200">
                          <img
                            src={generate_thumbnail_url(component)}
                            alt={component.name}
                            class="w-full h-full object-cover"
                          />
                        </div>
                        <!-- Info -->
                        <div class="flex-1 min-w-0">
                          <h3 class="font-medium text-gray-900 truncate">{component.name}</h3>
                          <p class="text-xs text-gray-500 capitalize mt-0.5">
                            {component.category || "custom"}
                          </p>
                          <%= if component.description do %>
                            <p class="text-xs text-gray-600 mt-1 line-clamp-2">
                              {component.description}
                            </p>
                          <% end %>
                        </div>
                      </div>
                      <!-- Drag Indicator -->
                      <div class="absolute top-2 right-2 opacity-0 group-hover:opacity-100 transition-opacity">
                        <svg class="w-5 h-5 text-gray-400" fill="currentColor" viewBox="0 0 24 24">
                          <path d="M9 3h2v2H9V3zm0 4h2v2H9V7zm0 4h2v2H9v-2zm0 4h2v2H9v-2zm0 4h2v2H9v-2zm4-16h2v2h-2V3zm0 4h2v2h-2V7zm0 4h2v2h-2v-2zm0 4h2v2h-2v-2zm0 4h2v2h-2v-2z" />
                        </svg>
                      </div>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>
          <% end %>
        <% end %>
      </div>
      <!-- Footer Info -->
      <div class="p-4 border-t border-gray-200 bg-gray-50">
        <div class="flex items-center justify-between text-xs text-gray-600">
          <span>{length(@filtered_components)} components</span>
          <span class="text-gray-500">
            Showing {length(@filtered_components)} of {length(@components)}
          </span>
        </div>
      </div>
    </div>
    """
  end
end
