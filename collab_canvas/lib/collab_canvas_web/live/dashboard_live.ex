defmodule CollabCanvasWeb.DashboardLive do
  @moduledoc """
  LiveView module for the canvas dashboard and management interface.

  The DashboardLive module provides the main user interface for managing canvases,
  including listing all available canvases, creating new canvases, and deleting
  existing ones. This is the central hub where users can see all their canvases
  and navigate to individual canvas editing sessions.

  ## Features

  - **Canvas Listing**: Displays all canvases in the system with metadata including
    creator, creation date, and last updated timestamp
  - **Canvas Creation**: Interactive form for creating new named canvases
  - **Canvas Deletion**: Ability to delete canvases with confirmation
  - **User Access Control**: Requires authentication to access the dashboard
  - **Navigation**: Provides links to navigate to individual canvas editing interfaces

  ## Access Control

  This LiveView requires authentication. Unauthenticated users are redirected to
  the home page with a flash message indicating they must log in.

  ## State Management

  The module maintains the following socket assigns:
  - `:canvases` - List of all available canvases
  - `:user` / `:current_user` - The currently logged-in user
  - `:show_create_form` - Boolean flag controlling create form visibility
  - `:new_canvas_name` - String storing the new canvas name input

  ## Navigation Flow

  Users can navigate from this dashboard to individual canvas editing sessions by
  clicking "Open" on any canvas card, which redirects to `/canvas/:id` where the
  CanvasLive module takes over.
  """
  use CollabCanvasWeb, :live_view

  alias CollabCanvas.Canvases
  alias CollabCanvasWeb.Plugs.Auth

  @doc """
  Mounts the dashboard LiveView and loads user-specific canvas data.

  This callback is invoked when a user first navigates to the dashboard.
  It performs authentication checks and initializes the dashboard state.

  ## Parameters

  - `_params`: URL parameters (unused in this implementation)
  - `session`: The session map containing authentication tokens
  - `socket`: The LiveView socket

  ## Returns

  - `{:ok, socket}` with canvases loaded if user is authenticated
  - `{:ok, socket}` with redirect if user is not authenticated

  ## Authentication

  Uses the `Auth.assign_current_user/2` plug to verify authentication.
  If no user is found in the session, redirects to home page with an error flash.

  ## Initial State

  On successful mount, the socket is assigned:
  - All canvases in the system via `Canvases.list_all_canvases/0`
  - The authenticated user
  - `show_create_form: false` (form hidden by default)
  - `new_canvas_name: ""` (empty canvas name input)
  """
  @impl true
  def mount(_params, session, socket) do
    socket = Auth.assign_current_user(socket, session)

    case socket.assigns.current_user do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "You must be logged in to access the dashboard.")
         |> redirect(to: "/")}

      user ->
        canvases = Canvases.list_all_canvases()

        {:ok,
         socket
         |> assign(:canvases, canvases)
         |> assign(:user, user)
         |> assign(:show_create_form, false)
         |> assign(:new_canvas_name, "")}
    end
  end

  @doc """
  Toggles the visibility of the canvas creation form.

  This event handler shows or hides the inline form for creating a new canvas.
  It's triggered by clicking the "New Canvas" or "Cancel" button.

  ## Parameters

  - `_params`: Event parameters (unused)
  - `socket`: The current LiveView socket

  ## Returns

  - `{:noreply, socket}` with `:show_create_form` toggled

  ## Behavior

  Flips the boolean value of `socket.assigns.show_create_form`, causing the
  form to appear if it was hidden, or disappear if it was visible.
  """
  @impl true
  def handle_event("toggle_create_form", _params, socket) do
    {:noreply, assign(socket, :show_create_form, !socket.assigns.show_create_form)}
  end

  @doc """
  Updates the new canvas name input value in the socket state.

  This event handler is triggered when the user types in the canvas name input field.
  It captures the input value and stores it in the socket assigns for form state management.

  ## Parameters

  - `%{"value" => name}`: Event parameters containing the current input field value
  - `socket`: The current LiveView socket

  ## Returns

  - `{:noreply, socket}` with `:new_canvas_name` updated to the new value

  ## Usage

  Connected to the canvas name input field via `phx-blur="update_name"`, though
  could also be used with `phx-change` for real-time updates.
  """
  @impl true
  def handle_event("update_name", %{"value" => name}, socket) do
    {:noreply, assign(socket, :new_canvas_name, name)}
  end

  @doc """
  Creates a new canvas and updates the dashboard canvas list.

  This event handler processes canvas creation form submissions. It creates a new
  canvas associated with the current user, refreshes the canvas list, and navigates
  the user to the newly created canvas editing interface.

  ## Parameters

  - `%{"name" => name}`: Event parameters containing the canvas name from the form
  - `socket`: The current LiveView socket with the authenticated user

  ## Returns

  - `{:noreply, socket}` with updated state and navigation on success
  - `{:noreply, socket}` with error flash on failure

  ## Success Flow

  On successful canvas creation:
  1. Creates the canvas via `Canvases.create_canvas/2`
  2. Reloads the canvas list to include the new canvas
  3. Hides the creation form
  4. Clears the canvas name input
  5. Shows a success flash message
  6. Navigates to the new canvas editing page at `/canvas/:id`

  ## Error Handling

  If canvas creation fails (e.g., validation errors):
  1. Extracts error messages from the Ecto changeset
  2. Displays them in a flash message
  3. Keeps the form visible for correction

  ## Validation

  Canvas name validation is handled by the `Canvases.create_canvas/2` function
  and includes checks like presence, length constraints, etc.
  """
  @impl true
  def handle_event("create_canvas", %{"name" => name}, socket) do
    user = socket.assigns.current_user

    case Canvases.create_canvas(user.id, name) do
      {:ok, canvas} ->
        canvases = Canvases.list_all_canvases()

        {:noreply,
         socket
         |> assign(:canvases, canvases)
         |> assign(:show_create_form, false)
         |> assign(:new_canvas_name, "")
         |> put_flash(:info, "Canvas '#{canvas.name}' created successfully!")
         |> push_navigate(to: "/canvas/#{canvas.id}")}

      {:error, changeset} ->
        errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
        error_message = errors |> Map.values() |> List.flatten() |> Enum.join(", ")

        {:noreply,
         socket
         |> put_flash(:error, "Failed to create canvas: #{error_message}")}
    end
  end

  @doc """
  Deletes a canvas and refreshes the dashboard canvas list.

  This event handler processes canvas deletion requests. It deletes the specified
  canvas from the database and updates the UI to reflect the change.

  ## Parameters

  - `%{"id" => canvas_id_str}`: Event parameters containing the canvas ID as a string
  - `socket`: The current LiveView socket

  ## Returns

  - `{:noreply, socket}` with updated canvas list and success flash on success
  - `{:noreply, socket}` with error flash on failure

  ## Success Flow

  On successful canvas deletion:
  1. Converts the string canvas ID to an integer
  2. Deletes the canvas via `Canvases.delete_canvas/1`
  3. Reloads the canvas list without the deleted canvas
  4. Shows a success flash message with the deleted canvas name

  ## Error Handling

  If canvas deletion fails:
  1. Shows a generic error flash message
  2. Keeps the canvas in the list

  ## UI Confirmation

  The deletion button in the template includes a `data-confirm` attribute that
  shows a browser confirmation dialog before triggering this event handler,
  helping prevent accidental deletions.

  ## Authorization

  Currently, this handler doesn't check if the current user has permission to
  delete the canvas. Consider adding authorization checks in production.
  """
  @impl true
  def handle_event("delete_canvas", %{"id" => canvas_id_str}, socket) do
    canvas_id = String.to_integer(canvas_id_str)

    case Canvases.delete_canvas(canvas_id) do
      {:ok, canvas} ->
        canvases = Canvases.list_all_canvases()

        {:noreply,
         socket
         |> assign(:canvases, canvases)
         |> put_flash(:info, "Canvas '#{canvas.name}' deleted successfully.")}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to delete canvas.")}
    end
  end

  @doc """
  Renders the dashboard HTML template.

  This callback generates the HTML for the dashboard interface, including the
  header, canvas creation form, and canvas grid display.

  ## Parameters

  - `assigns`: Map of template assigns including:
    - `:current_user` - The authenticated user
    - `:canvases` - List of all canvases
    - `:show_create_form` - Boolean controlling form visibility
    - `:new_canvas_name` - Current value of the canvas name input

  ## Template Structure

  - **Header**: Displays user welcome message and navigation links (Home, Logout)
  - **Create Button**: Toggles the canvas creation form
  - **Create Form**: Inline form for creating new canvases (conditionally shown)
  - **Empty State**: Friendly message when no canvases exist
  - **Canvas Grid**: Responsive grid of canvas cards with Open and Delete actions

  ## Canvas Cards

  Each canvas card displays:
  - Canvas name
  - Creator information
  - Last updated timestamp
  - "Open" button linking to `/canvas/:id`
  - "Delete" button with confirmation dialog

  ## Responsive Design

  The grid uses Tailwind CSS classes for responsive layouts:
  - Mobile: Single column
  - Tablet (md): 2 columns
  - Desktop (lg): 3 columns
  """
  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-100">
      <div class="container mx-auto px-4 py-8">
        <!-- Header -->
        <header class="flex justify-between items-center mb-8">
          <div>
            <h1 class="text-3xl font-bold text-gray-900">My Canvases</h1>
            <p class="text-gray-600 mt-1">
              Welcome back, <%= @current_user.name || @current_user.email %>
            </p>
          </div>

          <div class="flex items-center gap-4">
            <a href="/" class="px-4 py-2 text-gray-700 hover:text-gray-900 transition">
              Home
            </a>
            <a
              href="/auth/logout"
              class="px-4 py-2 bg-red-500 text-white rounded-lg hover:bg-red-600 transition"
            >
              Logout
            </a>
          </div>
        </header>

        <!-- Create Canvas Button -->
        <div class="mb-6">
          <button
            phx-click="toggle_create_form"
            class="px-6 py-3 bg-indigo-600 text-white rounded-lg hover:bg-indigo-700 transition font-semibold"
          >
            <%= if @show_create_form, do: "Cancel", else: "+ New Canvas" %>
          </button>
        </div>

        <!-- Create Canvas Form -->
        <%= if @show_create_form do %>
          <div class="bg-white p-6 rounded-lg shadow-md mb-8">
            <h3 class="text-xl font-semibold mb-4">Create New Canvas</h3>
            <form phx-submit="create_canvas" class="flex gap-4">
              <input
                type="text"
                name="name"
                value={@new_canvas_name}
                phx-blur="update_name"
                placeholder="Canvas name..."
                class="flex-1 px-4 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-indigo-500"
                required
              />
              <button
                type="submit"
                class="px-6 py-2 bg-indigo-600 text-white rounded-lg hover:bg-indigo-700 transition"
              >
                Create
              </button>
            </form>
          </div>
        <% end %>

        <!-- Canvas List -->
        <%= if Enum.empty?(@canvases) do %>
          <div class="bg-white p-12 rounded-lg shadow-md text-center">
            <div class="text-6xl mb-4">🎨</div>
            <h3 class="text-2xl font-semibold text-gray-900 mb-2">No canvases yet</h3>
            <p class="text-gray-600 mb-6">
              Create your first canvas to start collaborating!
            </p>
            <button
              phx-click="toggle_create_form"
              class="px-6 py-3 bg-indigo-600 text-white rounded-lg hover:bg-indigo-700 transition font-semibold"
            >
              Create Canvas
            </button>
          </div>
        <% else %>
          <div class="grid md:grid-cols-2 lg:grid-cols-3 gap-6">
            <%= for canvas <- @canvases do %>
              <div class="bg-white p-6 rounded-lg shadow-md hover:shadow-lg transition">
                <h3 class="text-xl font-semibold text-gray-900 mb-2"><%= canvas.name %></h3>
                <p class="text-sm text-gray-600 mb-1">
                  Created by <%= canvas.user.name || canvas.user.email %>
                </p>
                <p class="text-sm text-gray-500 mb-4">
                  Updated <%= Calendar.strftime(canvas.updated_at, "%B %d, %Y") %>
                </p>

                <div class="flex gap-2">
                  <a
                    href={"/canvas/#{canvas.id}"}
                    class="flex-1 text-center px-4 py-2 bg-indigo-600 text-white rounded-lg hover:bg-indigo-700 transition"
                  >
                    Open
                  </a>
                  <button
                    phx-click="delete_canvas"
                    phx-value-id={canvas.id}
                    data-confirm="Are you sure you want to delete this canvas?"
                    class="px-4 py-2 bg-red-500 text-white rounded-lg hover:bg-red-600 transition"
                  >
                    Delete
                  </button>
                </div>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
