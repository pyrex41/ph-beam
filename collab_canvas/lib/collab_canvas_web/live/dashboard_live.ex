defmodule CollabCanvasWeb.DashboardLive do
  use CollabCanvasWeb, :live_view

  alias CollabCanvas.{Accounts, Canvases}
  alias CollabCanvasWeb.Plugs.Auth

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
        canvases = Canvases.list_user_canvases(user.id)

        {:ok,
         socket
         |> assign(:canvases, canvases)
         |> assign(:user, user)
         |> assign(:show_create_form, false)
         |> assign(:new_canvas_name, "")}
    end
  end

  @impl true
  def handle_event("toggle_create_form", _params, socket) do
    {:noreply, assign(socket, :show_create_form, !socket.assigns.show_create_form)}
  end

  @impl true
  def handle_event("update_name", %{"value" => name}, socket) do
    {:noreply, assign(socket, :new_canvas_name, name)}
  end

  @impl true
  def handle_event("create_canvas", %{"name" => name}, socket) do
    user = socket.assigns.current_user

    case Canvases.create_canvas(user.id, name) do
      {:ok, canvas} ->
        canvases = Canvases.list_user_canvases(user.id)

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

  @impl true
  def handle_event("delete_canvas", %{"id" => canvas_id_str}, socket) do
    canvas_id = String.to_integer(canvas_id_str)
    user = socket.assigns.current_user

    case Canvases.delete_canvas(canvas_id) do
      {:ok, canvas} ->
        canvases = Canvases.list_user_canvases(user.id)

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
