defmodule CollabCanvasWeb.CanvasLive do
  @moduledoc """
  LiveView for real-time collaborative canvas editing.

  This module provides a complete collaborative drawing canvas with real-time
  synchronization across multiple users. It combines Phoenix LiveView for
  server-side rendering with Phoenix PubSub for real-time updates, and
  Phoenix Presence for user tracking.

  ## Features

  ### Real-time Collaboration
  - Multiple users can edit the same canvas simultaneously
  - Changes are broadcast instantly to all connected clients via PubSub
  - Local state updates are optimized for immediate UI feedback
  - Prevents duplicate updates when the originating client receives broadcasts

  ### Canvas State Management
  - Maintains synchronized state of canvas objects (rectangles, circles, text)
  - Handles object creation, updates, and deletion with database persistence
  - Tracks object positions and properties (color, size, text content, etc.)
  - Objects are stored in the database and cached in LiveView assigns

  ### PubSub Architecture
  - Each canvas has a dedicated PubSub topic: "canvas:<canvas_id>"
  - Broadcasts three types of events: object_created, object_updated, object_deleted
  - All connected clients subscribe to their canvas topic on mount
  - Events are pushed to JavaScript via push_event for client-side rendering

  ### User Presence Tracking
  - Tracks all users currently viewing the canvas
  - Each user gets a unique color for visual identification
  - Real-time cursor position tracking shows where other users are pointing
  - Presence metadata includes: online_at, cursor position, color, name, email
  - Automatic cleanup when users disconnect

  ### AI-Powered Object Generation
  - Natural language commands to create objects: "Create a blue rectangle"
  - Async implementation using Task.async to prevent blocking the UI
  - 30-second timeout protection with graceful error handling
  - AI-generated objects are validated and broadcast to all clients
  - Uses Claude API (Anthropic) for command interpretation
  - Prevents duplicate AI requests while one is in progress

  ### Tool System
  - Multiple drawing tools: select, rectangle, circle, text, delete
  - Tool state is synchronized between server and client
  - Keyboard shortcuts for quick tool switching (S, R, C, T, D)
  - Tool selection is pushed to JavaScript hooks for client-side handling

  ## State Management

  The socket assigns include:
  - `:canvas` - The canvas struct with metadata
  - `:canvas_id` - Canvas identifier for PubSub topic
  - `:objects` - List of all canvas objects (synchronized)
  - `:user_id` - Unique identifier for the current user
  - `:topic` - PubSub topic string for this canvas
  - `:presences` - Map of all connected users and their metadata
  - `:selected_tool` - Currently active drawing tool
  - `:ai_command` - Current AI command text
  - `:ai_loading` - Boolean indicating AI processing state
  - `:ai_task_ref` - Reference to async AI task for monitoring

  ## Event Flow

  1. User performs action (e.g., creates object)
  2. Client sends event to LiveView via handle_event/3
  3. LiveView persists change to database
  4. LiveView broadcasts change to PubSub topic
  5. All connected clients (including originator) receive broadcast via handle_info/2
  6. Each client updates local state and pushes to JavaScript
  7. JavaScript hook updates the PixiJS canvas rendering

  ## Error Handling

  - Database operations return {:ok, result} or {:error, reason}
  - Errors are displayed to users via flash messages
  - AI tasks have timeout protection and crash recovery
  - Presence tracking is automatically cleaned up on disconnect
  """

  use CollabCanvasWeb, :live_view

  alias CollabCanvas.Canvases
  alias CollabCanvas.ColorPalettes
  alias CollabCanvas.AI.Agent
  alias CollabCanvasWeb.Presence
  alias CollabCanvasWeb.Plugs.Auth

  require Logger

  @doc """
  Mounts the LiveView and initializes the collaborative canvas session.

  ## Responsibilities

  1. Authenticates the user from session data
  2. Loads canvas data with associated objects from database
  3. Subscribes to canvas-specific PubSub topic for real-time updates
  4. Tracks user presence with cursor metadata
  5. Initializes socket assigns for canvas state

  ## Parameters

  - `params` - Map containing the canvas ID in the "id" key
  - `session` - Session data containing authentication information
  - `socket` - The LiveView socket

  ## Returns

  - `{:ok, socket}` - Successfully mounted with initialized state
  - `{:ok, socket}` - Redirects to home if canvas not found or user not authenticated

  ## Side Effects

  - Subscribes to PubSub topic "canvas:\#{canvas_id}"
  - Tracks user presence in Phoenix Presence
  - Assigns random color to user for cursor display
  """
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
      # Handle both success and already_tracked cases (can happen on page reload)
      case Presence.track(self(), topic, user_id, %{
          online_at: System.system_time(:second),
          cursor: nil,
          color: generate_user_color(),
          name: user.name || user.email,
          email: user.email
        }) do
        {:ok, _} -> :ok
        {:error, {:already_tracked, _, _, _}} -> :ok
      end

      # Load user's saved viewport position for this canvas
      viewport = Canvases.get_viewport(user.id, canvas_id)

      # Initialize socket state
      socket =
        socket
        |> assign(:canvas, canvas)
        |> assign(:canvas_id, canvas_id)
        |> assign(:objects, canvas.objects)
        |> assign(:user_id, user_id)
        |> assign(:topic, topic)
        |> assign(:presences, %{})
        |> assign(:selected_tool, "select")
        |> assign(:ai_command, "")
        |> assign(:ai_loading, false)
        |> assign(:ai_task_ref, nil)
        |> assign(:ai_interaction_history, [])
        |> assign(:show_labels, false)
        |> assign(:current_color, ColorPalettes.get_default_color(user.id))
        |> assign(:show_color_picker, false)

      # If viewport position exists, push it to the client to restore position
      socket =
        if viewport do
          push_event(socket, "restore_viewport", %{
            x: viewport.viewport_x,
            y: viewport.viewport_y,
            zoom: viewport.zoom
          })
        else
          socket
        end

      {:ok, socket}
    else
      # Canvas not found or user not authenticated
      {:ok,
       socket
       |> put_flash(:error, "Canvas not found or you must be logged in")
       |> redirect(to: "/")}
    end
  end

  @doc false
  # Helper function to generate a random color for user cursors
  # Returns one of 8 predefined colors for visual distinction between users
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

  @doc """
  Handles object creation events from the client.

  Creates a new canvas object (rectangle, circle, text, etc.) and broadcasts
  the change to all connected clients. The object is persisted to the database
  and immediately pushed to the JavaScript client for optimistic UI updates.

  ## Parameters

  - `params` - Map containing:
    - "type" - Object type (e.g., "rectangle", "circle", "text")
    - "position" - Map with x, y coordinates (optional, defaults to {100, 100})
    - "data" - Object-specific data (color, size, text, etc.) as JSON or map

  ## Broadcast

  Sends `{:object_created, object}` to PubSub topic for all clients to receive.

  ## Returns

  `{:noreply, socket}` with updated objects list or error flash message.
  """
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

  @doc """
  Handles object selection events from the client.

  Locks an object for editing when a user selects it, preventing other users
  from modifying it simultaneously.

  ## Parameters

  - `params` - Map containing:
    - "object_id" or "id" - ID of object to lock

  ## Broadcast

  Sends `{:object_locked, object}` to PubSub topic for all clients to receive.

  ## Returns

  `{:noreply, socket}` with locked object or error flash message.
  """
  @impl true
  def handle_event("lock_object", params, socket) do
    # Extract object_id from params (could be "id" or "object_id")
    object_id = params["object_id"] || params["id"]

    # Convert string ID to integer if needed
    object_id = if is_binary(object_id), do: String.to_integer(object_id), else: object_id

    user_id = socket.assigns.user_id

    case Canvases.lock_object(object_id, user_id) do
      {:ok, locked_object} ->
        # Broadcast to all connected clients
        Phoenix.PubSub.broadcast(
          CollabCanvas.PubSub,
          socket.assigns.topic,
          {:object_locked, locked_object}
        )

        # Update local state
        objects =
          Enum.map(socket.assigns.objects, fn obj ->
            if obj.id == locked_object.id, do: locked_object, else: obj
          end)

        {:noreply,
         socket
         |> assign(:objects, objects)
         |> push_event("object_locked", %{object: locked_object})}

      {:error, :already_locked} ->
        {:noreply, put_flash(socket, :error, "Object is currently being edited by another user")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Object not found")}
    end
  end

  @doc """
  Handles object deselection events from the client.

  Unlocks an object when a user deselects it, allowing other users to edit it.

  ## Parameters

  - `params` - Map containing:
    - "object_id" or "id" - ID of object to unlock

  ## Broadcast

  Sends `{:object_unlocked, object}` to PubSub topic for all clients to receive.

  ## Returns

  `{:noreply, socket}` with unlocked object.
  """
  @impl true
  def handle_event("unlock_object", params, socket) do
    # Extract object_id from params (could be "id" or "object_id")
    object_id = params["object_id"] || params["id"]

    # Convert string ID to integer if needed
    object_id = if is_binary(object_id), do: String.to_integer(object_id), else: object_id

    user_id = socket.assigns.user_id

    case Canvases.unlock_object(object_id, user_id) do
      {:ok, unlocked_object} ->
        # Broadcast to all connected clients
        Phoenix.PubSub.broadcast(
          CollabCanvas.PubSub,
          socket.assigns.topic,
          {:object_unlocked, unlocked_object}
        )

        # Update local state
        objects =
          Enum.map(socket.assigns.objects, fn obj ->
            if obj.id == unlocked_object.id, do: unlocked_object, else: obj
          end)

        {:noreply,
         socket
         |> assign(:objects, objects)
         |> push_event("object_unlocked", %{object: unlocked_object})}

      {:error, :not_locked_by_user} ->
        # Object was locked by someone else, but we still want to unlock it
        # This handles cases where the locking user disconnected
        case Canvases.unlock_object(object_id) do
          {:ok, unlocked_object} ->
            Phoenix.PubSub.broadcast(
              CollabCanvas.PubSub,
              socket.assigns.topic,
              {:object_unlocked, unlocked_object}
            )

            objects =
              Enum.map(socket.assigns.objects, fn obj ->
                if obj.id == unlocked_object.id, do: unlocked_object, else: obj
              end)

            {:noreply,
             socket
             |> assign(:objects, objects)
             |> push_event("object_unlocked", %{object: unlocked_object})}

          _ ->
            {:noreply, socket}
        end

      _ ->
        {:noreply, socket}
    end
  end

  @doc """
  Handles object update events from the client.

  Updates an existing canvas object's position or data properties and broadcasts
  the change to all connected clients. Common for drag operations and property
  changes.

  ## Parameters

  - `params` - Map containing:
    - "object_id" or "id" - ID of object to update
    - "position" - New position map with x, y coordinates (optional)
    - "data" - Updated object data as JSON or map (optional)

  ## Broadcast

  Sends `{:object_updated, object}` to PubSub topic for all clients to receive.

  ## Returns

  `{:noreply, socket}` with updated objects list or error flash message.
  """
  @impl true
  def handle_event("update_object", params, socket) do
    # Extract object_id from params (could be "id" or "object_id")
    object_id = params["object_id"] || params["id"]

    # Convert string ID to integer if needed
    object_id = if is_binary(object_id), do: String.to_integer(object_id), else: object_id

    user_id = socket.assigns.user_id

    # Check if object is locked by another user
    case Canvases.check_lock(object_id) do
      {:locked, locked_by} when locked_by != user_id ->
        {:noreply, put_flash(socket, :error, "Object is currently being edited by another user")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Object not found")}

      _ ->
        # Object is unlocked or locked by current user, proceed with update
        # Extract update attributes and convert data to JSON string if it's a map
        data =
          case params["data"] do
            data when is_map(data) and data != %{} -> Jason.encode!(data)
            data when is_binary(data) -> data
            nil -> nil
          end

        attrs =
          %{
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
  end

  @doc """
  Handles batch object update events from the client (for multi-object dragging).

  Updates multiple canvas objects in a single database transaction and broadcasts
  the changes to all connected clients. This is more efficient than individual
  updates when dragging multiple selected objects.

  ## Parameters

  - `params` - Map containing:
    - "updates" - List of update maps, each containing:
      - "object_id" or "id" - ID of object to update
      - "position" - New position map with x, y coordinates

  ## Broadcast

  Sends `{:objects_updated_batch, updated_objects}` to PubSub topic for all clients to receive.

  ## Transaction

  All updates are performed in a single database transaction for atomicity.
  If any update fails, all updates are rolled back.

  ## Returns

  `{:noreply, socket}` with updated objects list or error flash message.
  """
  @impl true
  def handle_event("update_objects_batch", %{"updates" => updates}, socket) when is_list(updates) do
    user_id = socket.assigns.user_id

    # Execute all updates in a transaction
    result = CollabCanvas.Repo.transaction(fn ->
      Enum.map(updates, fn update_params ->
        # Extract object_id from params
        object_id = update_params["object_id"] || update_params["id"]
        object_id = if is_binary(object_id), do: String.to_integer(object_id), else: object_id

        # Check if object is locked by another user
        case Canvases.check_lock(object_id) do
          {:locked, locked_by} when locked_by != user_id ->
            CollabCanvas.Repo.rollback({:error, :locked_by_another_user, object_id})

          {:error, :not_found} ->
            CollabCanvas.Repo.rollback({:error, :not_found, object_id})

          _ ->
            # Object is unlocked or locked by current user, proceed with update
            attrs = %{position: update_params["position"]}

            case Canvases.update_object(object_id, attrs) do
              {:ok, updated_object} -> updated_object
              {:error, :not_found} -> CollabCanvas.Repo.rollback({:error, :not_found, object_id})
              {:error, _changeset} -> CollabCanvas.Repo.rollback({:error, :update_failed, object_id})
            end
        end
      end)
    end)

    case result do
      {:ok, updated_objects} ->
        # Broadcast to all connected clients
        Phoenix.PubSub.broadcast(
          CollabCanvas.PubSub,
          socket.assigns.topic,
          {:objects_updated_batch, updated_objects}
        )

        # Update local state
        updated_ids = MapSet.new(updated_objects, & &1.id)
        objects =
          Enum.map(socket.assigns.objects, fn obj ->
            if MapSet.member?(updated_ids, obj.id) do
              Enum.find(updated_objects, obj, fn updated -> updated.id == obj.id end)
            else
              obj
            end
          end)

        # Push batch update to JavaScript
        {:noreply,
         socket
         |> assign(:objects, objects)
         |> push_event("objects_updated_batch", %{objects: updated_objects})}

      {:error, {error_type, object_id}} ->
        message = case error_type do
          :locked_by_another_user -> "Object #{object_id} is locked by another user"
          :not_found -> "Object #{object_id} not found"
          :update_failed -> "Failed to update object #{object_id}"
          _ -> "Batch update failed"
        end
        {:noreply, put_flash(socket, :error, message)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Batch update failed")}
    end
  end

  @doc """
  Handles object deletion events from the client.

  Deletes a canvas object from the database and broadcasts the deletion to all
  connected clients for immediate removal from their canvases.

  ## Parameters

  - `params` - Map containing:
    - "object_id" or "id" - ID of object to delete

  ## Broadcast

  Sends `{:object_deleted, object_id}` to PubSub topic for all clients to receive.

  ## Returns

  `{:noreply, socket}` with updated objects list or error flash message.
  """
  @impl true
  def handle_event("delete_object", params, socket) do
    # Extract object_id from params (could be "id" or "object_id")
    object_id = params["object_id"] || params["id"]

    # Convert string ID to integer if needed
    object_id = if is_binary(object_id), do: String.to_integer(object_id), else: object_id

    user_id = socket.assigns.user_id

    # Check if object is locked by another user
    case Canvases.check_lock(object_id) do
      {:locked, locked_by} when locked_by != user_id ->
        {:noreply, put_flash(socket, :error, "Object is currently being edited by another user")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Object not found")}

      _ ->
        # Object is unlocked or locked by current user, proceed with deletion
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
  end

  @doc """
  Handles AI command input changes from the client.

  Updates the AI command text in socket assigns as the user types in the
  AI assistant textarea. This maintains form state across renders.

  ## Parameters

  - `params` - Map containing "value" key with current command text

  ## Returns

  `{:noreply, socket}` with updated ai_command assign.
  """
  @impl true
  def handle_event("ai_command_change", %{"value" => command}, socket) do
    {:noreply, assign(socket, :ai_command, command)}
  end

  @doc """
  Handles AI command updates from JavaScript hooks (voice input, Enter key).

  Used by the VoiceInput hook to update the command as speech is transcribed,
  and by the AICommandInput hook to clear the field after Enter submission.
  """
  @impl true
  def handle_event("update_ai_command", %{"command" => command}, socket) do
    {:noreply, assign(socket, :ai_command, command)}
  end

  @doc """
  Handles AI command execution requests from the client (async, non-blocking).

  Spawns an async task to process the natural language command using Claude API.
  The task runs in the background and results are handled by handle_info/2 callbacks.
  Includes duplicate request prevention and 30-second timeout protection.

  ## Parameters

  - `params` - Map containing:
    - "command" - Natural language instruction
    - "selected_ids" - Optional list of selected object IDs for context

  ## Async Processing

  1. Spawns Task.async to call Agent.execute_command/3
  2. Sets 30-second timeout with Process.send_after/3
  3. Task completion handled by handle_info({ref, result}, socket)
  4. Task crash handled by handle_info({:DOWN, ref, ...}, socket)
  5. Timeout handled by handle_info({:ai_timeout, ref}, socket)

  ## Returns

  `{:noreply, socket}` with ai_loading=true and ai_task_ref set, or warning
  flash if a command is already in progress.

  ## Example Commands

  - "Create a blue rectangle"
  - "Add a green circle"
  - "Arrange selected objects horizontally"
  - "Align these objects to the top"
  """
  @impl true
  def handle_event("execute_ai_command", params, socket) do
    command = params["command"]
    selected_ids = Map.get(params, "selected_ids", [])

    # Prevent duplicate AI commands while one is in progress
    if socket.assigns.ai_loading do
      {:noreply, put_flash(socket, :warning, "AI command already in progress, please wait...")}
    else
      canvas_id = socket.assigns.canvas_id

      # Start async task with timeout (Task.async automatically links to current process)
      current_color = socket.assigns.current_color
      Logger.info("CanvasLive: Passing current_color to AI: #{current_color}")
      task =
        Task.async(fn ->
          Agent.execute_command(command, canvas_id, selected_ids, current_color: current_color)
        end)

      # Set loading state and store task reference for timeout monitoring
      Process.send_after(self(), {:ai_timeout, task.ref}, 30_000)

      # Add command to interaction history
      new_interaction = %{
        type: :user,
        content: command,
        timestamp: DateTime.utc_now()
      }

      history = [new_interaction | socket.assigns.ai_interaction_history]
      # Keep only last 20 interactions (10 command/response pairs)
      history = Enum.take(history, 20)

      {:noreply,
       socket
       |> assign(:ai_loading, true)
       |> assign(:ai_task_ref, task.ref)
       |> assign(:ai_interaction_history, history)
       |> clear_flash()}
    end
  end

  @doc """
  Handles tool selection events from the client.

  Updates the currently selected drawing tool and pushes the selection to
  JavaScript hooks for client-side behavior changes (cursor style, click handlers).

  ## Parameters

  - `params` - Map containing "tool" key with tool name

  ## Available Tools

  - "select" - Selection and move tool (keyboard: S)
  - "rectangle" - Rectangle drawing tool (keyboard: R)
  - "circle" - Circle drawing tool (keyboard: C)
  - "text" - Text insertion tool (keyboard: T)
  - "delete" - Object deletion tool (keyboard: D)

  ## Returns

  `{:noreply, socket}` with updated selected_tool assign and push_event to client.
  """
  @impl true
  def handle_event("select_tool", %{"tool" => tool}, socket) do
    # Push tool selection to JavaScript hook
    {:noreply,
     socket
     |> assign(:selected_tool, tool)
     |> push_event("tool_selected", %{tool: tool})}
  end

  @doc """
  Handles cursor position update events from the client.

  Updates the user's cursor position in Phoenix Presence, which is then
  broadcast to all other connected clients for real-time cursor tracking.

  ## Parameters

  - `params` - Map containing "position" with x, y coordinates in canvas space

  ## Side Effects

  Updates Presence metadata for current user with new cursor position.
  Other clients receive presence_diff broadcast and update cursor display.

  ## Returns

  `{:noreply, socket}` - State unchanged as cursor position is in Presence only.
  """
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

  @doc """
  Handles viewport position save events from the client.

  Saves the user's current viewport position and zoom level for this canvas,
  so they can return to the same position when they reload or revisit.

  ## Parameters

  - `params` - Map containing:
    - "x" - Viewport X coordinate
    - "y" - Viewport Y coordinate
    - "zoom" - Zoom level

  ## Returns

  `{:noreply, socket}` - State unchanged, viewport saved to database
  """
  @impl true
  def handle_event("save_viewport", %{"x" => x, "y" => y, "zoom" => zoom}, socket) do
    user = socket.assigns.current_user
    canvas_id = socket.assigns.canvas_id

    # Save viewport position asynchronously (don't block on response)
    Task.start(fn ->
      Canvases.save_viewport(user.id, canvas_id, %{
        viewport_x: x,
        viewport_y: y,
        zoom: zoom
      })
    end)

    {:noreply, socket}
  end

  @doc """
  Handles component instantiation via drag-and-drop from the components panel.

  Creates instances of the component at the specified position on the current canvas.
  Broadcasts the instantiation to all connected clients.

  ## Parameters

  - `params` - Map containing:
    - "component_id" - ID of component to instantiate
    - "position" - Map with x, y coordinates for placement

  ## Returns

  `{:noreply, socket}` with updated objects list or error flash message
  """
  @impl true
  def handle_event("instantiate_component", params, socket) do
    component_id = params["component_id"]
    component_id = if is_binary(component_id), do: String.to_integer(component_id), else: component_id

    position = params["position"]
    position = %{x: position["x"], y: position["y"]}

    canvas_id = socket.assigns.canvas_id

    case CollabCanvas.Components.instantiate_component(component_id, position, canvas_id: canvas_id) do
      {:ok, instances} ->
        # Broadcast to all connected clients
        Enum.each(instances, fn instance ->
          Phoenix.PubSub.broadcast(
            CollabCanvas.PubSub,
            socket.assigns.topic,
            {:object_created, instance}
          )
        end)

        # Update local state
        updated_objects = instances ++ socket.assigns.objects

        {:noreply,
         socket
         |> assign(:objects, updated_objects)
         |> put_flash(:info, "Component instantiated (#{length(instances)} objects created)")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Component not found")}

      {:error, reason} ->
        Logger.error("Failed to instantiate component: #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, "Failed to instantiate component")}
    end
  end

  @doc """
  Handles toggle_labels events from the UI toggle switch.

  Toggles the display of object labels on the canvas and updates the state.

  ## Parameters

  - No parameters needed, toggles the current state

  ## Returns

  `{:noreply, socket}` with updated show_labels state and push_event to client.
  """
  @impl true
  def handle_event("toggle_labels", _params, socket) do
    new_state = !socket.assigns.show_labels
    object_labels = generate_object_labels(socket.assigns.objects)

    {:noreply,
     socket
     |> assign(:show_labels, new_state)
     |> push_event("toggle_object_labels", %{show: new_state, labels: object_labels})}
  end

  @doc """
  Handles toggle_color_picker events from the left sidebar button.

  Toggles the visibility of the color picker popup.

  ## Returns

  `{:noreply, socket}` with updated show_color_picker state.
  """
  @impl true
  def handle_event("toggle_color_picker", _params, socket) do
    {:noreply, assign(socket, :show_color_picker, !socket.assigns.show_color_picker)}
  end

  @doc """
  Handles color picker color change messages from the ColorPicker component.

  Updates the current color in socket assigns, updates the component, and saves to recent colors.

  ## Parameters

  - `color` - Hex color string selected by the user
  - `user_id` - ID of the user who changed the color

  ## Returns

  `{:noreply, socket}` with updated current_color assign and component update pushed.
  """
  @impl true
  def handle_info({:color_changed, color, user_id}, socket) do
    # Extract numeric user ID from the "user_#{id}" format
    current_user = socket.assigns.current_user

    # Only update if this color change is for the current user
    if "user_#{current_user.id}" == user_id do
      # Save to recent colors (async, non-blocking)
      Task.start(fn ->
        ColorPalettes.add_recent_color(current_user.id, color)
      end)

      # Update the LiveComponent with the new color
      send_update(CollabCanvasWeb.Components.ColorPicker,
        id: "color-picker",
        current_color: color
      )

      # Push event to JavaScript to update current color in CanvasManager
      {:noreply,
       socket
       |> assign(:current_color, color)
       |> push_event("color_changed", %{color: color})}
    else
      {:noreply, socket}
    end
  end

  @doc """
  Handles debounced color save messages from the ColorPicker component.

  The ColorPicker component sends this message after a 500ms debounce delay
  when users interact with color sliders. This prevents excessive database
  writes during rapid slider movements.

  Note: The actual save is performed by the ColorPicker component itself,
  but messages sent via Process.send_after(self(), ...) in a LiveComponent
  are delivered to the parent LiveView. We handle it here to prevent crashes.

  ## Parameters

  - `color` - Hex color string to save as default

  ## Returns

  `{:noreply, socket}` - No state changes needed, save handled by component.
  """
  @impl true
  def handle_info({:save_default_color, _color}, socket) do
    # Debounced save is handled by ColorPicker component
    # This handler just prevents FunctionClauseError when message arrives
    {:noreply, socket}
  end

  @doc """
  Handles object_created broadcasts from PubSub (from other clients or AI).

  Adds newly created objects to local state and pushes to JavaScript for
  rendering. Includes deduplication logic to prevent showing the same object
  twice when the originating client receives its own broadcast.

  ## Parameters

  - `object` - The newly created canvas object struct

  ## Returns

  `{:noreply, socket}` with updated objects list and push_event to client,
  or unchanged socket if object already exists (deduplication).
  """
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

  @doc """
  Handles object_updated broadcasts from PubSub (from other clients).

  Updates the object in local state with the new properties and pushes to
  JavaScript for re-rendering. Common during drag operations or property changes.

  ## Parameters

  - `updated_object` - The updated canvas object struct with new properties

  ## Returns

  `{:noreply, socket}` with updated objects list and push_event to client.
  """
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

  @doc """
  Handles batch object updates broadcast from PubSub (from other clients).

  Updates multiple objects in local state with new properties and pushes to
  JavaScript for re-rendering. Used during multi-object dragging operations.

  ## Parameters

  - `updated_objects` - List of updated canvas object structs

  ## Returns

  `{:noreply, socket}` with updated objects list and push_event to client.
  """
  @impl true
  def handle_info({:objects_updated_batch, updated_objects}, socket) do
    # Create a map of updated objects for efficient lookup
    updated_map = Map.new(updated_objects, fn obj -> {obj.id, obj} end)

    # Update local state
    objects =
      Enum.map(socket.assigns.objects, fn obj ->
        Map.get(updated_map, obj.id, obj)
      end)

    {:noreply,
     socket
     |> assign(:objects, objects)
     |> push_event("objects_updated_batch", %{objects: updated_objects})}
  end

  @doc """
  Handles object_deleted broadcasts from PubSub (from other clients).

  Removes the deleted object from local state and pushes to JavaScript for
  removal from the canvas rendering.

  ## Parameters

  - `object_id` - ID of the deleted canvas object

  ## Returns

  `{:noreply, socket}` with updated objects list and push_event to client.
  """
  @impl true
  def handle_info({:object_deleted, object_id}, socket) do
    objects = Enum.reject(socket.assigns.objects, fn obj -> obj.id == object_id end)

    {:noreply,
     socket
     |> assign(:objects, objects)
     |> push_event("object_deleted", %{object_id: object_id})}
  end

  @doc """
  Handles object_locked broadcasts from PubSub (from other clients).

  Updates the object in local state to show it's locked and pushes to
  JavaScript for visual feedback (grayed out, different cursor).

  ## Parameters

  - `locked_object` - The object that was locked with locked_by field set

  ## Returns

  `{:noreply, socket}` with updated objects list and push_event to client.
  """
  @impl true
  def handle_info({:object_locked, locked_object}, socket) do
    objects =
      Enum.map(socket.assigns.objects, fn obj ->
        if obj.id == locked_object.id, do: locked_object, else: obj
      end)

    {:noreply,
     socket
     |> assign(:objects, objects)
     |> push_event("object_locked", %{object: locked_object})}
  end

  @doc """
  Handles object_unlocked broadcasts from PubSub (from other clients).

  Updates the object in local state to show it's unlocked and pushes to
  JavaScript for visual feedback (normal appearance).

  ## Parameters

  - `unlocked_object` - The object that was unlocked with locked_by set to nil

  ## Returns

  `{:noreply, socket}` with updated objects list and push_event to client.
  """
  @impl true
  def handle_info({:object_unlocked, unlocked_object}, socket) do
    objects =
      Enum.map(socket.assigns.objects, fn obj ->
        if obj.id == unlocked_object.id, do: unlocked_object, else: obj
      end)

    {:noreply,
     socket
     |> assign(:objects, objects)
     |> push_event("object_unlocked", %{object: unlocked_object})}
  end

  @doc """
  Handles presence_diff broadcasts from Phoenix Presence.

  Triggered when users join, leave, or update their presence metadata (cursor
  position). Fetches the latest presence list and pushes to JavaScript for
  updating user cursors and online user display.

  ## Presence Metadata

  - `online_at` - Unix timestamp when user joined
  - `cursor` - Map with x, y coordinates or nil
  - `color` - Hex color string for user identification
  - `name` - User display name
  - `email` - User email address

  ## Returns

  `{:noreply, socket}` with updated presences assign and push_event to client.
  """
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

  @doc """
  Handles successful AI task completion messages.

  Called when the async AI task spawned by execute_ai_command completes
  successfully. Processes the result, creates objects, broadcasts to all
  clients, and updates UI with success/error message.

  ## Parameters

  - `ref` - Task reference to match against ai_task_ref
  - `result` - AI execution result from Agent.execute_command/2

  ## Result Processing

  Extracts created objects from AI results, broadcasts them to all clients,
  and displays success message with count of objects created.

  ## Returns

  `{:noreply, socket}` with ai_loading=false, objects updated, and flash message,
  or unchanged socket if ref doesn't match current task.
  """
  @impl true
  def handle_info({ref, result}, socket) when is_reference(ref) do
    # Only process if this is our AI task
    if ref == socket.assigns.ai_task_ref do
      # Demonitor the task (cleanup)
      Process.demonitor(ref, [:flush])

      socket = process_ai_result(result, socket)

      {:noreply,
       socket
       |> assign(:ai_loading, false)
       |> assign(:ai_task_ref, nil)}
    else
      {:noreply, socket}
    end
  end

  @doc """
  Handles AI task failure or crash via process monitoring.

  Called when the async AI task process crashes or exits abnormally. Logs
  the error and displays user-friendly error message.

  ## Parameters

  - `ref` - Task reference to match against ai_task_ref
  - `reason` - Crash reason (exception, exit signal, etc.)

  ## Returns

  `{:noreply, socket}` with ai_loading=false and error flash message,
  or unchanged socket if ref doesn't match current task.
  """
  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, socket) when is_reference(ref) do
    # Only process if this is our AI task
    if ref == socket.assigns.ai_task_ref do
      Logger.error("AI task crashed: #{inspect(reason)}")

      {:noreply,
       socket
       |> assign(:ai_loading, false)
       |> assign(:ai_task_ref, nil)
       |> put_flash(:error, "AI processing failed unexpectedly")}
    else
      {:noreply, socket}
    end
  end

  @doc """
  Handles AI task timeout after 30 seconds.

  Called when the AI task takes longer than 30 seconds to complete. Resets
  loading state and displays timeout error message to the user.

  ## Parameters

  - `ref` - Task reference to match against ai_task_ref

  ## Returns

  `{:noreply, socket}` with ai_loading=false and timeout error message,
  or unchanged socket if ref doesn't match current task (already completed).
  """
  @impl true
  def handle_info({:ai_timeout, ref}, socket) when is_reference(ref) do
    # Only process if this is still the current task
    if ref == socket.assigns.ai_task_ref do
      Logger.warning("AI task timed out after 30 seconds")

      {:noreply,
       socket
       |> assign(:ai_loading, false)
       |> assign(:ai_task_ref, nil)
       |> put_flash(:error, "AI request timed out after 30 seconds. Please try again.")}
    else
      # Timeout for an old task that already completed, ignore
      {:noreply, socket}
    end
  end

  @doc """
  Cleanup when the LiveView process terminates.

  Unsubscribes from PubSub topic to prevent memory leaks. Presence tracking
  is automatically cleaned up when the process dies. Also unlocks any objects
  that were locked by this user.

  ## Parameters

  - `reason` - Termination reason (normal, crash, timeout, etc.)
  - `socket` - The LiveView socket

  ## Returns

  `:ok`
  """
  @impl true
  def terminate(_reason, socket) do
    # Unlock any objects locked by this user
    if Map.has_key?(socket.assigns, :user_id) do
      user_id = socket.assigns.user_id
      canvas_id = socket.assigns[:canvas_id]

      if canvas_id do
        # Find and unlock all objects locked by this user on this canvas
        locked_objects =
          Canvases.list_objects(canvas_id)
          |> Enum.filter(fn obj -> obj.locked_by == user_id end)

        Enum.each(locked_objects, fn obj ->
          Canvases.unlock_object(obj.id)
          # Broadcast unlock to other clients
          Phoenix.PubSub.broadcast(
            CollabCanvas.PubSub,
            socket.assigns.topic,
            {:object_unlocked, %{obj | locked_by: nil}}
          )
        end)
      end
    end

    # Unsubscribe from PubSub topic
    if Map.has_key?(socket.assigns, :topic) do
      Phoenix.PubSub.unsubscribe(CollabCanvas.PubSub, socket.assigns.topic)
    end

    # Presence tracking is automatically cleaned up when process dies
    :ok
  end

  @doc false
  # Private helper to generate human-readable labels for canvas objects.
  # Numbers all objects sequentially by creation time.
  # Returns a map of object_id => display_name (e.g., "Object 1", "Object 2")
  defp generate_object_labels(objects) do
    # Sort by insertion time (oldest first) and number sequentially
    objects
    |> Enum.sort_by(& &1.inserted_at, DateTime)
    |> Enum.with_index(1)
    |> Enum.map(fn {object, index} ->
      {object.id, "Object #{index}"}
    end)
    |> Map.new()
  end

  @doc false
  # Private helper to process AI agent results and update socket state.
  # Handles all possible result types from Agent.execute_command/2:
  # - {:ok, results} - Successfully created objects
  # - {:error, :canvas_not_found} - Canvas doesn't exist
  # - {:error, :missing_api_key} - Claude API key not configured
  # - {:error, {:api_error, status, body}} - API request failed
  # - {:error, {:request_failed, reason}} - Network/connection error
  # - {:error, :invalid_response_format} - AI response parsing failed
  # - {:error, reason} - Other errors
  defp process_ai_result(result, socket) do
    # Helper to add AI response to history
    add_ai_response = fn socket, response_text ->
      new_interaction = %{
        type: :ai,
        content: response_text,
        timestamp: DateTime.utc_now()
      }
      history = [new_interaction | socket.assigns.ai_interaction_history]
      # Keep only last 20 interactions
      history = Enum.take(history, 20)
      assign(socket, :ai_interaction_history, history)
    end

    case result do
      {:ok, {:text_response, text}} ->
        # AI asked for clarification or provided text response
        socket
        |> add_ai_response.(text)
        |> assign(:ai_command, "")
        |> put_flash(:info, text)

      {:ok, {:toggle_labels, show}} ->
        # AI requested to show/hide object labels
        # Generate display names for all objects
        object_labels = generate_object_labels(socket.assigns.objects)

        # Push event to JavaScript to render labels
        response = if(show, do: "✅ Object labels shown", else: "✅ Object labels hidden")
        socket
        |> add_ai_response.(response)
        |> push_event("toggle_object_labels", %{show: show, labels: object_labels})
        |> assign(:ai_command, "")
        |> assign(:show_labels, show)
        |> put_flash(:info, response)

      {:ok, results} when is_list(results) and length(results) == 0 ->
        # AI returned no tool calls - it either doesn't understand or can't perform the action
        socket
        |> assign(:ai_command, "")
        |> put_flash(:warning, "I couldn't perform that action. Try rephrasing your command or check if I have the right tools available.")

      {:ok, results} when is_list(results) ->
        # Check if this is a special non-object result (like toggle_labels)
        case results do
          [%{tool: "show_object_labels", result: {:ok, {:toggle_labels, show}}}] ->
            # Handle label toggle
            object_labels = generate_object_labels(socket.assigns.objects)

            socket
            |> push_event("toggle_object_labels", %{show: show, labels: object_labels})
            |> assign(:ai_command, "")
            |> assign(:show_labels, show)
            |> put_flash(:info, if(show, do: "Object labels shown", else: "Object labels hidden"))

          [%{tool: "select_objects_by_description", result: {:ok, %{selected_ids: selected_ids, description: description}}}] ->
            # Handle semantic selection - select objects matching the description
            response = "✅ Selected #{length(selected_ids)} objects matching: #{description}"
            socket
            |> add_ai_response.(response)
            |> push_event("select_objects", %{object_ids: selected_ids})
            |> assign(:selected_objects, selected_ids)
            |> assign(:ai_command, "")
            |> put_flash(:info, response)

          _ ->
            # Separate created objects from updated objects
            {created_objects, updated_objects} =
              results
              |> Enum.reduce({[], []}, fn result, {created, updated} ->
                case result do
                  # Handle create operations
                  %{tool: tool, result: {:ok, object}} when tool in ["create_shape", "create_text", "create_component"] and is_map(object) and is_map_key(object, :id) ->
                    {[object | created], updated}

                  # Handle update/move/arrange operations
                  %{tool: tool, result: {:ok, object}} when tool in ["move_object", "move_shape", "resize_object", "resize_shape", "rotate_object", "change_style", "update_text"] and is_map(object) and is_map_key(object, :id) ->
                    {created, [object | updated]}

                  # Handle arrange_objects which returns a success map
                  %{tool: "arrange_objects", result: {:ok, _success_map}, input: input} ->
                    # Fetch the actual updated objects from the database
                    object_ids = Map.get(input, "object_ids", [])
                    arranged_objects = Enum.map(object_ids, fn id ->
                      Canvases.get_object(id)
                    end) |> Enum.reject(&is_nil/1)
                    {created, arranged_objects ++ updated}

                  _ ->
                    {created, updated}
                end
              end)

        # Broadcast created objects
        Enum.each(created_objects, fn object ->
          Phoenix.PubSub.broadcast(
            CollabCanvas.PubSub,
            socket.assigns.topic,
            {:object_created, object}
          )
        end)

        # Broadcast updated objects
        Enum.each(updated_objects, fn object ->
          Phoenix.PubSub.broadcast(
            CollabCanvas.PubSub,
            socket.assigns.topic,
            {:object_updated, object}
          )
        end)

        # Update local state - merge created and updated
        new_created = created_objects
        existing_objects = socket.assigns.objects

        # Update existing objects with new data, add new objects
        updated_ids = MapSet.new(updated_objects, & &1.id)
        merged_objects =
          Enum.map(existing_objects, fn obj ->
            if MapSet.member?(updated_ids, obj.id) do
              Enum.find(updated_objects, obj, fn updated -> updated.id == obj.id end)
            else
              obj
            end
          end)

        final_objects = new_created ++ merged_objects

        total_count = length(created_objects) + length(updated_objects)

        message =
          if total_count > 0 do
            parts = []
            parts = if length(created_objects) > 0, do: ["created #{length(created_objects)}" | parts], else: parts
            parts = if length(updated_objects) > 0, do: ["updated #{length(updated_objects)}" | parts], else: parts
            "AI #{Enum.join(Enum.reverse(parts), " and ")} object(s) successfully"
          else
            "AI command processed (check canvas for results)"
          end

        # Push created objects to JavaScript
        socket_with_created = Enum.reduce(created_objects, socket, fn object, acc_socket ->
          push_event(acc_socket, "object_created", %{object: object})
        end)

        # Push updated objects to JavaScript for immediate rendering with animation
        socket_with_all = Enum.reduce(updated_objects, socket_with_created, fn object, acc_socket ->
          push_event(acc_socket, "object_updated", %{object: object, animate: true})
        end)

        socket_with_all
        |> add_ai_response.(message)
        |> assign(:objects, final_objects)
        |> assign(:ai_command, "")
        |> put_flash(:info, message)
        end

      {:error, :canvas_not_found} ->
        put_flash(socket, :error, "Canvas not found")

      {:error, :missing_api_key} ->
        put_flash(
          socket,
          :error,
          "AI API key not configured. Please set CLAUDE_API_KEY environment variable."
        )

      {:error, {:api_error, status, body}} ->
        Logger.error("AI API error: #{status} - #{inspect(body)}")

        error_msg =
          case body do
            %{"error" => %{"message" => msg}} when is_binary(msg) -> msg
            %{"error" => msg} when is_binary(msg) -> msg
            _ -> "AI API error (#{status})"
          end

        put_flash(socket, :error, error_msg)

      {:error, {:request_failed, reason}} ->
        Logger.error("AI request failed: #{inspect(reason)}")
        put_flash(socket, :error, "AI request failed: #{inspect(reason)}")

      {:error, :invalid_response_format} ->
        put_flash(socket, :error, "AI returned invalid response format")

      {:error, reason} ->
        Logger.error("AI command failed: #{inspect(reason)}")
        put_flash(socket, :error, "AI command failed: #{inspect(reason)}")
    end
  end

  @doc """
  Renders the canvas interface with toolbar, canvas area, and AI panel.

  The template includes:
  - Left toolbar with drawing tools and online user list
  - Center canvas area with PixiJS rendering via CanvasRenderer hook
  - Right AI assistant panel with command input and object list

  All real-time updates are handled via push_event to JavaScript hooks,
  which update the PixiJS canvas without full page re-renders.
  """
  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex h-screen bg-gray-100">
      <!-- Flash Messages -->
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />
      <.flash kind={:warning} flash={@flash} />

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

        <!-- Divider -->
        <div class="w-10 h-px bg-gray-300 my-2"></div>

        <!-- Color Picker Button -->
        <button
          phx-click="toggle_color_picker"
          class={[
            "w-12 h-12 rounded-lg flex items-center justify-center hover:bg-gray-100 transition-colors relative group border-2",
            @show_color_picker && "bg-blue-100 border-blue-500",
            !@show_color_picker && "border-gray-300"
          ]}
          title="Color Picker"
          style={"background-color: #{@current_color}"}
        >
          <svg class="w-6 h-6 text-white drop-shadow-md" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M7 21a4 4 0 01-4-4V5a2 2 0 012-2h4a2 2 0 012 2v12a4 4 0 01-4 4zm0 0h12a2 2 0 002-2v-4a2 2 0 00-2-2h-2.343M11 7.343l1.657-1.657a2 2 0 012.828 0l2.829 2.829a2 2 0 010 2.828l-8.486 8.485M7 17h.01"
            />
          </svg>
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
          style="min-width: 0; min-height: 0;"
          data-objects={Jason.encode!(@objects)}
          data-presences={Jason.encode!(@presences)}
          data-user-id={@user_id}
          data-current-color={@current_color}
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

        <div class="flex-1 flex flex-col">
          <!-- AI Interaction History -->
          <div class="flex-1 p-4 overflow-y-auto border-b border-gray-200">
            <h3 class="text-sm font-medium text-gray-700 mb-3">AI Interaction History</h3>
            <div class="space-y-2 flex flex-col-reverse">
              <%= if length(@ai_interaction_history) == 0 do %>
                <p class="text-sm text-gray-500 italic">No interactions yet. Enter a command below to get started.</p>
              <% else %>
                <%= for interaction <- @ai_interaction_history do %>
                  <div class={[
                    "p-2 rounded-lg text-sm",
                    interaction.type == :user && "bg-blue-50 border border-blue-200",
                    interaction.type == :ai && "bg-green-50 border border-green-200"
                  ]}>
                    <div class="flex items-start gap-2">
                      <span class={[
                        "font-semibold",
                        interaction.type == :user && "text-blue-700",
                        interaction.type == :ai && "text-green-700"
                      ]}>
                        <%= if interaction.type == :user do %>
                          You:
                        <% else %>
                          AI:
                        <% end %>
                      </span>
                      <span class="flex-1 text-gray-700"><%= interaction.content %></span>
                    </div>
                    <div class="text-xs text-gray-500 mt-1">
                      <%= Calendar.strftime(interaction.timestamp, "%H:%M:%S") %>
                    </div>
                  </div>
                <% end %>
              <% end %>
            </div>
          </div>

          <!-- AI Command Input -->
          <div class="p-4">
            <div class="space-y-4">
              <!-- AI Command Input -->
            <form phx-change="ai_command_change">
              <label class="block text-sm font-medium text-gray-700 mb-2">
                Command
              </label>
              <div class="relative">
                <textarea
                  id="ai-command-input"
                  name="value"
                  value={@ai_command}
                  disabled={@ai_loading}
                  phx-hook="AICommandInput"
                  class={[
                    "w-full px-3 py-2 pr-12 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent resize-none",
                    @ai_loading && "bg-gray-50 cursor-not-allowed"
                  ]}
                  rows="4"
                  placeholder="e.g., 'Create a blue rectangle' or 'Add a green circle' (Enter to submit, Shift+Enter for new line)"
                ><%= @ai_command %></textarea>

                <!-- Voice Input Button (Push-to-Talk) -->
                <button
                  type="button"
                  id="voice-input-button"
                  phx-hook="VoiceInput"
                  class="absolute right-2 top-2 p-2 rounded-lg bg-blue-500 hover:bg-blue-600 text-white transition-colors"
                  title="Hold to speak (push-to-talk)"
                  disabled={@ai_loading}
                >
                  <svg
                    class="w-5 h-5 mic-icon"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                    xmlns="http://www.w3.org/2000/svg"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M19 11a7 7 0 01-7 7m0 0a7 7 0 01-7-7m7 7v4m0 0H8m4 0h4m-4-8a3 3 0 01-3-3V5a3 3 0 116 0v6a3 3 0 01-3 3z"
                    />
                  </svg>
                  <span class="listening-indicator hidden absolute -top-1 -right-1 h-3 w-3">
                    <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-red-400 opacity-75"></span>
                    <span class="relative inline-flex rounded-full h-3 w-3 bg-red-500"></span>
                  </span>
                </button>
              </div>
            </form>

            <button
              id="ai-execute-button"
              phx-click="execute_ai_command"
              phx-value-command={@ai_command}
              disabled={@ai_command == "" || @ai_loading}
              class={[
                "w-full py-2 px-4 rounded-lg font-medium transition-colors flex items-center justify-center gap-2",
                (@ai_command == "" || @ai_loading) &&
                  "bg-gray-300 text-gray-500 cursor-not-allowed",
                @ai_command != "" && !@ai_loading &&
                  "bg-blue-600 text-white hover:bg-blue-700"
              ]}
            >
              <%= if @ai_loading do %>
                <svg
                  class="animate-spin h-5 w-5"
                  xmlns="http://www.w3.org/2000/svg"
                  fill="none"
                  viewBox="0 0 24 24"
                >
                  <circle
                    class="opacity-25"
                    cx="12"
                    cy="12"
                    r="10"
                    stroke="currentColor"
                    stroke-width="4"
                  >
                  </circle>
                  <path
                    class="opacity-75"
                    fill="currentColor"
                    d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
                  >
                  </path>
                </svg>
                Processing...
              <% else %>
                Generate
              <% end %>
            </button>
          </div>
          <!-- Example Commands -->
          <div class="mt-6">
            <h3 class="text-sm font-medium text-gray-700 mb-2">Example Commands:</h3>
            <ul class="text-sm text-gray-600 space-y-1">
              <li>• "Create a rectangle"</li>
              <li>• "Add a circle"</li>
              <li>• "Make a blue square"</li>
              <li class="text-blue-600 font-medium">• "Arrange selected horizontally"</li>
              <li class="text-blue-600 font-medium">• "Align selected objects to top"</li>
              <li class="text-blue-600 font-medium">• "Distribute vertically with 20px spacing"</li>
            </ul>
            <div class="mt-4 p-3 bg-blue-50 border border-blue-200 rounded-lg">
              <p class="text-xs text-blue-700">
                Tip: Select multiple objects (Shift+click) before using layout commands!
              </p>
            </div>
          </div>
        </div>
        <!-- Objects List -->
        <div class="border-t border-gray-200 p-4">
          <div class="flex items-center justify-between mb-3">
            <h3 class="text-sm font-medium text-gray-700">
              Objects (<%= length(@objects) %>)
            </h3>
            <!-- Show Labels Toggle -->
            <button
              phx-click="toggle_labels"
              class="flex items-center gap-2 group"
              title={if @show_labels, do: "Hide object labels", else: "Show object labels"}
            >
              <span class="text-xs text-gray-600 group-hover:text-gray-900">Labels</span>
              <div class={[
                "relative inline-flex h-5 w-9 items-center rounded-full transition-colors",
                @show_labels && "bg-blue-600",
                !@show_labels && "bg-gray-300"
              ]}>
                <span class={[
                  "inline-block h-4 w-4 transform rounded-full bg-white transition-transform",
                  @show_labels && "translate-x-5",
                  !@show_labels && "translate-x-1"
                ]} />
              </div>
            </button>
          </div>
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

      <!-- Color Picker Popup -->
      <%= if @show_color_picker do %>
        <div class="fixed inset-0 z-50">
          <div class="absolute inset-0 bg-black opacity-25" phx-click="toggle_color_picker"></div>
          <div class="absolute top-4 left-20 z-10">
            <.live_component
              module={CollabCanvasWeb.Components.ColorPicker}
              id="color-picker"
              user_id={@current_user.id}
              current_color={@current_color}
            />
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
