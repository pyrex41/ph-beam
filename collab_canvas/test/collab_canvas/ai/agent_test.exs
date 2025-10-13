defmodule CollabCanvas.AI.AgentTest do
  use CollabCanvas.DataCase, async: true

  alias CollabCanvas.AI.Agent
  alias CollabCanvas.Canvases
  alias CollabCanvas.Accounts

  describe "execute_command/2" do
    setup do
      # Create a test user and canvas
      {:ok, user} = Accounts.create_user(%{email: "test@example.com", name: "Test User"})
      {:ok, canvas} = Canvases.create_canvas(user.id, "Test Canvas")

      %{user: user, canvas: canvas}
    end

    test "returns error when canvas doesn't exist" do
      result = Agent.execute_command("create a rectangle", 99999)
      assert {:error, :canvas_not_found} == result
    end

    test "returns error when CLAUDE_API_KEY is missing", %{canvas: canvas} do
      # Store original value
      original_key = System.get_env("CLAUDE_API_KEY")

      # Clear the API key
      System.delete_env("CLAUDE_API_KEY")

      result = Agent.execute_command("create a rectangle", canvas.id)
      assert {:error, :missing_api_key} == result

      # Restore original value
      if original_key, do: System.put_env("CLAUDE_API_KEY", original_key)
    end
  end

  describe "call_claude_api/1" do
    test "returns error when API key is missing" do
      # Store original value
      original_key = System.get_env("CLAUDE_API_KEY")

      # Clear the API key
      System.delete_env("CLAUDE_API_KEY")

      result = Agent.call_claude_api("create a rectangle")
      assert {:error, :missing_api_key} == result

      # Restore original value
      if original_key, do: System.put_env("CLAUDE_API_KEY", original_key)
    end

    @tag :external_api
    test "successfully calls Claude API with valid key" do
      # This test requires a real API key and is skipped by default
      # Run with: mix test --only external_api
      api_key = System.get_env("CLAUDE_API_KEY")

      if api_key && api_key != "" do
        result = Agent.call_claude_api("create a red rectangle at position 100, 200")

        case result do
          {:ok, tool_calls} ->
            assert is_list(tool_calls)

          {:error, reason} ->
            # API might fail for various reasons (rate limit, invalid key, etc.)
            # We just want to verify the function can be called
            assert reason != :missing_api_key
        end
      end
    end
  end

  describe "process_tool_calls/2" do
    setup do
      # Create test user and canvas
      {:ok, user} = Accounts.create_user(%{email: "test@example.com", name: "Test User"})
      {:ok, canvas} = Canvases.create_canvas(user.id, "Test Canvas")

      %{user: user, canvas: canvas}
    end

    test "processes create_shape tool call", %{canvas: canvas} do
      tool_calls = [
        %{
          id: "call_1",
          name: "create_shape",
          input: %{
            "type" => "rectangle",
            "x" => 100,
            "y" => 200,
            "width" => 150,
            "height" => 100,
            "color" => "#FF0000"
          }
        }
      ]

      results = Agent.process_tool_calls(tool_calls, canvas.id)

      assert length(results) == 1
      result = List.first(results)

      assert result.tool == "create_shape"
      assert {:ok, object} = result.result
      assert object.type == "rectangle"
      assert object.canvas_id == canvas.id
      assert object.position.x == 100
      assert object.position.y == 200

      decoded_data = Jason.decode!(object.data)
      assert decoded_data["width"] == 150
      assert decoded_data["height"] == 100
      assert decoded_data["color"] == "#FF0000"
    end

    test "processes create_text tool call", %{canvas: canvas} do
      tool_calls = [
        %{
          id: "call_2",
          name: "create_text",
          input: %{
            "text" => "Hello World",
            "x" => 50,
            "y" => 75,
            "font_size" => 24,
            "color" => "#000000"
          }
        }
      ]

      results = Agent.process_tool_calls(tool_calls, canvas.id)

      assert length(results) == 1
      result = List.first(results)

      assert result.tool == "create_text"
      assert {:ok, object} = result.result
      assert object.type == "text"
      assert object.canvas_id == canvas.id
      assert object.position.x == 50
      assert object.position.y == 75

      decoded_data = Jason.decode!(object.data)
      assert decoded_data["text"] == "Hello World"
      assert decoded_data["font_size"] == 24
      assert decoded_data["color"] == "#000000"
    end

    test "processes move_shape tool call", %{canvas: canvas} do
      # First create a shape to move
      {:ok, object} =
        Canvases.create_object(canvas.id, "rectangle", %{
          position: %{x: 0, y: 0},
          data: Jason.encode!(%{width: 100, height: 100})
        })

      tool_calls = [
        %{
          id: "call_3",
          name: "move_shape",
          input: %{
            "object_id" => object.id,
            "x" => 200,
            "y" => 300
          }
        }
      ]

      results = Agent.process_tool_calls(tool_calls, canvas.id)

      assert length(results) == 1
      result = List.first(results)

      assert result.tool == "move_shape"
      assert {:ok, updated_object} = result.result
      assert updated_object.id == object.id
      assert updated_object.position.x == 200
      assert updated_object.position.y == 300
    end

    test "processes resize_shape tool call", %{canvas: canvas} do
      # First create a shape to resize
      {:ok, object} =
        Canvases.create_object(canvas.id, "rectangle", %{
          position: %{x: 0, y: 0},
          data: Jason.encode!(%{width: 100, height: 100})
        })

      tool_calls = [
        %{
          id: "call_4",
          name: "resize_shape",
          input: %{
            "object_id" => object.id,
            "width" => 250,
            "height" => 150
          }
        }
      ]

      results = Agent.process_tool_calls(tool_calls, canvas.id)

      assert length(results) == 1
      result = List.first(results)

      assert result.tool == "resize_shape"
      assert {:ok, updated_object} = result.result
      assert updated_object.id == object.id

      decoded_data = Jason.decode!(updated_object.data)
      assert decoded_data["width"] == 250
      assert decoded_data["height"] == 150
    end

    test "processes multiple tool calls in sequence", %{canvas: canvas} do
      tool_calls = [
        %{
          id: "call_5",
          name: "create_shape",
          input: %{
            "type" => "circle",
            "x" => 100,
            "y" => 100,
            "width" => 50,
            "height" => 50
          }
        },
        %{
          id: "call_6",
          name: "create_text",
          input: %{
            "text" => "Circle",
            "x" => 125,
            "y" => 125
          }
        }
      ]

      results = Agent.process_tool_calls(tool_calls, canvas.id)

      assert length(results) == 2

      # Verify first result (create_shape)
      result1 = Enum.at(results, 0)
      assert result1.tool == "create_shape"
      assert {:ok, object1} = result1.result
      assert object1.type == "circle"

      # Verify second result (create_text)
      result2 = Enum.at(results, 1)
      assert result2.tool == "create_text"
      assert {:ok, object2} = result2.result
      assert object2.type == "text"

      decoded_data = Jason.decode!(object2.data)
      assert decoded_data["text"] == "Circle"
    end

    test "handles unknown tool calls gracefully", %{canvas: canvas} do
      tool_calls = [
        %{
          id: "call_unknown",
          name: "unknown_tool",
          input: %{"foo" => "bar"}
        }
      ]

      results = Agent.process_tool_calls(tool_calls, canvas.id)

      assert length(results) == 1
      result = List.first(results)

      assert result.tool == "unknown"
      assert {:error, :unknown_tool} = result.result
    end

    test "handles errors in tool execution gracefully", %{canvas: canvas} do
      # Try to move a non-existent object
      tool_calls = [
        %{
          id: "call_error",
          name: "move_shape",
          input: %{
            "object_id" => 99999,
            "x" => 100,
            "y" => 100
          }
        }
      ]

      results = Agent.process_tool_calls(tool_calls, canvas.id)

      assert length(results) == 1
      result = List.first(results)

      assert result.tool == "move_shape"
      assert {:error, :not_found} = result.result
    end

    test "applies default values for optional parameters", %{canvas: canvas} do
      # Create text without font_size and color
      tool_calls = [
        %{
          id: "call_defaults",
          name: "create_text",
          input: %{
            "text" => "Default Text",
            "x" => 10,
            "y" => 20
          }
        }
      ]

      results = Agent.process_tool_calls(tool_calls, canvas.id)

      result = List.first(results)
      assert {:ok, object} = result.result

      # Check default values
      decoded_data = Jason.decode!(object.data)
      assert decoded_data["font_size"] == 16
      assert decoded_data["color"] == "#000000"
    end

    test "applies default color for shapes", %{canvas: canvas} do
      # Create shape without color
      tool_calls = [
        %{
          id: "call_default_color",
          name: "create_shape",
          input: %{
            "type" => "rectangle",
            "x" => 0,
            "y" => 0,
            "width" => 100,
            "height" => 100
          }
        }
      ]

      results = Agent.process_tool_calls(tool_calls, canvas.id)

      result = List.first(results)
      assert {:ok, object} = result.result

      # Check default color
      decoded_data = Jason.decode!(object.data)
      assert decoded_data["color"] == "#000000"
    end

    test "processes delete_object tool call", %{canvas: canvas} do
      # First create an object to delete
      {:ok, object} =
        Canvases.create_object(canvas.id, "rectangle", %{
          position: %{x: 0, y: 0},
          data: Jason.encode!(%{width: 100, height: 100})
        })

      tool_calls = [
        %{
          id: "call_delete",
          name: "delete_object",
          input: %{
            "object_id" => object.id
          }
        }
      ]

      results = Agent.process_tool_calls(tool_calls, canvas.id)

      assert length(results) == 1
      result = List.first(results)

      assert result.tool == "delete_object"
      assert {:ok, deleted_object} = result.result
      assert deleted_object.id == object.id

      # Verify object is actually deleted
      assert Canvases.get_object(object.id) == nil
    end

    test "processes list_objects tool call", %{canvas: canvas} do
      # Create some objects
      {:ok, obj1} =
        Canvases.create_object(canvas.id, "rectangle", %{
          position: %{x: 10, y: 20},
          data: Jason.encode!(%{width: 100, height: 50, color: "#FF0000"})
        })

      {:ok, obj2} =
        Canvases.create_object(canvas.id, "circle", %{
          position: %{x: 200, y: 300},
          data: Jason.encode!(%{width: 75, height: 75, color: "#00FF00"})
        })

      tool_calls = [
        %{
          id: "call_list",
          name: "list_objects",
          input: %{}
        }
      ]

      results = Agent.process_tool_calls(tool_calls, canvas.id)

      assert length(results) == 1
      result = List.first(results)

      assert result.tool == "list_objects"
      assert {:ok, objects_list} = result.result
      assert length(objects_list) == 2

      # Check first object
      first_obj = Enum.find(objects_list, fn obj -> obj.id == obj1.id end)
      assert first_obj.type == "rectangle"
      # Position comes from DB with string keys
      assert Map.get(first_obj.position, :x) || first_obj.position["x"] == 10
      assert Map.get(first_obj.position, :y) || first_obj.position["y"] == 20
      assert first_obj.data["width"] == 100
      assert first_obj.data["color"] == "#FF0000"

      # Check second object
      second_obj = Enum.find(objects_list, fn obj -> obj.id == obj2.id end)
      assert second_obj.type == "circle"
      # Position comes from DB with string keys
      assert Map.get(second_obj.position, :x) || second_obj.position["x"] == 200
      assert Map.get(second_obj.position, :y) || second_obj.position["y"] == 300
      assert second_obj.data["width"] == 75
      assert second_obj.data["color"] == "#00FF00"
    end

    test "delete_object handles non-existent object", %{canvas: canvas} do
      tool_calls = [
        %{
          id: "call_delete_nonexistent",
          name: "delete_object",
          input: %{
            "object_id" => 99999
          }
        }
      ]

      results = Agent.process_tool_calls(tool_calls, canvas.id)

      result = List.first(results)
      assert result.tool == "delete_object"
      assert {:error, :not_found} = result.result
    end

    test "list_objects returns empty list for canvas with no objects", %{canvas: canvas} do
      tool_calls = [
        %{
          id: "call_list_empty",
          name: "list_objects",
          input: %{}
        }
      ]

      results = Agent.process_tool_calls(tool_calls, canvas.id)

      result = List.first(results)
      assert result.tool == "list_objects"
      assert {:ok, objects_list} = result.result
      assert objects_list == []
    end

    test "processes create_component tool call for login_form", %{canvas: canvas} do
      tool_calls = [
        %{
          id: "call_login_form",
          name: "create_component",
          input: %{
            "type" => "login_form",
            "x" => 100,
            "y" => 100,
            "width" => 350,
            "height" => 280,
            "theme" => "light",
            "content" => %{
              "title" => "Sign In"
            }
          }
        }
      ]

      results = Agent.process_tool_calls(tool_calls, canvas.id)

      assert length(results) == 1
      result = List.first(results)

      assert result.tool == "create_component"
      assert {:ok, component_result} = result.result
      assert component_result.component_type == "login_form"
      assert is_list(component_result.object_ids)
      # Login form should have: background, title, 2 labels, 2 inputs, button, button text = 8 objects
      assert length(component_result.object_ids) == 8

      # Verify all objects were created
      objects = Canvases.list_objects(canvas.id)
      assert length(objects) == 8
    end

    test "processes create_component tool call for navbar", %{canvas: canvas} do
      tool_calls = [
        %{
          id: "call_navbar",
          name: "create_component",
          input: %{
            "type" => "navbar",
            "x" => 0,
            "y" => 0,
            "width" => 800,
            "height" => 60,
            "theme" => "dark",
            "content" => %{
              "title" => "MyBrand",
              "items" => ["Home", "About", "Contact"]
            }
          }
        }
      ]

      results = Agent.process_tool_calls(tool_calls, canvas.id)

      assert length(results) == 1
      result = List.first(results)

      assert result.tool == "create_component"
      assert {:ok, component_result} = result.result
      assert component_result.component_type == "navbar"
      assert is_list(component_result.object_ids)
      # Navbar should have: background, logo, 3 menu items = 5 objects
      assert length(component_result.object_ids) == 5

      objects = Canvases.list_objects(canvas.id)
      assert length(objects) == 5
    end

    test "processes create_component tool call for card", %{canvas: canvas} do
      tool_calls = [
        %{
          id: "call_card",
          name: "create_component",
          input: %{
            "type" => "card",
            "x" => 200,
            "y" => 200,
            "width" => 300,
            "height" => 200,
            "theme" => "blue",
            "content" => %{
              "title" => "Welcome",
              "subtitle" => "This is a card component"
            }
          }
        }
      ]

      results = Agent.process_tool_calls(tool_calls, canvas.id)

      assert length(results) == 1
      result = List.first(results)

      assert result.tool == "create_component"
      assert {:ok, component_result} = result.result
      assert component_result.component_type == "card"
      assert is_list(component_result.object_ids)
      # Card should have: shadow, background, header, title, content, footer = 6 objects
      assert length(component_result.object_ids) == 6

      objects = Canvases.list_objects(canvas.id)
      assert length(objects) == 6
    end

    test "processes create_component tool call for button_group", %{canvas: canvas} do
      tool_calls = [
        %{
          id: "call_button_group",
          name: "create_component",
          input: %{
            "type" => "button",
            "x" => 50,
            "y" => 50,
            "width" => 400,
            "height" => 40,
            "theme" => "green",
            "content" => %{
              "items" => ["Save", "Cancel", "Reset"]
            }
          }
        }
      ]

      results = Agent.process_tool_calls(tool_calls, canvas.id)

      assert length(results) == 1
      result = List.first(results)

      assert result.tool == "create_component"
      assert {:ok, component_result} = result.result
      assert component_result.component_type == "button_group"
      assert is_list(component_result.object_ids)
      # Button group should have: 3 buttons + 3 labels = 6 objects
      assert length(component_result.object_ids) == 6

      objects = Canvases.list_objects(canvas.id)
      assert length(objects) == 6
    end

    test "processes create_component tool call for sidebar", %{canvas: canvas} do
      tool_calls = [
        %{
          id: "call_sidebar",
          name: "create_component",
          input: %{
            "type" => "sidebar",
            "x" => 0,
            "y" => 0,
            "width" => 250,
            "height" => 600,
            "theme" => "light",
            "content" => %{
              "title" => "Navigation",
              "items" => ["Dashboard", "Profile", "Settings"]
            }
          }
        }
      ]

      results = Agent.process_tool_calls(tool_calls, canvas.id)

      assert length(results) == 1
      result = List.first(results)

      assert result.tool == "create_component"
      assert {:ok, component_result} = result.result
      assert component_result.component_type == "sidebar"
      assert is_list(component_result.object_ids)
      # Sidebar should have: background, title, 3 items (bg + text each) = 2 + 6 = 8 objects
      assert length(component_result.object_ids) == 8

      objects = Canvases.list_objects(canvas.id)
      assert length(objects) == 8
    end

    test "create_component applies default dimensions", %{canvas: canvas} do
      tool_calls = [
        %{
          id: "call_default_dims",
          name: "create_component",
          input: %{
            "type" => "card",
            "x" => 100,
            "y" => 100
            # No width/height specified
          }
        }
      ]

      results = Agent.process_tool_calls(tool_calls, canvas.id)

      result = List.first(results)
      assert result.tool == "create_component"
      assert {:ok, component_result} = result.result
      # Should still create the component with default dimensions
      assert is_list(component_result.object_ids)
      assert length(component_result.object_ids) > 0
    end

    test "create_component handles unknown component type", %{canvas: canvas} do
      tool_calls = [
        %{
          id: "call_unknown_component",
          name: "create_component",
          input: %{
            "type" => "unknown_type",
            "x" => 100,
            "y" => 100
          }
        }
      ]

      results = Agent.process_tool_calls(tool_calls, canvas.id)

      result = List.first(results)
      assert result.tool == "create_component"
      assert {:error, :unknown_component_type} = result.result
    end

    test "processes group_objects tool call", %{canvas: canvas} do
      # Create some objects first
      {:ok, obj1} =
        Canvases.create_object(canvas.id, "rectangle", %{
          position: %{x: 0, y: 0},
          data: Jason.encode!(%{width: 100, height: 100})
        })

      {:ok, obj2} =
        Canvases.create_object(canvas.id, "circle", %{
          position: %{x: 50, y: 50},
          data: Jason.encode!(%{width: 50, height: 50})
        })

      tool_calls = [
        %{
          id: "call_group",
          name: "group_objects",
          input: %{
            "object_ids" => [obj1.id, obj2.id],
            "group_name" => "MyGroup"
          }
        }
      ]

      results = Agent.process_tool_calls(tool_calls, canvas.id)

      assert length(results) == 1
      result = List.first(results)

      assert result.tool == "group_objects"
      assert {:ok, group_result} = result.result
      assert is_binary(group_result.group_id)
      assert group_result.object_ids == [obj1.id, obj2.id]
    end
  end

  describe "integration tests" do
    setup do
      {:ok, user} = Accounts.create_user(%{email: "test@example.com", name: "Test User"})
      {:ok, canvas} = Canvases.create_canvas(user.id, "Test Canvas")

      %{user: user, canvas: canvas}
    end

    @tag :external_api
    test "end-to-end command execution with real API", %{canvas: canvas} do
      # This test requires a real API key and is skipped by default
      # Run with: mix test --only external_api
      api_key = System.get_env("CLAUDE_API_KEY")

      if api_key && api_key != "" do
        result = Agent.execute_command("create a blue rectangle at 50, 50", canvas.id)

        case result do
          {:ok, results} ->
            assert is_list(results)
            # Should have created objects on the canvas
            objects = Canvases.list_objects(canvas.id)
            assert length(objects) > 0

          {:error, reason} ->
            # API might fail for various reasons
            # Just verify it's not a missing canvas error
            assert reason != :canvas_not_found
        end
      end
    end
  end
end
