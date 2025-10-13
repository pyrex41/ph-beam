defmodule CollabCanvas.CanvasesTest do
  use CollabCanvas.DataCase

  alias CollabCanvas.Canvases
  alias CollabCanvas.Canvases.{Canvas, Object}
  alias CollabCanvas.Accounts

  describe "canvases" do
    setup do
      # Create a test user
      {:ok, user} =
        Accounts.create_user(%{
          email: "test@example.com",
          name: "Test User"
        })

      {:ok, user: user}
    end

    test "create_canvas/2 creates a canvas with valid attributes", %{user: user} do
      assert {:ok, %Canvas{} = canvas} = Canvases.create_canvas(user.id, "My Canvas")
      assert canvas.name == "My Canvas"
      assert canvas.user_id == user.id
      assert canvas.inserted_at
      assert canvas.updated_at
    end

    test "create_canvas/2 returns error with invalid attributes", %{user: user} do
      # Empty name
      assert {:error, changeset} = Canvases.create_canvas(user.id, "")
      assert %{name: ["can't be blank"]} = errors_on(changeset)

      # Name too long (> 255 chars)
      long_name = String.duplicate("a", 256)
      assert {:error, changeset} = Canvases.create_canvas(user.id, long_name)
      assert %{name: ["should be at most 255 character(s)"]} = errors_on(changeset)
    end

    test "create_canvas/2 raises with invalid user_id" do
      # SQLite will raise a foreign key constraint error
      assert_raise Ecto.ConstraintError, fn ->
        Canvases.create_canvas(999_999, "Canvas")
      end
    end

    test "get_canvas/1 returns the canvas with given id", %{user: user} do
      {:ok, canvas} = Canvases.create_canvas(user.id, "Test Canvas")
      fetched_canvas = Canvases.get_canvas(canvas.id)
      assert fetched_canvas.id == canvas.id
      assert fetched_canvas.name == "Test Canvas"
    end

    test "get_canvas/1 returns nil for non-existent id" do
      assert Canvases.get_canvas(999_999) == nil
    end

    test "get_canvas_with_preloads/1 returns canvas with preloaded associations", %{user: user} do
      {:ok, canvas} = Canvases.create_canvas(user.id, "Test Canvas")
      {:ok, _obj1} = Canvases.create_object(canvas.id, "rectangle", %{position: %{x: 0, y: 0}})
      {:ok, _obj2} = Canvases.create_object(canvas.id, "circle", %{position: %{x: 10, y: 10}})

      fetched_canvas = Canvases.get_canvas_with_preloads(canvas.id)
      assert fetched_canvas.id == canvas.id
      assert Ecto.assoc_loaded?(fetched_canvas.user)
      assert Ecto.assoc_loaded?(fetched_canvas.objects)
      assert fetched_canvas.user.id == user.id
      assert length(fetched_canvas.objects) == 2
    end

    test "get_canvas_with_preloads/2 returns canvas with specific preloads", %{user: user} do
      {:ok, canvas} = Canvases.create_canvas(user.id, "Test Canvas")

      fetched_canvas = Canvases.get_canvas_with_preloads(canvas.id, [:user])
      assert Ecto.assoc_loaded?(fetched_canvas.user)
      refute Ecto.assoc_loaded?(fetched_canvas.objects)
    end

    test "list_user_canvases/1 returns all canvases for a user", %{user: user} do
      {:ok, canvas1} = Canvases.create_canvas(user.id, "Canvas 1")
      {:ok, canvas2} = Canvases.create_canvas(user.id, "Canvas 2")
      {:ok, canvas3} = Canvases.create_canvas(user.id, "Canvas 3")

      canvases = Canvases.list_user_canvases(user.id)
      assert length(canvases) == 3

      canvas_ids = Enum.map(canvases, & &1.id)
      assert canvas1.id in canvas_ids
      assert canvas2.id in canvas_ids
      assert canvas3.id in canvas_ids
    end

    test "list_user_canvases/1 returns canvases ordered by updated_at desc", %{user: user} do
      {:ok, canvas1} = Canvases.create_canvas(user.id, "Canvas 1")
      # Sleep to ensure different timestamps
      :timer.sleep(1000)
      {:ok, canvas2} = Canvases.create_canvas(user.id, "Canvas 2")
      :timer.sleep(1000)
      {:ok, canvas3} = Canvases.create_canvas(user.id, "Canvas 3")

      canvases = Canvases.list_user_canvases(user.id)
      assert length(canvases) == 3
      # Most recently updated should be first
      canvas_ids = Enum.map(canvases, & &1.id)
      assert canvas_ids == [canvas3.id, canvas2.id, canvas1.id]
    end

    test "list_user_canvases/1 returns empty list for user with no canvases", %{user: user} do
      assert Canvases.list_user_canvases(user.id) == []
    end

    test "list_user_canvases/1 only returns canvases for specified user", %{user: user} do
      {:ok, other_user} =
        Accounts.create_user(%{
          email: "other@example.com",
          name: "Other User"
        })

      {:ok, _canvas1} = Canvases.create_canvas(user.id, "User Canvas")
      {:ok, _canvas2} = Canvases.create_canvas(other_user.id, "Other Canvas")

      user_canvases = Canvases.list_user_canvases(user.id)
      assert length(user_canvases) == 1
      assert hd(user_canvases).name == "User Canvas"
    end

    test "delete_canvas/1 deletes the canvas", %{user: user} do
      {:ok, canvas} = Canvases.create_canvas(user.id, "Test Canvas")
      assert {:ok, %Canvas{}} = Canvases.delete_canvas(canvas.id)
      assert Canvases.get_canvas(canvas.id) == nil
    end

    test "delete_canvas/1 returns error for non-existent canvas" do
      assert {:error, :not_found} = Canvases.delete_canvas(999_999)
    end

    test "delete_canvas/1 cascades to delete all objects", %{user: user} do
      {:ok, canvas} = Canvases.create_canvas(user.id, "Test Canvas")
      {:ok, obj1} = Canvases.create_object(canvas.id, "rectangle", %{position: %{x: 0, y: 0}})
      {:ok, obj2} = Canvases.create_object(canvas.id, "circle", %{position: %{x: 10, y: 10}})

      assert {:ok, %Canvas{}} = Canvases.delete_canvas(canvas.id)
      assert Canvases.get_object(obj1.id) == nil
      assert Canvases.get_object(obj2.id) == nil
    end
  end

  describe "objects" do
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

    test "create_object/3 creates an object with valid attributes", %{canvas: canvas} do
      assert {:ok, %Object{} = object} =
               Canvases.create_object(canvas.id, "rectangle", %{
                 position: %{x: 10, y: 20},
                 data: "{\"color\": \"red\"}"
               })

      assert object.type == "rectangle"
      assert object.canvas_id == canvas.id
      # SQLite/Ecto stores map keys as atoms
      assert object.position == %{x: 10, y: 20}
      assert object.data == "{\"color\": \"red\"}"
    end

    test "create_object/3 creates object without optional fields", %{canvas: canvas} do
      assert {:ok, %Object{} = object} = Canvases.create_object(canvas.id, "circle")
      assert object.type == "circle"
      assert object.canvas_id == canvas.id
      assert object.position == nil
      assert object.data == nil
    end

    test "create_object/3 validates object type", %{canvas: canvas} do
      assert {:error, changeset} = Canvases.create_object(canvas.id, "invalid_type")
      assert %{type: ["is invalid"]} = errors_on(changeset)
    end

    test "create_object/3 validates position structure", %{canvas: canvas} do
      # Missing y coordinate
      assert {:error, changeset} =
               Canvases.create_object(canvas.id, "rectangle", %{position: %{x: 10}})

      assert %{position: ["must contain numeric y coordinate"]} = errors_on(changeset)

      # Missing x coordinate
      assert {:error, changeset} =
               Canvases.create_object(canvas.id, "rectangle", %{position: %{y: 10}})

      assert %{position: ["must contain numeric x coordinate"]} = errors_on(changeset)

      # Non-numeric coordinates
      assert {:error, changeset} =
               Canvases.create_object(canvas.id, "rectangle", %{position: %{x: "ten", y: 10}})

      assert %{position: ["must contain numeric x coordinate"]} = errors_on(changeset)
    end

    test "create_object/3 accepts atom keys in position", %{canvas: canvas} do
      assert {:ok, %Object{} = object} =
               Canvases.create_object(canvas.id, "rectangle", %{position: %{x: 10, y: 20}})

      # SQLite stores as atom keys
      assert object.position == %{x: 10, y: 20}
    end

    test "create_object/3 accepts string keys in position", %{canvas: canvas} do
      assert {:ok, %Object{} = object} =
               Canvases.create_object(canvas.id, "rectangle", %{position: %{"x" => 10, "y" => 20}})

      # SQLite preserves string keys when provided as strings
      assert object.position == %{"x" => 10, "y" => 20}
    end

    test "create_object/3 raises with invalid canvas_id" do
      # SQLite will raise a foreign key constraint error
      assert_raise Ecto.ConstraintError, fn ->
        Canvases.create_object(999_999, "rectangle")
      end
    end

    test "get_object/1 returns the object with given id", %{canvas: canvas} do
      {:ok, object} = Canvases.create_object(canvas.id, "rectangle", %{position: %{x: 0, y: 0}})
      fetched_object = Canvases.get_object(object.id)
      assert fetched_object.id == object.id
      assert fetched_object.type == "rectangle"
    end

    test "get_object/1 returns nil for non-existent id" do
      assert Canvases.get_object(999_999) == nil
    end

    test "update_object/2 updates the object with valid attributes", %{canvas: canvas} do
      {:ok, object} = Canvases.create_object(canvas.id, "rectangle", %{position: %{x: 0, y: 0}})

      assert {:ok, %Object{} = updated_object} =
               Canvases.update_object(object.id, %{
                 position: %{x: 100, y: 200},
                 data: "{\"color\": \"blue\"}"
               })

      assert updated_object.id == object.id
      # SQLite stores as atom keys
      assert updated_object.position == %{x: 100, y: 200}
      assert updated_object.data == "{\"color\": \"blue\"}"
    end

    test "update_object/2 validates updated position", %{canvas: canvas} do
      {:ok, object} = Canvases.create_object(canvas.id, "rectangle", %{position: %{x: 0, y: 0}})

      assert {:error, changeset} =
               Canvases.update_object(object.id, %{position: %{x: 100}})

      assert %{position: ["must contain numeric y coordinate"]} = errors_on(changeset)
    end

    test "update_object/2 returns error for non-existent object" do
      assert {:error, :not_found} =
               Canvases.update_object(999_999, %{position: %{x: 100, y: 200}})
    end

    test "delete_object/1 deletes the object", %{canvas: canvas} do
      {:ok, object} = Canvases.create_object(canvas.id, "rectangle")
      assert {:ok, %Object{}} = Canvases.delete_object(object.id)
      assert Canvases.get_object(object.id) == nil
    end

    test "delete_object/1 returns error for non-existent object" do
      assert {:error, :not_found} = Canvases.delete_object(999_999)
    end

    test "list_objects/1 returns all objects for a canvas", %{canvas: canvas} do
      {:ok, obj1} = Canvases.create_object(canvas.id, "rectangle", %{position: %{x: 0, y: 0}})
      {:ok, obj2} = Canvases.create_object(canvas.id, "circle", %{position: %{x: 10, y: 10}})
      {:ok, obj3} = Canvases.create_object(canvas.id, "text", %{position: %{x: 20, y: 20}})

      objects = Canvases.list_objects(canvas.id)
      assert length(objects) == 3

      object_ids = Enum.map(objects, & &1.id)
      assert obj1.id in object_ids
      assert obj2.id in object_ids
      assert obj3.id in object_ids
    end

    test "list_objects/1 returns objects ordered by inserted_at asc", %{canvas: canvas} do
      {:ok, obj1} = Canvases.create_object(canvas.id, "rectangle")
      :timer.sleep(100)
      {:ok, _obj2} = Canvases.create_object(canvas.id, "circle")
      :timer.sleep(100)
      {:ok, obj3} = Canvases.create_object(canvas.id, "text")

      objects = Canvases.list_objects(canvas.id)
      assert length(objects) == 3
      # Oldest should be first
      assert hd(objects).id == obj1.id
      assert List.last(objects).id == obj3.id
    end

    test "list_objects/1 returns empty list for canvas with no objects", %{canvas: canvas} do
      assert Canvases.list_objects(canvas.id) == []
    end

    test "list_objects/1 only returns objects for specified canvas", %{user: user, canvas: canvas} do
      {:ok, other_canvas} = Canvases.create_canvas(user.id, "Other Canvas")

      {:ok, _obj1} = Canvases.create_object(canvas.id, "rectangle")
      {:ok, _obj2} = Canvases.create_object(other_canvas.id, "circle")

      canvas_objects = Canvases.list_objects(canvas.id)
      assert length(canvas_objects) == 1
      assert hd(canvas_objects).type == "rectangle"
    end

    test "delete_canvas_objects/1 deletes all objects from canvas", %{canvas: canvas} do
      {:ok, _obj1} = Canvases.create_object(canvas.id, "rectangle")
      {:ok, _obj2} = Canvases.create_object(canvas.id, "circle")
      {:ok, _obj3} = Canvases.create_object(canvas.id, "text")

      assert {3, nil} = Canvases.delete_canvas_objects(canvas.id)
      assert Canvases.list_objects(canvas.id) == []
    end

    test "delete_canvas_objects/1 returns 0 for canvas with no objects", %{canvas: canvas} do
      assert {0, nil} = Canvases.delete_canvas_objects(canvas.id)
    end
  end

  describe "object types" do
    setup do
      {:ok, user} =
        Accounts.create_user(%{
          email: "test@example.com",
          name: "Test User"
        })

      {:ok, canvas} = Canvases.create_canvas(user.id, "Test Canvas")

      {:ok, canvas: canvas}
    end

    test "allows creating rectangle objects", %{canvas: canvas} do
      assert {:ok, %Object{type: "rectangle"}} = Canvases.create_object(canvas.id, "rectangle")
    end

    test "allows creating circle objects", %{canvas: canvas} do
      assert {:ok, %Object{type: "circle"}} = Canvases.create_object(canvas.id, "circle")
    end

    test "allows creating ellipse objects", %{canvas: canvas} do
      assert {:ok, %Object{type: "ellipse"}} = Canvases.create_object(canvas.id, "ellipse")
    end

    test "allows creating text objects", %{canvas: canvas} do
      assert {:ok, %Object{type: "text"}} = Canvases.create_object(canvas.id, "text")
    end

    test "allows creating line objects", %{canvas: canvas} do
      assert {:ok, %Object{type: "line"}} = Canvases.create_object(canvas.id, "line")
    end

    test "allows creating path objects", %{canvas: canvas} do
      assert {:ok, %Object{type: "path"}} = Canvases.create_object(canvas.id, "path")
    end
  end
end
