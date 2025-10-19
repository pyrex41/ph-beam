defmodule CollabCanvas.AI.BatchProcessorTest do
  use CollabCanvas.DataCase
  alias CollabCanvas.AI.BatchProcessor
  alias CollabCanvas.Canvases

  describe "is_create_tool?/1" do
    test "returns true for create_shape" do
      assert BatchProcessor.is_create_tool?(%{name: "create_shape"})
    end

    test "returns true for create_text" do
      assert BatchProcessor.is_create_tool?(%{name: "create_text"})
    end

    test "returns false for other tools" do
      refute BatchProcessor.is_create_tool?(%{name: "move_object"})
      refute BatchProcessor.is_create_tool?(%{name: "delete_object"})
      refute BatchProcessor.is_create_tool?(%{name: "arrange_objects"})
    end
  end

  describe "build_object_attrs_from_tool_call/3" do
    test "builds single shape attrs" do
      tool_call = %{
        name: "create_shape",
        input: %{"type" => "rectangle", "x" => 10, "y" => 20, "width" => 100, "height" => 50}
      }

      normalize_color = fn color -> color end

      {attrs_list, count} =
        BatchProcessor.build_object_attrs_from_tool_call(tool_call, "#000000", normalize_color)

      assert length(attrs_list) == 1
      assert count == 1

      [attrs] = attrs_list
      assert attrs.type == "rectangle"
      assert attrs.position == %{x: 10, y: 20}

      data = Jason.decode!(attrs.data)
      assert data["width"] == 100
      assert data["height"] == 50
      assert data["color"] == "#000000"
    end

    test "builds multiple shape attrs with count parameter" do
      tool_call = %{
        name: "create_shape",
        input: %{
          "type" => "circle",
          "x" => 0,
          "y" => 0,
          "width" => 50,
          "height" => 50,
          "count" => 3
        }
      }

      normalize_color = fn color -> color end

      {attrs_list, count} =
        BatchProcessor.build_object_attrs_from_tool_call(tool_call, "#FF0000", normalize_color)

      assert length(attrs_list) == 3
      assert count == 3

      # Verify each shape has proper spacing
      [first, second, third] = attrs_list
      assert first.position.x == 0
      # 50 * 2.5 spacing
      assert second.position.x == 125
      assert third.position.x == 250
    end

    test "builds text attrs" do
      tool_call = %{
        name: "create_text",
        input: %{"text" => "Hello World", "x" => 100, "y" => 200, "font_size" => 24}
      }

      normalize_color = fn color -> color end

      {attrs_list, count} =
        BatchProcessor.build_object_attrs_from_tool_call(tool_call, "#333333", normalize_color)

      assert length(attrs_list) == 1
      assert count == 1

      [attrs] = attrs_list
      assert attrs.type == "text"
      assert attrs.position == %{x: 100, y: 200}

      data = Jason.decode!(attrs.data)
      assert data["text"] == "Hello World"
      assert data["font_size"] == 24
      assert data["color"] == "#333333"
    end
  end

  describe "execute_batched_creates/4 integration" do
    setup do
      user = insert_user()
      {:ok, canvas} = Canvases.create_canvas(user.id, "Test Canvas")
      %{canvas: canvas}
    end

    test "executes batch of create_shape calls", %{canvas: canvas} do
      tool_calls = [
        %{
          id: "t1",
          name: "create_shape",
          input: %{"type" => "rectangle", "x" => 10, "y" => 10, "width" => 100, "height" => 50}
        },
        %{
          id: "t2",
          name: "create_shape",
          input: %{"type" => "circle", "x" => 200, "y" => 10, "width" => 60, "height" => 60}
        }
      ]

      normalize_color = fn color -> String.upcase(color) end

      results =
        BatchProcessor.execute_batched_creates(tool_calls, canvas.id, "#ff0000", normalize_color)

      assert length(results) == 2

      # Verify first result
      assert %{tool: "create_shape", input: input1, result: {:ok, obj1}} = Enum.at(results, 0)
      assert input1["type"] == "rectangle"
      assert obj1.type == "rectangle"

      # Verify second result
      assert %{tool: "create_shape", input: input2, result: {:ok, obj2}} = Enum.at(results, 1)
      assert input2["type"] == "circle"
      assert obj2.type == "circle"

      # Verify objects were actually created
      objects = Canvases.list_objects(canvas.id)
      assert length(objects) == 2
    end

    test "executes batch with count parameter", %{canvas: canvas} do
      tool_calls = [
        %{
          id: "t1",
          name: "create_shape",
          input: %{
            "type" => "rectangle",
            "x" => 0,
            "y" => 0,
            "width" => 50,
            "height" => 30,
            "count" => 5
          }
        }
      ]

      normalize_color = fn color -> color end

      results =
        BatchProcessor.execute_batched_creates(tool_calls, canvas.id, "#0000ff", normalize_color)

      assert length(results) == 1

      # Verify result has multiple objects
      [result] = results

      assert %{tool: "create_shape", result: {:ok, %{count: 5, total: 5, objects: objects}}} =
               result

      assert length(objects) == 5

      # Verify objects were created
      db_objects = Canvases.list_objects(canvas.id)
      assert length(db_objects) == 5
    end

    test "combines create_shape and create_text calls", %{canvas: canvas} do
      tool_calls = [
        %{
          id: "t1",
          name: "create_shape",
          input: %{"type" => "rectangle", "x" => 10, "y" => 10, "width" => 100, "height" => 50}
        },
        %{
          id: "t2",
          name: "create_text",
          input: %{"text" => "Test", "x" => 50, "y" => 50}
        }
      ]

      normalize_color = fn color -> color end

      results =
        BatchProcessor.execute_batched_creates(tool_calls, canvas.id, "#000000", normalize_color)

      assert length(results) == 2

      # Verify both objects created
      objects = Canvases.list_objects(canvas.id)
      assert length(objects) == 2
      assert Enum.any?(objects, fn obj -> obj.type == "rectangle" end)
      assert Enum.any?(objects, fn obj -> obj.type == "text" end)
    end
  end

  describe "combine_results_in_order/3" do
    test "maintains original order with mixed create and non-create calls" do
      original_calls = [
        %{id: "t1", name: "create_shape", input: %{"type" => "rect"}},
        %{id: "t2", name: "move_object", input: %{"object_id" => 1}},
        %{id: "t3", name: "create_text", input: %{"text" => "Hi"}},
        %{id: "t4", name: "delete_object", input: %{"object_id" => 2}},
        %{id: "t5", name: "create_shape", input: %{"type" => "circle"}}
      ]

      batch_results = [
        %{tool: "create_shape", input: %{"type" => "rect"}, result: {:ok, %{id: 10}}},
        %{tool: "create_text", input: %{"text" => "Hi"}, result: {:ok, %{id: 11}}},
        %{tool: "create_shape", input: %{"type" => "circle"}, result: {:ok, %{id: 12}}}
      ]

      other_results = [
        %{tool: "move_object", input: %{"object_id" => 1}, result: {:ok, %{}}},
        %{tool: "delete_object", input: %{"object_id" => 2}, result: {:ok, %{}}}
      ]

      combined =
        BatchProcessor.combine_results_in_order(original_calls, batch_results, other_results)

      assert length(combined) == 5
      assert Enum.at(combined, 0).tool == "create_shape"
      assert Enum.at(combined, 1).tool == "move_object"
      assert Enum.at(combined, 2).tool == "create_text"
      assert Enum.at(combined, 3).tool == "delete_object"
      assert Enum.at(combined, 4).tool == "create_shape"
    end
  end

  # Helper function to create a test user
  defp insert_user do
    %CollabCanvas.Accounts.User{}
    |> CollabCanvas.Accounts.User.changeset(%{
      email: "test@example.com",
      name: "Test User",
      provider: "auth0",
      provider_id: "auth0|123"
    })
    |> CollabCanvas.Repo.insert!()
  end
end
