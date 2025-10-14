defmodule CollabCanvasWeb.CanvasLive do
  @moduledoc """
  LiveView for real-time collaborative canvas editing.

  This module handles:
  - Canvas state management
  - Real-time object updates via PubSub
  - User presence tracking
  - AI-powered object generation
  - Cursor position tracking
  """

  use CollabCanvasWeb, :live_view

  alias CollabCanvas.Canvases
  alias CollabCanvasWeb.Presence
  alias CollabCanvasWeb.Plugs.Auth

  @impl true
  def mount(%{"id" => canvas_id}, session, socket) do
    # Load authenticated user
    socket = Auth.assign_current_user(socket, session)

    # Convert canvas_id to integer
    canvas_id = String.to_integer(canvas_id)

    # Load canvas data
    canvas = Canvases.get_canvas_with_preloads(canvas_id, [:objects])

    if canvas && socket.assigns.current_user do
      # Subscribe to canvas-specific PubSub topic for real-time updates
      topic = "canvas:#{canvas_id}"
      Phoenix.PubSub.subscribe(CollabCanvas.PubSub, topic)

      # Use authenticated user information
      user = socket.assigns.current_user
      user_id = "user_#{user.id}"

      # Track user presence (cursor will be set when user first moves mouse)
      {:ok, _} =
        Presence.track(self(), topic, user_id, %{
          online_at: System.system_time(:second),
          cursor: nil,
          color: generate_user_color(),
          name: user.name || user.email,
          email: user.email
        })

      # Initialize socket state
      {:ok,
       socket
       |> assign(:canvas, canvas)
       |> assign(:canvas_id, canvas_id)
       |> assign(:objects, canvas.objects)
       |> assign(:user_id, user_id)
       |> assign(:topic, topic)
       |> assign(:presences, %{})
       |> assign(:selected_tool, "select")
       |> assign(:ai_command, "")}
    else
      # Canvas not found or user not authenticated
      {:ok,
       socket
       |> put_flash(:error, "Canvas not found or you must be logged in")
       |> redirect(to: "/")}
    end
  end

  # Helper function to generate a random color for user cursors
  defp generate_user_color do
    colors = [
      "#3b82f6",
      "#ef4444",
      "#10b981",
      "#f59e0b",
      "#8b5cf6",
      "#ec4899",
      "#06b6d4",
      "#84cc16"
    ]

    Enum.random(colors)
  end

  # Handle object creation
  @impl true
  def handle_event("create_object", %{"type" => type} = params, socket) do
    canvas_id = socket.assigns.canvas_id

    # Extract object attributes and convert data to JSON string if it's a map
    data =
      case params["data"] do
        data when is_map(data) and data != %{} -> Jason.encode!(data)
        data when is_binary(data) -> data
        _ -> nil
      end

    attrs = %{
      position: params["position"] || %{x: 100, y: 100},
      data: data
    }

    case Canvases.create_object(canvas_id, type, attrs) do
      {:ok, object} ->
        # Broadcast to all connected clients (including other browser tabs)
        Phoenix.PubSub.broadcast(
          CollabCanvas.PubSub,
          socket.assigns.topic,
          {:object_created, object}
        )

        # Update local state and push to JavaScript immediately
        {:noreply,
         socket
         |> assign(:objects, [object | socket.assigns.objects])
         |> push_event("object_created", %{object: object})}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to create object")}
    end
  end

  # Handle object updates
  @impl true
  def handle_event("update_object", params, socket) do
    # Extract object_id from params (could be "id" or "object_id")
    object_id = params["object_id"] || params["id"]

    # Convert string ID to integer if needed
    object_id = if is_binary(object_id), do: String.to_integer(object_id), else: object_id

    # Extract update attributes and convert data to JSON string if it's a map
    data =
      case params["data"] do
        data when is_map(data) and data != %{} -> Jason.encode!(data)
        data when is_binary(data) -> data
        nil -> nil
      end

    attrs = %{
      position: params["position"],
      data: data
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()

    case Canvases.update_object(object_id, attrs) do
      {:ok, updated_object} ->
        # Broadcast to all connected clients
        Phoenix.PubSub.broadcast(
          CollabCanvas.PubSub,
          socket.assigns.topic,
          {:object_updated, updated_object}
        )

        # Update local state and push to JavaScript immediately
        objects =
          Enum.map(socket.assigns.objects, fn obj ->
            if obj.id == updated_object.id, do: updated_object, else: obj
          end)

        {:noreply,
         socket
         |> assign(:objects, objects)
         |> push_event("object_updated", %{object: updated_object})}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Object not found")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update object")}
    end
  end

  # Handle object deletion
  @impl true
  def handle_event("delete_object", params, socket) do
    # Extract object_id from params (could be "id" or "object_id")
    object_id = params["object_id"] || params["id"]

    # Convert string ID to integer if needed
    object_id = if is_binary(object_id), do: String.to_integer(object_id), else: object_id

    case Canvases.delete_object(object_id) do
      {:ok, _deleted_object} ->
        # Broadcast to all connected clients
        Phoenix.PubSub.broadcast(
          CollabCanvas.PubSub,
          socket.assigns.topic,
          {:object_deleted, object_id}
        )

        # Update local state and push to JavaScript immediately
        objects = Enum.reject(socket.assigns.objects, fn obj -> obj.id == object_id end)

        {:noreply,
         socket
         |> assign(:objects, objects)
         |> push_event("object_deleted", %{object_id: object_id})}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Object not found")}
    end
  end

  # Handle AI command input changes
  @impl true
  def handle_event("ai_command_change", %{"value" => command}, socket) do
    {:noreply, assign(socket, :ai_command, command)}
  end

  # Handle AI command execution
  @impl true
  def handle_event("execute_ai_command", %{"command" => command}, socket) do
    canvas_id = socket.assigns.canvas_id

    # TODO: Integrate with actual AI service (Task 17)
    # For now, create a placeholder response
    case process_ai_command(command, canvas_id) do
      {:ok, objects} ->
        # Broadcast AI-generated objects to all clients
        Enum.each(objects, fn object ->
          Phoenix.PubSub.broadcast(
            CollabCanvas.PubSub,
            socket.assigns.topic,
            {:object_created, object}
          )
        end)

        # Update local state
        updated_objects = objects ++ socket.assigns.objects

        {:noreply,
         socket
         |> assign(:objects, updated_objects)
         |> assign(:ai_command, "")
         |> put_flash(:info, "AI command executed successfully")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "AI command failed: #{reason}")}
    end
  end

  # Handle tool selection
  @impl true
  def handle_event("select_tool", %{"tool" => tool}, socket) do
    # Push tool selection to JavaScript hook
    {:noreply,
     socket
     |> assign(:selected_tool, tool)
     |> push_event("tool_selected", %{tool: tool})}
  end

  # Handle cursor position updates
  @impl true
  def handle_event("cursor_move", %{"position" => %{"x" => x, "y" => y}}, socket) do
    user_id = socket.assigns.user_id
    topic = socket.assigns.topic

    # Update presence with new cursor position
    Presence.update(self(), topic, user_id, fn meta ->
      Map.put(meta, :cursor, %{x: x, y: y})
    end)

    {:noreply, socket}
  end

  # Placeholder AI command processor (will be replaced with actual AI service)
  defp process_ai_command(command, canvas_id) do
    # Simple placeholder: create a rectangle based on command
    # Real implementation will use Task 17's AI service
    cond do
      String.contains?(String.downcase(command), "rectangle") ->
        attrs = %{
          position: %{x: 200, y: 200},
          data: Jason.encode!(%{width: 100, height: 60, fill: "#3b82f6"})
        }

        case Canvases.create_object(canvas_id, "rectangle", attrs) do
          {:ok, object} -> {:ok, [object]}
          {:error, _} -> {:error, "Failed to create object"}
        end

      String.contains?(String.downcase(command), "circle") ->
        attrs = %{
          position: %{x: 300, y: 300},
          data: Jason.encode!(%{radius: 50, fill: "#10b981"})
        }

        case Canvases.create_object(canvas_id, "circle", attrs) do
          {:ok, object} -> {:ok, [object]}
          {:error, _} -> {:error, "Failed to create object"}
        end

      true ->
        {:error, "Command not recognized. Try 'create a rectangle' or 'create a circle'"}
    end
  end

  # Handle object created broadcasts from other clients
  @impl true
  def handle_info({:object_created, object}, socket) do
    # Only update if this object isn't already in our list (avoid duplicates)
    exists? = Enum.any?(socket.assigns.objects, fn obj -> obj.id == object.id end)

    if exists? do
      {:noreply, socket}
    else
      {:noreply,
       socket
       |> assign(:objects, [object | socket.assigns.objects])
       |> push_event("object_created", %{object: object})}
    end
  end

  # Handle object updated broadcasts from other clients
  @impl true
  def handle_info({:object_updated, updated_object}, socket) do
    objects =
      Enum.map(socket.assigns.objects, fn obj ->
        if obj.id == updated_object.id, do: updated_object, else: obj
      end)

    {:noreply,
     socket
     |> assign(:objects, objects)
     |> push_event("object_updated", %{object: updated_object})}
  end

  # Handle object deleted broadcasts from other clients
  @impl true
  def handle_info({:object_deleted, object_id}, socket) do
    objects = Enum.reject(socket.assigns.objects, fn obj -> obj.id == object_id end)

    {:noreply,
     socket
     |> assign(:objects, objects)
     |> push_event("object_deleted", %{object_id: object_id})}
  end

  # Handle presence diff (user join/leave, cursor updates)
  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff", payload: _diff}, socket) do
    # Get current presences from the topic
    topic = socket.assigns.topic
    presences = Presence.list(topic)

    # Push presence updates to JavaScript
    {:noreply,
     socket
     |> assign(:presences, presences)
     |> push_event("presence_updated", %{presences: presences})}
  end

  # Cleanup when LiveView process terminates
  @impl true
  def terminate(_reason, socket) do
    # Unsubscribe from PubSub topic
    if Map.has_key?(socket.assigns, :topic) do
      Phoenix.PubSub.unsubscribe(CollabCanvas.PubSub, socket.assigns.topic)
    end

    # Presence tracking is automatically cleaned up when process dies
    :ok
  end

  # Render the canvas interface
  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex h-screen bg-gray-100">
      <!-- Toolbar -->
      <div class="w-16 bg-white border-r border-gray-200 flex flex-col items-center py-4 space-y-2">
        <button
          phx-click="select_tool"
          phx-value-tool="select"
          class={[
            "w-12 h-12 rounded-lg flex items-center justify-center hover:bg-gray-100 transition-colors relative group",
            @selected_tool == "select" && "bg-blue-100 text-blue-600"
          ]}
          title="Select Tool (S)"
        >
          <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M15 15l-2 5L9 9l11 4-5 2zm0 0l5 5M7.188 2.239l.777 2.897M5.136 7.965l-2.898-.777M13.95 4.05l-2.122 2.122m-5.657 5.656l-2.12 2.122"
            />
          </svg>
          <span class="absolute right-1 bottom-1 text-[10px] font-bold opacity-50">S</span>
        </button>

        <button
          phx-click="select_tool"
          phx-value-tool="rectangle"
          class={[
            "w-12 h-12 rounded-lg flex items-center justify-center hover:bg-gray-100 transition-colors relative group",
            @selected_tool == "rectangle" && "bg-blue-100 text-blue-600"
          ]}
          title="Rectangle Tool (R) - Click & drag to create"
        >
          <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <rect x="4" y="6" width="16" height="12" stroke-width="2" rx="2" />
          </svg>
          <span class="absolute right-1 bottom-1 text-[10px] font-bold opacity-50">R</span>
        </button>

        <button
          phx-click="select_tool"
          phx-value-tool="circle"
          class={[
            "w-12 h-12 rounded-lg flex items-center justify-center hover:bg-gray-100 transition-colors relative group",
            @selected_tool == "circle" && "bg-blue-100 text-blue-600"
          ]}
          title="Circle Tool (C) - Click & drag to create"
        >
          <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <circle cx="12" cy="12" r="8" stroke-width="2" />
          </svg>
          <span class="absolute right-1 bottom-1 text-[10px] font-bold opacity-50">C</span>
        </button>

        <button
          phx-click="select_tool"
          phx-value-tool="text"
          class={[
            "w-12 h-12 rounded-lg flex items-center justify-center hover:bg-gray-100 transition-colors relative group",
            @selected_tool == "text" && "bg-blue-100 text-blue-600"
          ]}
          title="Text Tool (T) - Click to add text"
        >
          <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M3 5h12M9 3v2m1.048 9.5A18.022 18.022 0 016.412 9m6.088 9h7M11 21l5-10 5 10M12.751 5C11.783 10.77 8.07 15.61 3 18.129"
            />
          </svg>
          <span class="absolute right-1 bottom-1 text-[10px] font-bold opacity-50">T</span>
        </button>

        <button
          phx-click="select_tool"
          phx-value-tool="delete"
          class={[
            "w-12 h-12 rounded-lg flex items-center justify-center hover:bg-gray-100 transition-colors relative group",
            @selected_tool == "delete" && "bg-red-100 text-red-600"
          ]}
          title="Delete Tool (D) - Click object to delete"
        >
          <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"
            />
          </svg>
          <span class="absolute right-1 bottom-1 text-[10px] font-bold opacity-50">D</span>
        </button>

        <div class="flex-1"></div>

        <!-- Keyboard shortcuts help -->
        <div class="text-[10px] text-gray-400 text-center px-1 leading-tight mb-2">
          <div class="mb-1">Space + Drag = Pan</div>
          <div class="mb-1">2-Finger Scroll = Pan</div>
          <div>Ctrl + Scroll = Zoom</div>
        </div>

        <!-- Online Users -->
        <div class="border-t border-gray-200 pt-2 mt-2">
          <div class="text-[10px] text-gray-500 text-center mb-2 font-medium">
            ONLINE (<%= map_size(@presences) %>)
          </div>
          <%= for {user_id, %{metas: [meta | _]}} <- @presences do %>
            <div
              class="w-12 h-12 rounded-lg flex items-center justify-center mb-1 text-white font-bold text-xs relative group"
              style={"background-color: #{meta.color}"}
              title={"#{meta.email}#{if user_id == @user_id, do: " (You)", else: ""}"}
            >
              <%= String.first(meta.email || meta.name || "?") %>
              <%= if user_id == @user_id do %>
                <div class="absolute -bottom-1 -right-1 w-3 h-3 bg-green-500 rounded-full border-2 border-white"></div>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>
      <!-- Main Canvas Area -->
      <div class="flex-1 flex flex-col">
        <!-- Top Bar -->
        <div class="h-14 bg-white border-b border-gray-200 flex items-center px-4">
          <h1 class="text-lg font-semibold text-gray-800"><%= @canvas.name %></h1>
          <div class="flex-1"></div>
          <span class="text-sm text-gray-500">
            Canvas ID: <%= @canvas_id %>
          </span>
        </div>
        <!-- Canvas Container -->
        <div
          id="canvas-container"
          phx-hook="CanvasRenderer"
          phx-update="ignore"
          class="flex-1 bg-white overflow-hidden"
          data-objects={Jason.encode!(@objects)}
          data-presences={Jason.encode!(@presences)}
          data-user-id={@user_id}
        >
          <!-- PixiJS will render here -->
        </div>
      </div>
      <!-- AI Panel -->
      <div class="w-80 bg-white border-l border-gray-200 flex flex-col">
        <div class="p-4 border-b border-gray-200">
          <h2 class="text-lg font-semibold text-gray-800">AI Assistant</h2>
          <p class="text-sm text-gray-500 mt-1">Describe what you want to create</p>
        </div>

        <div class="flex-1 p-4 overflow-y-auto">
          <div class="space-y-4">
            <!-- AI Command Input -->
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-2">
                Command
              </label>
              <textarea
                phx-change="ai_command_change"
                phx-value-value={@ai_command}
                value={@ai_command}
                class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent resize-none"
                rows="4"
                placeholder="e.g., 'Create a blue rectangle' or 'Add a green circle'"
              ><%= @ai_command %></textarea>
            </div>

            <button
              phx-click="execute_ai_command"
              phx-value-command={@ai_command}
              disabled={@ai_command == ""}
              class={[
                "w-full py-2 px-4 rounded-lg font-medium transition-colors",
                @ai_command == "" &&
                  "bg-gray-300 text-gray-500 cursor-not-allowed",
                @ai_command != "" &&
                  "bg-blue-600 text-white hover:bg-blue-700"
              ]}
            >
              Generate
            </button>
          </div>
          <!-- Example Commands -->
          <div class="mt-6">
            <h3 class="text-sm font-medium text-gray-700 mb-2">Example Commands:</h3>
            <ul class="text-sm text-gray-600 space-y-1">
              <li>• "Create a rectangle"</li>
              <li>• "Add a circle"</li>
              <li>• "Make a blue square"</li>
            </ul>
          </div>
        </div>
        <!-- Objects List -->
        <div class="border-t border-gray-200 p-4">
          <h3 class="text-sm font-medium text-gray-700 mb-2">
            Objects (<%= length(@objects) %>)
          </h3>
          <div class="space-y-1 max-h-40 overflow-y-auto">
            <%= for object <- @objects do %>
              <div class="flex items-center justify-between text-sm py-1">
                <span class="text-gray-600"><%= object.type %></span>
                <button
                  phx-click="delete_object"
                  phx-value-id={object.id}
                  class="text-red-600 hover:text-red-800"
                  title="Delete"
                >
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"
                    />
                  </svg>
                </button>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
