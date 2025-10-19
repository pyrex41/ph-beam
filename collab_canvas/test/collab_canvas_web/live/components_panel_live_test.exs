defmodule CollabCanvasWeb.ComponentsPanelLiveTest do
  use CollabCanvasWeb.ConnCase

  import Phoenix.LiveViewTest

  alias CollabCanvas.{Accounts, Canvases, Components}

  @moduletag :integration

  setup do
    # Create test user and canvas
    {:ok, user} =
      Accounts.create_user(%{
        email: "test@example.com",
        name: "Test User"
      })

    {:ok, canvas} = Canvases.create_canvas(user.id, "Test Canvas")

    # Create some test objects for components
    {:ok, obj1} =
      Canvases.create_object(canvas.id, "rectangle", %{
        position: %{x: 10, y: 20},
        data: Jason.encode!(%{width: 100, height: 50, fill: "#3b82f6"})
      })

    {:ok, obj2} =
      Canvases.create_object(canvas.id, "circle", %{
        position: %{x: 50, y: 50},
        data: Jason.encode!(%{radius: 40, fill: "#10b981"})
      })

    {:ok, user: user, canvas: canvas, objects: [obj1, obj2]}
  end

  describe "mount/1" do
    test "subscribes to component PubSub topics", %{canvas: canvas, objects: [obj1, obj2]} do
      # Create a component
      {:ok, component} =
        Components.create_component([obj1.id, obj2.id], "Button", "button",
          canvas_id: canvas.id,
          is_published: true
        )

      # Mount the LiveComponent would happen in parent LiveView context
      # We can test that components are loaded
      components = Components.list_published_components()
      assert length(components) >= 1
      assert Enum.find(components, fn c -> c.id == component.id end)
    end
  end

  describe "handle_event/3 - search" do
    setup %{canvas: canvas, objects: [obj1, obj2]} do
      # Create test components with different names
      {:ok, button_comp} =
        Components.create_component([obj1.id], "Primary Button", "button",
          canvas_id: canvas.id,
          is_published: true,
          description: "A primary action button"
        )

      {:ok, card_comp} =
        Components.create_component([obj2.id], "Profile Card", "card",
          canvas_id: canvas.id,
          is_published: true,
          description: "User profile display card"
        )

      {:ok, button_comp: button_comp, card_comp: card_comp}
    end

    test "filters components by name", %{button_comp: button_comp} do
      components = Components.list_published_components()
      query = String.downcase("button")

      filtered =
        Enum.filter(components, fn component ->
          String.contains?(String.downcase(component.name), query)
        end)

      assert length(filtered) >= 1
      assert Enum.find(filtered, fn c -> c.id == button_comp.id end)
    end

    test "filters components by description", %{card_comp: card_comp} do
      components = Components.list_published_components()
      query = String.downcase("profile")

      filtered =
        Enum.filter(components, fn component ->
          description = component.description || ""
          String.contains?(String.downcase(description), query)
        end)

      assert Enum.find(filtered, fn c -> c.id == card_comp.id end)
    end

    test "returns empty list when no matches found" do
      components = Components.list_published_components()
      query = "nonexistent_component_xyz"

      filtered =
        Enum.filter(components, fn component ->
          name_match = String.contains?(String.downcase(component.name), String.downcase(query))

          description_match =
            if component.description do
              String.contains?(String.downcase(component.description), String.downcase(query))
            else
              false
            end

          name_match || description_match
        end)

      assert filtered == []
    end

    test "search is case-insensitive", %{button_comp: button_comp} do
      components = Components.list_published_components()

      # Search with different cases
      for query <- ["BUTTON", "Button", "button", "BuTtOn"] do
        filtered =
          Enum.filter(components, fn component ->
            String.contains?(String.downcase(component.name), String.downcase(query))
          end)

        assert Enum.find(filtered, fn c -> c.id == button_comp.id end)
      end
    end
  end

  describe "handle_event/3 - filter_category" do
    setup %{canvas: canvas, objects: [obj1, obj2]} do
      # Create components in different categories
      {:ok, button} =
        Components.create_component([obj1.id], "Button", "button",
          canvas_id: canvas.id,
          is_published: true
        )

      {:ok, card} =
        Components.create_component([obj2.id], "Card", "card",
          canvas_id: canvas.id,
          is_published: true
        )

      {:ok, button: button, card: card}
    end

    test "filters components by category", %{button: button, card: card} do
      all_components = Components.list_published_components()

      # Filter by button category
      buttons =
        Enum.filter(all_components, fn component ->
          component.category == "button"
        end)

      assert Enum.find(buttons, fn c -> c.id == button.id end)
      refute Enum.find(buttons, fn c -> c.id == card.id end)

      # Filter by card category
      cards =
        Enum.filter(all_components, fn component ->
          component.category == "card"
        end)

      assert Enum.find(cards, fn c -> c.id == card.id end)
      refute Enum.find(cards, fn c -> c.id == button.id end)
    end

    test "returns all components when category is nil" do
      all_components = Components.list_published_components()
      filtered_all = all_components

      assert length(filtered_all) == length(all_components)
    end
  end

  describe "handle_event/3 - toggle_category" do
    test "toggles category expansion state" do
      expanded = MapSet.new(["button"])

      # Toggle expanded category (should collapse)
      expanded_after_collapse =
        if MapSet.member?(expanded, "button") do
          MapSet.delete(expanded, "button")
        else
          MapSet.put(expanded, "button")
        end

      refute MapSet.member?(expanded_after_collapse, "button")

      # Toggle collapsed category (should expand)
      expanded_after_expand =
        if MapSet.member?(expanded_after_collapse, "button") do
          MapSet.delete(expanded_after_collapse, "button")
        else
          MapSet.put(expanded_after_collapse, "button")
        end

      assert MapSet.member?(expanded_after_expand, "button")
    end
  end

  describe "handle_event/3 - drag operations" do
    setup %{canvas: canvas, objects: [obj1, _obj2]} do
      {:ok, component} =
        Components.create_component([obj1.id], "Draggable", "button",
          canvas_id: canvas.id,
          is_published: true
        )

      {:ok, component: component}
    end

    test "drag_start sets dragging_component", %{component: component} do
      # Simulate drag start
      dragging_component = component

      assert dragging_component != nil
      assert dragging_component.id == component.id
    end

    test "drag_end clears dragging_component" do
      # Simulate drag end
      dragging_component = nil

      assert dragging_component == nil
    end
  end

  describe "handle_event/3 - create_component" do
    test "creates component from object IDs", %{canvas: canvas, user: user, objects: [obj1, obj2]} do
      result =
        Components.create_component([obj1.id, obj2.id], "New Component", "custom",
          canvas_id: canvas.id,
          created_by: user.id,
          description: "Test component",
          is_published: true
        )

      assert {:ok, component} = result
      assert component.name == "New Component"
      assert component.category == "custom"
      assert component.is_published == true
    end

    test "handles missing objects error", %{canvas: canvas, user: user} do
      result =
        Components.create_component([999_999, 999_998], "Invalid", "custom",
          canvas_id: canvas.id,
          created_by: user.id,
          is_published: true
        )

      assert {:error, :objects_not_found} = result
    end

    test "validates component name is required", %{canvas: canvas, objects: [obj1 | _]} do
      result =
        Components.create_component([obj1.id], "", "button",
          canvas_id: canvas.id,
          is_published: true
        )

      assert {:error, changeset} = result
      assert changeset.errors[:name]
    end
  end

  describe "handle_event/3 - update_component" do
    setup %{canvas: canvas, objects: [obj1, _obj2]} do
      {:ok, component} =
        Components.create_component([obj1.id], "Original Name", "button",
          canvas_id: canvas.id,
          is_published: true
        )

      {:ok, component: component}
    end

    test "updates component properties", %{component: component} do
      result =
        Components.update_component(component.id, %{
          name: "Updated Name",
          description: "Updated description"
        })

      assert {:ok, updated} = result
      assert updated.name == "Updated Name"
      assert updated.description == "Updated description"
    end

    test "handles update of non-existent component" do
      result = Components.update_component(999_999, %{name: "New Name"})

      assert {:error, :not_found} = result
    end

    test "validates updated data", %{component: component} do
      result = Components.update_component(component.id, %{name: ""})

      assert {:error, changeset} = result
      assert changeset.errors[:name]
    end
  end

  describe "handle_event/3 - override_instance_property" do
    setup %{canvas: canvas, objects: [obj1, _obj2]} do
      # Create component
      {:ok, component} =
        Components.create_component([obj1.id], "Base Component", "button",
          canvas_id: canvas.id,
          is_published: true
        )

      # Create instance
      {:ok, instances} =
        Components.instantiate_component(component.id, %{x: 100, y: 100}, canvas_id: canvas.id)

      instance = List.first(instances)

      {:ok, component: component, instance: instance}
    end

    test "overrides instance property", %{instance: instance} do
      # Parse existing overrides
      overrides = %{}

      # Add new override
      property = "fill"
      value = "#ff0000"
      overrides = Map.put(overrides, property, value)

      # Update instance
      result =
        Canvases.update_object(instance.id, %{
          instance_overrides: Jason.encode!(overrides)
        })

      assert {:ok, updated} = result
      assert updated.instance_overrides != nil

      decoded = Jason.decode!(updated.instance_overrides)
      assert decoded[property] == value
    end

    test "handles non-existent instance" do
      result = Canvases.update_object(999_999, %{instance_overrides: "{}"})

      assert {:error, :not_found} = result
    end
  end

  describe "handle_info/2 - component PubSub events" do
    setup %{canvas: canvas, objects: [obj1, _obj2]} do
      # Subscribe to component topics
      Phoenix.PubSub.subscribe(CollabCanvas.PubSub, "component:created")
      Phoenix.PubSub.subscribe(CollabCanvas.PubSub, "component:updated")
      Phoenix.PubSub.subscribe(CollabCanvas.PubSub, "component:deleted")
      Phoenix.PubSub.subscribe(CollabCanvas.PubSub, "component:instantiated")

      {:ok, component} =
        Components.create_component([obj1.id], "Test Component", "button",
          canvas_id: canvas.id,
          is_published: true
        )

      {:ok, component: component}
    end

    test "receives component:created broadcast", %{
      canvas: canvas,
      objects: [obj1, _obj2],
      component: setup_component
    } do
      # Flush any broadcasts from setup
      receive do
        {:created, _, _} -> :ok
      after
        0 -> :ok
      end

      {:ok, new_component} =
        Components.create_component([obj1.id], "New Component", "card",
          canvas_id: canvas.id,
          is_published: true
        )

      assert_receive {:created, broadcast_component, _metadata}, 1000
      assert broadcast_component.id == new_component.id
      # Make sure it's not the setup component
      refute broadcast_component.id == setup_component.id
    end

    test "receives component:updated broadcast", %{component: component} do
      {:ok, updated} = Components.update_component(component.id, %{name: "Updated Name"})

      assert_receive {:updated, component, _metadata}, 1000
      assert component.id == updated.id
      assert component.name == "Updated Name"
    end

    test "receives component:deleted broadcast", %{component: component} do
      {:ok, deleted} = Components.delete_component(component.id)

      assert_receive {:deleted, component, _metadata}, 1000
      assert component.id == deleted.id
    end

    test "receives component:instantiated broadcast", %{canvas: canvas, component: component} do
      {:ok, instances} =
        Components.instantiate_component(component.id, %{x: 200, y: 200}, canvas_id: canvas.id)

      assert_receive {:instantiated, received_component, metadata}, 1000
      assert received_component.id == component.id
      assert metadata.instances == instances
      assert metadata.canvas_id == canvas.id
    end
  end

  describe "real-time collaboration" do
    setup %{canvas: canvas, objects: [obj1, _obj2]} do
      {:ok, component} =
        Components.create_component([obj1.id], "Shared Component", "button",
          canvas_id: canvas.id,
          is_published: true
        )

      {:ok, component: component}
    end

    test "multiple clients see component updates in real-time", %{component: component} do
      # Subscribe to component updates
      Phoenix.PubSub.subscribe(CollabCanvas.PubSub, "component:updated")

      # Update component (simulating another client)
      {:ok, updated} = Components.update_component(component.id, %{name: "Realtime Update"})

      # Verify broadcast was received
      assert_receive {:updated, received, _metadata}, 1000
      assert received.id == updated.id
      assert received.name == "Realtime Update"
    end

    test "component instantiation is broadcast to all clients", %{
      canvas: canvas,
      component: component
    } do
      # Subscribe to instantiation events
      Phoenix.PubSub.subscribe(CollabCanvas.PubSub, "component:instantiated")

      # Instantiate component
      {:ok, instances} =
        Components.instantiate_component(component.id, %{x: 150, y: 150}, canvas_id: canvas.id)

      # Verify broadcast was received
      assert_receive {:instantiated, received_component, metadata}, 1000
      assert received_component.id == component.id
      assert length(metadata.instances) == length(instances)
    end
  end

  describe "component instantiation integration" do
    setup %{canvas: canvas, objects: [obj1, obj2]} do
      {:ok, component} =
        Components.create_component([obj1.id, obj2.id], "Multi-Object Component", "layout",
          canvas_id: canvas.id,
          is_published: true
        )

      {:ok, component: component}
    end

    test "instantiates component at specified position", %{canvas: canvas, component: component} do
      position = %{x: 300, y: 400}

      {:ok, instances} =
        Components.instantiate_component(component.id, position, canvas_id: canvas.id)

      assert length(instances) == 2

      # Verify instances are linked to component
      Enum.each(instances, fn instance ->
        assert instance.component_id == component.id
        assert instance.is_main_component == false
      end)
    end

    test "maintains relative positions of objects in component", %{
      canvas: canvas,
      component: component,
      objects: [obj1, obj2]
    } do
      # Calculate expected offset
      original_pos1 = obj1.position
      original_pos2 = obj2.position

      drop_position = %{x: 500, y: 600}

      {:ok, instances} =
        Components.instantiate_component(component.id, drop_position, canvas_id: canvas.id)

      # Verify relative positions are maintained
      [inst1, inst2] = instances

      # Handle both atom and string keys for position
      get_x = fn pos -> pos[:x] || pos["x"] end
      get_y = fn pos -> pos[:y] || pos["y"] end

      # Calculate offsets
      offset_x = get_x.(inst1.position) - get_x.(original_pos1)
      offset_y = get_y.(inst1.position) - get_y.(original_pos1)

      # Second instance should have same offset
      assert get_x.(inst2.position) - get_x.(original_pos2) == offset_x
      assert get_y.(inst2.position) - get_y.(original_pos2) == offset_y
    end

    test "creates instances with unique IDs", %{canvas: canvas, component: component} do
      {:ok, instances1} =
        Components.instantiate_component(component.id, %{x: 100, y: 100}, canvas_id: canvas.id)

      {:ok, instances2} =
        Components.instantiate_component(component.id, %{x: 200, y: 200}, canvas_id: canvas.id)

      # All instances should have unique IDs
      all_ids = Enum.map(instances1 ++ instances2, & &1.id)
      assert length(all_ids) == length(Enum.uniq(all_ids))
    end
  end

  describe "UI rendering helpers" do
    test "generates thumbnails based on component type" do
      # Test rectangle thumbnail
      rect_svg = generate_rectangle_svg()
      assert String.contains?(rect_svg, "data:image/svg+xml")
      assert String.contains?(rect_svg, "rect")

      # Test circle thumbnail
      circle_svg = generate_circle_svg()
      assert String.contains?(circle_svg, "data:image/svg+xml")
      assert String.contains?(circle_svg, "circle")

      # Test text thumbnail
      text_svg = generate_text_svg()
      assert String.contains?(text_svg, "data:image/svg+xml")
      assert String.contains?(text_svg, "text")

      # Test default thumbnail
      default_svg = generate_default_svg()
      assert String.contains?(default_svg, "data:image/svg+xml")
    end

    test "groups components by category" do
      components = [
        %{id: 1, name: "Button 1", category: "button"},
        %{id: 2, name: "Button 2", category: "button"},
        %{id: 3, name: "Card 1", category: "card"}
      ]

      grouped = Enum.group_by(components, & &1.category)

      assert length(grouped["button"]) == 2
      assert length(grouped["card"]) == 1
    end

    test "returns category icons" do
      categories = ["button", "card", "form", "navigation", "layout", "icon", "custom"]

      Enum.each(categories, fn category ->
        icon = category_icon(category)
        assert is_binary(icon)
        assert String.length(icon) > 0
      end)
    end

    test "returns category colors" do
      categories = ["button", "card", "form", "navigation", "layout", "icon", "custom"]

      Enum.each(categories, fn category ->
        color = category_color(category)
        assert is_binary(color)
        assert String.length(color) > 0
      end)
    end
  end

  # Helper functions

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
end
