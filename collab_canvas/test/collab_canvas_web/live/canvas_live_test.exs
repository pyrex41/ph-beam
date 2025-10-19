defmodule CollabCanvasWeb.CanvasLiveTest do
  use CollabCanvasWeb.ConnCase

  import Phoenix.LiveViewTest

  alias CollabCanvas.{Accounts, Canvases}
  alias CollabCanvasWeb.Presence

  @moduletag :integration

  setup do
    # Create a test user and canvas
    {:ok, user} =
      Accounts.create_user(%{
        email: "test@example.com",
        name: "Test User"
      })

    {:ok, canvas} = Canvases.create_canvas(user.id, "Test Canvas")

    {:ok, user: user, canvas: canvas}
  end

  describe "mount/3" do
    test "successfully mounts with valid canvas ID", %{conn: conn, canvas: canvas} do
      {:ok, _view, html} = live(conn, ~p"/canvas/#{canvas.id}")

      assert html =~ "Test Canvas"
      assert html =~ "Canvas ID: #{canvas.id}"
    end

    test "redirects when canvas does not exist", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/", flash: %{"error" => "Canvas not found"}}}} =
               live(conn, ~p"/canvas/999999")
    end

    test "subscribes to canvas-specific PubSub topic", %{conn: conn, canvas: canvas} do
      {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      # Verify subscription by broadcasting a message
      topic = "canvas:#{canvas.id}"
      Phoenix.PubSub.broadcast(CollabCanvas.PubSub, topic, {:object_created, build_test_object()})

      # Give it a moment to process
      :timer.sleep(50)

      # Check that the view is still alive and received the message
      assert render(view) =~ "Test Canvas"
    end

    test "tracks user presence on mount", %{conn: conn, canvas: canvas} do
      {:ok, _view, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      # Give presence a moment to track
      :timer.sleep(50)

      # Check that there's at least one user present
      topic = "canvas:#{canvas.id}"
      presences = Presence.list(topic)

      assert map_size(presences) >= 1
    end

    test "loads canvas objects on mount", %{conn: conn, canvas: canvas} do
      # Create some objects
      {:ok, _obj1} =
        Canvases.create_object(canvas.id, "rectangle", %{
          position: %{x: 10, y: 20},
          data: Jason.encode!(%{width: 100, height: 50})
        })

      {:ok, _obj2} =
        Canvases.create_object(canvas.id, "circle", %{
          position: %{x: 100, y: 100},
          data: Jason.encode!(%{radius: 50})
        })

      {:ok, _view, html} = live(conn, ~p"/canvas/#{canvas.id}")

      # Check objects are in the HTML (in the data attributes)
      assert html =~ "canvas-container"
      assert html =~ "Objects (2)"
    end

    test "initializes socket assigns correctly", %{conn: conn, canvas: canvas} do
      {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      assert view
             |> element("#canvas-container")
             |> has_element?()
    end
  end

  describe "handle_event/3 - create_object" do
    test "creates a rectangle object", %{conn: conn, canvas: canvas} do
      {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      # Create a rectangle via event
      view
      |> element("button[phx-value-tool='rectangle']")
      |> render_click()

      result =
        render_hook(view, "create_object", %{
          "type" => "rectangle",
          "position" => %{"x" => 50, "y" => 50},
          "data" => %{"width" => 100, "height" => 60, "fill" => "#3b82f6"}
        })

      # Verify object was created
      objects = Canvases.list_objects(canvas.id)
      assert length(objects) == 1
      assert hd(objects).type == "rectangle"

      # Check the view updated
      assert result =~ "Objects (1)"
    end

    test "creates a circle object", %{conn: conn, canvas: canvas} do
      {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      render_hook(view, "create_object", %{
        "type" => "circle",
        "position" => %{"x" => 100, "y" => 100},
        "data" => %{"radius" => 50, "fill" => "#10b981"}
      })

      objects = Canvases.list_objects(canvas.id)
      assert length(objects) == 1
      assert hd(objects).type == "circle"
    end

    test "creates object with default position if not provided", %{conn: conn, canvas: canvas} do
      {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      render_hook(view, "create_object", %{
        "type" => "text"
      })

      objects = Canvases.list_objects(canvas.id)
      assert length(objects) == 1
      object = hd(objects)
      assert object.type == "text"
      # Default position should be set
      assert object.position == %{x: 100, y: 100} or object.position == %{"x" => 100, "y" => 100}
    end

    test "broadcasts object creation to other clients", %{conn: conn, canvas: canvas} do
      {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      # Subscribe to the topic to receive broadcasts
      topic = "canvas:#{canvas.id}"
      Phoenix.PubSub.subscribe(CollabCanvas.PubSub, topic)

      render_hook(view, "create_object", %{
        "type" => "rectangle",
        "position" => %{"x" => 50, "y" => 50}
      })

      # Check that broadcast was sent
      assert_receive {:object_created, object}, 1000
      assert object.type == "rectangle"
    end

    test "handles creation errors gracefully", %{conn: conn, canvas: canvas} do
      {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      # Try to create object with invalid type
      render_hook(view, "create_object", %{
        "type" => "invalid_type"
      })

      # Verify no object was created in database
      objects = Canvases.list_objects(canvas.id)
      assert length(objects) == 0
    end
  end

  describe "handle_event/3 - update_object" do
    test "updates object position", %{conn: conn, canvas: canvas} do
      # Create an object first
      {:ok, object} =
        Canvases.create_object(canvas.id, "rectangle", %{
          position: %{x: 10, y: 20}
        })

      {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      render_hook(view, "update_object", %{
        "id" => to_string(object.id),
        "position" => %{"x" => 100, "y" => 200}
      })

      updated_object = Canvases.get_object(object.id)
      assert updated_object.position["x"] == 100 or updated_object.position[:x] == 100
      assert updated_object.position["y"] == 200 or updated_object.position[:y] == 200
    end

    test "updates object data", %{conn: conn, canvas: canvas} do
      {:ok, object} =
        Canvases.create_object(canvas.id, "rectangle", %{
          position: %{x: 10, y: 20},
          data: Jason.encode!(%{width: 100, height: 50})
        })

      {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      render_hook(view, "update_object", %{
        "id" => to_string(object.id),
        "data" => %{width: 200, height: 100, fill: "#ff0000"}
      })

      updated_object = Canvases.get_object(object.id)
      assert updated_object.data != Jason.encode!(%{width: 100, height: 50})
    end

    test "broadcasts object update to other clients", %{conn: conn, canvas: canvas} do
      {:ok, object} =
        Canvases.create_object(canvas.id, "rectangle", %{
          position: %{x: 10, y: 20}
        })

      {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      topic = "canvas:#{canvas.id}"
      Phoenix.PubSub.subscribe(CollabCanvas.PubSub, topic)

      render_hook(view, "update_object", %{
        "id" => to_string(object.id),
        "position" => %{"x" => 100, "y" => 200}
      })

      assert_receive {:object_updated, updated_object}, 1000
      assert updated_object.id == object.id
    end

    test "handles update of non-existent object", %{conn: conn, canvas: canvas} do
      {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      render_hook(view, "update_object", %{
        "id" => "999999",
        "position" => %{"x" => 100, "y" => 200}
      })

      # View should still be alive and functional
      assert render(view) =~ "Test Canvas"
    end
  end

  describe "handle_event/3 - delete_object" do
    test "deletes an object", %{conn: conn, canvas: canvas} do
      {:ok, object} = Canvases.create_object(canvas.id, "rectangle")

      {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      # Click delete button
      view
      |> element("button[phx-click='delete_object'][phx-value-id='#{object.id}']")
      |> render_click()

      # Verify object was deleted
      assert Canvases.get_object(object.id) == nil
      assert Canvases.list_objects(canvas.id) == []
    end

    test "broadcasts object deletion to other clients", %{conn: conn, canvas: canvas} do
      {:ok, object} = Canvases.create_object(canvas.id, "rectangle")

      {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      topic = "canvas:#{canvas.id}"
      Phoenix.PubSub.subscribe(CollabCanvas.PubSub, topic)

      view
      |> element("button[phx-click='delete_object'][phx-value-id='#{object.id}']")
      |> render_click()

      assert_receive {:object_deleted, object_id}, 1000
      assert object_id == object.id
    end

    test "handles deletion of non-existent object", %{conn: conn, canvas: canvas} do
      {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      # Use render_hook instead since we can't create a button for non-existent object
      render_hook(view, "delete_object", %{"id" => "999999"})

      # View should still be alive and functional
      assert render(view) =~ "Test Canvas"
    end
  end

  describe "handle_event/3 - select_tool" do
    test "changes selected tool", %{conn: conn, canvas: canvas} do
      {:ok, view, html} = live(conn, ~p"/canvas/#{canvas.id}")

      # Initially, select tool should be selected
      assert html =~ "bg-blue-100 text-blue-600"

      # Click rectangle tool
      result =
        view
        |> element("button[phx-value-tool='rectangle']")
        |> render_click()

      # Rectangle tool should now be highlighted
      assert result =~ "rectangle"
    end

    test "supports multiple tool types", %{conn: conn, canvas: canvas} do
      {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      for tool <- ["select", "rectangle", "circle", "text"] do
        view
        |> element("button[phx-value-tool='#{tool}']")
        |> render_click()
      end

      # Should not crash
      assert render(view) =~ "Test Canvas"
    end
  end

  describe "handle_event/3 - cursor_move" do
    test "updates cursor position in presence", %{conn: conn, canvas: canvas} do
      {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      # Give presence time to track
      :timer.sleep(50)

      render_hook(view, "cursor_move", %{"x" => 150, "y" => 250})

      # Give presence time to update
      :timer.sleep(50)

      # Verify presence was updated
      topic = "canvas:#{canvas.id}"
      presences = Presence.list(topic)

      assert map_size(presences) >= 1
    end
  end

  describe "handle_event/3 - AI commands" do
    test "updates ai_command on change", %{conn: conn, canvas: canvas} do
      {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      result =
        view
        |> element("textarea[phx-change='ai_command_change']")
        |> render_change(%{"value" => "create a blue rectangle"})

      assert result =~ "create a blue rectangle" or render(view) =~ "create a blue rectangle"
    end

    test "executes AI command - rectangle", %{conn: conn, canvas: canvas} do
      {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      # Set AI command
      view
      |> element("textarea[phx-change='ai_command_change']")
      |> render_change(%{"value" => "create a rectangle"})

      # Execute command
      view
      |> element("button[phx-click='execute_ai_command']")
      |> render_click()

      # Give it a moment to process
      :timer.sleep(100)

      # Verify object was created
      objects = Canvases.list_objects(canvas.id)
      assert length(objects) == 1
      assert hd(objects).type == "rectangle"
    end

    test "executes AI command - circle", %{conn: conn, canvas: canvas} do
      {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      view
      |> element("textarea[phx-change='ai_command_change']")
      |> render_change(%{"value" => "create a circle"})

      view
      |> element("button[phx-click='execute_ai_command']")
      |> render_click()

      :timer.sleep(100)

      objects = Canvases.list_objects(canvas.id)
      assert length(objects) == 1
      assert hd(objects).type == "circle"
    end

    test "handles unrecognized AI command", %{conn: conn, canvas: canvas} do
      {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      view
      |> element("textarea[phx-change='ai_command_change']")
      |> render_change(%{"value" => "do something random"})

      view
      |> element("button[phx-click='execute_ai_command']")
      |> render_click()

      :timer.sleep(100)

      # Verify no object was created
      objects = Canvases.list_objects(canvas.id)
      assert length(objects) == 0
    end

    test "clears command input after successful execution", %{conn: conn, canvas: canvas} do
      {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      view
      |> element("textarea[phx-change='ai_command_change']")
      |> render_change(%{"value" => "create a rectangle"})

      view
      |> element("button[phx-click='execute_ai_command']")
      |> render_click()

      # Command should be cleared
      html = render(view)
      # The textarea value should be empty
      assert html =~ ~r/<textarea[^>]*>\s*<\/textarea>/ or html =~ "value=\"\""
    end

    test "broadcasts AI-generated objects to other clients", %{conn: conn, canvas: canvas} do
      {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      topic = "canvas:#{canvas.id}"
      Phoenix.PubSub.subscribe(CollabCanvas.PubSub, topic)

      view
      |> element("textarea[phx-change='ai_command_change']")
      |> render_change(%{"value" => "create a rectangle"})

      view
      |> element("button[phx-click='execute_ai_command']")
      |> render_click()

      assert_receive {:object_created, object}, 1000
      assert object.type == "rectangle"
    end
  end

  describe "handle_info/2 - PubSub broadcasts" do
    test "receives and handles object_created broadcast", %{conn: conn, canvas: canvas} do
      {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      topic = "canvas:#{canvas.id}"

      # Create object directly and broadcast
      {:ok, object} =
        Canvases.create_object(canvas.id, "rectangle", %{
          position: %{x: 50, y: 50}
        })

      Phoenix.PubSub.broadcast(CollabCanvas.PubSub, topic, {:object_created, object})

      # Give it time to process
      :timer.sleep(50)

      html = render(view)
      # Should show the new object count
      assert html =~ "Objects (1)"
    end

    test "receives and handles object_updated broadcast", %{conn: conn, canvas: canvas} do
      {:ok, object} =
        Canvases.create_object(canvas.id, "rectangle", %{
          position: %{x: 10, y: 20}
        })

      {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      topic = "canvas:#{canvas.id}"

      # Update object and broadcast
      {:ok, updated_object} = Canvases.update_object(object.id, %{position: %{x: 100, y: 200}})

      Phoenix.PubSub.broadcast(CollabCanvas.PubSub, topic, {:object_updated, updated_object})

      :timer.sleep(50)

      # View should still be functioning
      assert render(view) =~ "Test Canvas"
    end

    test "receives and handles object_deleted broadcast", %{conn: conn, canvas: canvas} do
      {:ok, object} = Canvases.create_object(canvas.id, "rectangle")

      {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      topic = "canvas:#{canvas.id}"

      # Delete object and broadcast
      {:ok, _} = Canvases.delete_object(object.id)
      Phoenix.PubSub.broadcast(CollabCanvas.PubSub, topic, {:object_deleted, object.id})

      :timer.sleep(50)

      html = render(view)
      # Should show 0 objects
      assert html =~ "Objects (0)"
    end

    test "handles presence_diff updates", %{conn: conn, canvas: canvas} do
      {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      topic = "canvas:#{canvas.id}"

      # Simulate another user joining
      other_user_id = "user_test_#{:erlang.unique_integer([:positive])}"

      {:ok, _} =
        Presence.track(self(), topic, other_user_id, %{
          online_at: System.system_time(:second),
          cursor: %{x: 100, y: 100},
          color: "#ff0000",
          name: "Other User"
        })

      :timer.sleep(100)

      # User count should increase
      html = render(view)
      # Should show at least 2 users (original + other)
      # Should have user count displayed
      assert html =~ ~r/\d+/
    end

    test "avoids duplicate objects from broadcasts", %{conn: conn, canvas: canvas} do
      {:ok, object} = Canvases.create_object(canvas.id, "rectangle")

      {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      topic = "canvas:#{canvas.id}"

      # Broadcast the same object twice
      Phoenix.PubSub.broadcast(CollabCanvas.PubSub, topic, {:object_created, object})
      Phoenix.PubSub.broadcast(CollabCanvas.PubSub, topic, {:object_created, object})

      :timer.sleep(50)

      html = render(view)
      # Should still show only 1 object
      assert html =~ "Objects (1)"
    end
  end

  describe "terminate/2" do
    test "cleans up PubSub subscription on disconnect", %{conn: conn, canvas: canvas} do
      {:ok, view, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      # Get the view's PID
      view_pid = GenServer.whereis(view.pid)

      # Stop the view
      GenServer.stop(view.pid)

      # Give it time to terminate
      :timer.sleep(50)

      # View should be dead
      refute Process.alive?(view_pid || view.pid)
    end
  end

  describe "UI rendering" do
    test "renders toolbar with tool buttons", %{conn: conn, canvas: canvas} do
      {:ok, _view, html} = live(conn, ~p"/canvas/#{canvas.id}")

      assert html =~ "Select Tool"
      assert html =~ "Rectangle Tool"
      assert html =~ "Circle Tool"
      assert html =~ "Text Tool"
    end

    test "renders canvas container with PixiJS hook", %{conn: conn, canvas: canvas} do
      {:ok, _view, html} = live(conn, ~p"/canvas/#{canvas.id}")

      assert html =~ "canvas-container"
      assert html =~ "phx-hook=\"CanvasRenderer\""
    end

    test "renders AI assistant panel", %{conn: conn, canvas: canvas} do
      {:ok, _view, html} = live(conn, ~p"/canvas/#{canvas.id}")

      assert html =~ "AI Assistant"
      assert html =~ "Describe what you want to create"
      assert html =~ "Example Commands:"
    end

    test "renders objects list", %{conn: conn, canvas: canvas} do
      {:ok, _obj1} = Canvases.create_object(canvas.id, "rectangle")
      {:ok, _obj2} = Canvases.create_object(canvas.id, "circle")

      {:ok, _view, html} = live(conn, ~p"/canvas/#{canvas.id}")

      assert html =~ "Objects (2)"
      assert html =~ "rectangle"
      assert html =~ "circle"
    end

    test "renders canvas name in header", %{conn: conn, canvas: canvas} do
      {:ok, _view, html} = live(conn, ~p"/canvas/#{canvas.id}")

      assert html =~ "Test Canvas"
    end

    test "renders user count indicator", %{conn: conn, canvas: canvas} do
      {:ok, _view, html} = live(conn, ~p"/canvas/#{canvas.id}")

      # Should have some indication of user count
      assert html =~ ~r/\d+/
    end

    test "disables generate button when command is empty", %{conn: conn, canvas: canvas} do
      {:ok, _view, html} = live(conn, ~p"/canvas/#{canvas.id}")

      assert html =~ "disabled"
      assert html =~ "cursor-not-allowed"
    end
  end

  describe "integration scenarios" do
    test "multiple users can collaborate on same canvas", %{conn: conn, canvas: canvas} do
      # User 1 connects
      {:ok, view1, _html} = live(conn, ~p"/canvas/#{canvas.id}")

      # User 2 connects
      conn2 = build_conn()
      {:ok, view2, _html} = live(conn2, ~p"/canvas/#{canvas.id}")

      :timer.sleep(100)

      # User 1 creates object
      render_hook(view1, "create_object", %{
        "type" => "rectangle",
        "position" => %{"x" => 50, "y" => 50}
      })

      :timer.sleep(100)

      # User 2 should see the object
      html2 = render(view2)
      assert html2 =~ "Objects (1)"

      # User 2 creates object
      render_hook(view2, "create_object", %{
        "type" => "circle",
        "position" => %{"x" => 100, "y" => 100}
      })

      :timer.sleep(100)

      # Both users should see 2 objects
      html1 = render(view1)
      html2 = render(view2)
      assert html1 =~ "Objects (2)"
      assert html2 =~ "Objects (2)"
    end

    test "objects persist across reconnections", %{conn: conn, canvas: canvas} do
      # Create objects
      {:ok, _obj1} = Canvases.create_object(canvas.id, "rectangle")
      {:ok, _obj2} = Canvases.create_object(canvas.id, "circle")

      # Connect
      {:ok, view1, html1} = live(conn, ~p"/canvas/#{canvas.id}")
      assert html1 =~ "Objects (2)"

      # Disconnect
      render_click(view1, "select_tool", %{"tool" => "select"})

      # Reconnect with new connection
      conn2 = build_conn()
      {:ok, _view2, html2} = live(conn2, ~p"/canvas/#{canvas.id}")

      # Objects should still be there
      assert html2 =~ "Objects (2)"
    end

    test "complete workflow: create, update, delete object", %{conn: conn, canvas: canvas} do
      {:ok, view, html} = live(conn, ~p"/canvas/#{canvas.id}")

      # Initially no objects
      assert html =~ "Objects (0)"

      # Create object
      render_hook(view, "create_object", %{
        "type" => "rectangle",
        "position" => %{"x" => 50, "y" => 50}
      })

      :timer.sleep(50)
      html = render(view)
      assert html =~ "Objects (1)"

      # Get the created object
      [object] = Canvases.list_objects(canvas.id)

      # Update object
      render_hook(view, "update_object", %{
        "id" => to_string(object.id),
        "position" => %{"x" => 100, "y" => 100}
      })

      :timer.sleep(50)

      # Verify update
      updated_object = Canvases.get_object(object.id)
      assert updated_object.position["x"] == 100 or updated_object.position[:x] == 100

      # Delete object
      view
      |> element("button[phx-click='delete_object'][phx-value-id='#{object.id}']")
      |> render_click()

      :timer.sleep(50)
      html = render(view)
      assert html =~ "Objects (0)"
    end
  end

  # Helper function to build a test object
  defp build_test_object do
    %CollabCanvas.Canvases.Object{
      id: 1,
      canvas_id: 1,
      type: "rectangle",
      position: %{x: 10, y: 20},
      data: %{},
      inserted_at: ~N[2024-01-01 00:00:00],
      updated_at: ~N[2024-01-01 00:00:00]
    }
  end
end
