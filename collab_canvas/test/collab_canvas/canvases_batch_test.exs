defmodule CollabCanvas.CanvasesBatchTest do
  use CollabCanvas.DataCase

  alias CollabCanvas.Canvases
  alias CollabCanvas.Accounts

  describe "create_objects_batch/2" do
    setup do
      # Create test user and canvas
      {:ok, user} = Accounts.create_user(%{email: "test@example.com", name: "Test User"})
      {:ok, canvas} = Canvases.create_canvas(user.id, "Test Canvas")

      %{canvas: canvas, user: user}
    end

    test "creates multiple objects in a single transaction", %{canvas: canvas} do
      attrs_list = [
        %{
          type: "rectangle",
          position: %{x: 10, y: 20},
          data: Jason.encode!(%{width: 100, height: 50, color: "#FF0000"})
        },
        %{
          type: "circle",
          position: %{x: 200, y: 100},
          data: Jason.encode!(%{radius: 30, color: "#00FF00"})
        },
        %{
          type: "text",
          position: %{x: 300, y: 150},
          data: Jason.encode!(%{text: "Hello", fontSize: 16, color: "#0000FF"})
        }
      ]

      assert {:ok, objects} = Canvases.create_objects_batch(canvas.id, attrs_list)
      assert length(objects) == 3

      # Verify all objects were created
      assert Enum.all?(objects, fn obj ->
               obj.canvas_id == canvas.id and
                 obj.id != nil and
                 obj.inserted_at != nil
             end)

      # Verify object types
      types = Enum.map(objects, & &1.type)
      assert "rectangle" in types
      assert "circle" in types
      assert "text" in types

      # Verify all objects exist in database
      db_objects = Canvases.list_objects(canvas.id)
      assert length(db_objects) == 3
    end

    test "handles empty list", %{canvas: canvas} do
      assert {:ok, []} = Canvases.create_objects_batch(canvas.id, [])
    end

    test "validates object attributes", %{canvas: canvas} do
      attrs_list = [
        %{
          type: "rectangle",
          position: %{x: 10, y: 20},
          data: Jason.encode!(%{width: 100, height: 50})
        },
        %{
          type: "invalid_type",
          # This should fail validation
          position: %{x: 50, y: 60}
        }
      ]

      assert {:error, {:object, 1}, changeset, _changes} =
               Canvases.create_objects_batch(canvas.id, attrs_list)

      assert "is invalid" in errors_on(changeset).type

      # Verify no objects were created (transaction rolled back)
      assert Canvases.list_objects(canvas.id) == []
    end

    test "handles position validation errors", %{canvas: canvas} do
      attrs_list = [
        %{
          type: "rectangle",
          position: %{x: "invalid", y: 20}
          # Invalid x coordinate
        }
      ]

      assert {:error, {:object, 0}, changeset, _changes} =
               Canvases.create_objects_batch(canvas.id, attrs_list)

      assert "must contain numeric x coordinate" in errors_on(changeset).position
    end

    test "creates objects with z_index", %{canvas: canvas} do
      attrs_list = [
        %{type: "rectangle", position: %{x: 10, y: 20}, z_index: 1.0},
        %{type: "circle", position: %{x: 50, y: 60}, z_index: 2.0},
        %{type: "text", position: %{x: 100, y: 120}, z_index: 3.0}
      ]

      assert {:ok, objects} = Canvases.create_objects_batch(canvas.id, attrs_list)

      # Verify z_index values
      z_indexes = Enum.map(objects, & &1.z_index)
      assert 1.0 in z_indexes
      assert 2.0 in z_indexes
      assert 3.0 in z_indexes
    end

    test "creates objects with group_id", %{canvas: canvas} do
      group_id = Ecto.UUID.generate()

      attrs_list = [
        %{type: "rectangle", position: %{x: 10, y: 20}, group_id: group_id},
        %{type: "circle", position: %{x: 50, y: 60}, group_id: group_id}
      ]

      assert {:ok, objects} = Canvases.create_objects_batch(canvas.id, attrs_list)

      # Verify all objects have same group_id
      assert Enum.all?(objects, fn obj -> obj.group_id == group_id end)

      # Verify we can retrieve them by group
      group_objects = Canvases.get_group_objects(group_id)
      assert length(group_objects) == 2
    end

    test "handles string keys in attributes", %{canvas: canvas} do
      # Test with string keys (common from JSON parsing)
      attrs_list = [
        %{
          "type" => "rectangle",
          "position" => %{"x" => 10, "y" => 20},
          "data" => Jason.encode!(%{width: 100, height: 50})
        }
      ]

      assert {:ok, objects} = Canvases.create_objects_batch(canvas.id, attrs_list)
      assert length(objects) == 1
      assert hd(objects).type == "rectangle"
    end

    test "performance: creates 100 objects in <1 second", %{canvas: canvas} do
      attrs_list =
        Enum.map(1..100, fn i ->
          %{
            type: "rectangle",
            position: %{x: rem(i, 10) * 100, y: div(i, 10) * 100},
            data: Jason.encode!(%{width: 50, height: 50, color: "#FF0000"}),
            z_index: i * 1.0
          }
        end)

      {time_microseconds, {:ok, objects}} =
        :timer.tc(fn -> Canvases.create_objects_batch(canvas.id, attrs_list) end)

      time_seconds = time_microseconds / 1_000_000

      assert length(objects) == 100

      assert time_seconds < 1.0,
             "Expected <1s, got #{Float.round(time_seconds, 3)}s for 100 objects"

      # Verify all objects exist
      assert length(Canvases.list_objects(canvas.id)) == 100
    end

    test "performance: creates 500 objects in <2 seconds", %{canvas: canvas} do
      attrs_list =
        Enum.map(1..500, fn i ->
          %{
            type: Enum.random(["rectangle", "circle", "ellipse", "text"]),
            position: %{x: rem(i, 20) * 50, y: div(i, 20) * 50},
            data: Jason.encode!(%{width: 40, height: 40}),
            z_index: i * 1.0
          }
        end)

      {time_microseconds, {:ok, objects}} =
        :timer.tc(fn -> Canvases.create_objects_batch(canvas.id, attrs_list) end)

      time_seconds = time_microseconds / 1_000_000

      assert length(objects) == 500

      assert time_seconds < 2.0,
             "Expected <2s, got #{Float.round(time_seconds, 3)}s for 500 objects"

      # Verify all objects exist
      assert length(Canvases.list_objects(canvas.id)) == 500
    end

    test "performance: creates 600 objects for demo (target: instantaneous feel)", %{
      canvas: canvas
    } do
      attrs_list =
        Enum.map(1..600, fn i ->
          %{
            type: Enum.random(["rectangle", "circle", "star", "triangle"]),
            position: %{x: rem(i, 30) * 50, y: div(i, 30) * 50},
            data:
              Jason.encode!(%{
                width: 30 + :rand.uniform(20),
                height: 30 + :rand.uniform(20),
                color: Enum.random(["#FF0000", "#00FF00", "#0000FF", "#FFFF00"])
              }),
            z_index: i * 1.0
          }
        end)

      {time_microseconds, {:ok, objects}} =
        :timer.tc(fn -> Canvases.create_objects_batch(canvas.id, attrs_list) end)

      time_seconds = time_microseconds / 1_000_000

      assert length(objects) == 600

      # Log performance for demo purposes
      IO.puts("\n=== DEMO PERFORMANCE ===")
      IO.puts("Created 600 objects in #{Float.round(time_seconds, 3)} seconds")
      IO.puts("Average: #{Float.round(time_microseconds / 600, 2)} microseconds per object")
      IO.puts("========================\n")

      # Should feel instantaneous (< 3 seconds for demo purposes)
      assert time_seconds < 3.0,
             "Expected <3s for demo, got #{Float.round(time_seconds, 3)}s for 600 objects"

      # Verify all objects exist
      assert length(Canvases.list_objects(canvas.id)) == 600
    end

    test "atomicity: all objects created or none on validation failure", %{canvas: canvas} do
      attrs_list = [
        %{type: "rectangle", position: %{x: 10, y: 20}},
        %{type: "circle", position: %{x: 50, y: 60}},
        # This one will fail
        %{type: "invalid_type", position: %{x: 100, y: 120}},
        %{type: "text", position: %{x: 150, y: 180}}
      ]

      # Should fail on invalid object
      assert {:error, {:object, 2}, _changeset, _changes} =
               Canvases.create_objects_batch(canvas.id, attrs_list)

      # Verify NO objects were created (transaction rolled back)
      assert Canvases.list_objects(canvas.id) == []
    end

    test "creates objects with all optional fields", %{canvas: canvas} do
      group_id = Ecto.UUID.generate()

      attrs_list = [
        %{
          type: "rectangle",
          position: %{x: 10, y: 20},
          data: Jason.encode!(%{width: 100, height: 50, color: "#FF0000"}),
          z_index: 5.0,
          group_id: group_id,
          locked_by: "user_123"
        }
      ]

      assert {:ok, objects} = Canvases.create_objects_batch(canvas.id, attrs_list)
      object = hd(objects)

      assert object.type == "rectangle"
      assert object.position == %{x: 10, y: 20}
      assert object.z_index == 5.0
      assert object.group_id == group_id
      assert object.locked_by == "user_123"

      # Verify data was stored correctly
      data = Jason.decode!(object.data)
      assert data["width"] == 100
      assert data["height"] == 50
      assert data["color"] == "#FF0000"
    end
  end
end
