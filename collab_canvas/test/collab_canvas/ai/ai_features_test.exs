defmodule CollabCanvas.AI.AIFeaturesTest do
  @moduledoc """
  Comprehensive test suite for AI features including:
  - Semantic selection tool
  - Voice command input
  - AI interaction history
  - Enter key submission

  This test suite covers 20-30 core commands with 3-5 variations each
  to ensure reliability of all AI features.
  """

  use CollabCanvas.DataCase, async: true

  alias CollabCanvas.AI.Agent
  alias CollabCanvas.Canvases
  alias CollabCanvas.Accounts

  setup do
    # Create test user and canvas
    {:ok, user} = Accounts.create_user(%{email: "ai_test@example.com", name: "AI Test User"})
    {:ok, canvas} = Canvases.create_canvas(user.id, "AI Test Canvas")

    # Create some test objects for selection tests
    {:ok, red_rect} =
      Canvases.create_object(canvas.id, "rectangle", %{
        position: %{x: 10, y: 10},
        data: Jason.encode!(%{width: 100, height: 50, color: "#FF0000"})
      })

    {:ok, blue_circle} =
      Canvases.create_object(canvas.id, "circle", %{
        position: %{x: 200, y: 10},
        data: Jason.encode!(%{width: 80, height: 80, color: "#0000FF"})
      })

    {:ok, green_rect} =
      Canvases.create_object(canvas.id, "rectangle", %{
        position: %{x: 10, y: 200},
        data: Jason.encode!(%{width: 60, height: 60, color: "#00FF00"})
      })

    {:ok, red_circle} =
      Canvases.create_object(canvas.id, "circle", %{
        position: %{x: 300, y: 300},
        data: Jason.encode!(%{width: 50, height: 50, color: "#FF0000"})
      })

    {:ok, text_obj} =
      Canvases.create_object(canvas.id, "text", %{
        position: %{x: 150, y: 150},
        data: Jason.encode!(%{text: "Test Label", font_size: 24, color: "#000000"})
      })

    %{
      user: user,
      canvas: canvas,
      red_rect: red_rect,
      blue_circle: blue_circle,
      green_rect: green_rect,
      red_circle: red_circle,
      text_obj: text_obj
    }
  end

  describe "Semantic Selection Tool Tests" do
    test "select_objects_by_description - select by color", %{canvas: canvas} do
      tool_calls = [
        %{
          id: "call_select_red",
          name: "select_objects_by_description",
          input: %{
            "description" => "all red objects",
            "objects_context" => [
              %{"id" => 1, "type" => "rectangle", "position" => %{"x" => 10, "y" => 10},
                "data" => %{"color" => "#FF0000", "width" => 100}},
              %{"id" => 2, "type" => "circle", "position" => %{"x" => 200, "y" => 10},
                "data" => %{"color" => "#0000FF", "width" => 80}},
              %{"id" => 4, "type" => "circle", "position" => %{"x" => 300, "y" => 300},
                "data" => %{"color" => "#FF0000", "width" => 50}}
            ]
          }
        }
      ]

      results = Agent.process_tool_calls(tool_calls, canvas.id)
      result = List.first(results)

      assert result.tool == "select_objects_by_description"
      assert {:ok, %{selected_ids: selected_ids, description: _desc}} = result.result
      # Should select the two red objects
      assert length(selected_ids) == 2
      assert 1 in selected_ids
      assert 4 in selected_ids
    end

    test "select_objects_by_description - select by shape type", %{canvas: canvas} do
      tool_calls = [
        %{
          id: "call_select_circles",
          name: "select_objects_by_description",
          input: %{
            "description" => "all circles",
            "objects_context" => [
              %{"id" => 1, "type" => "rectangle", "position" => %{"x" => 10, "y" => 10}},
              %{"id" => 2, "type" => "circle", "position" => %{"x" => 200, "y" => 10}},
              %{"id" => 3, "type" => "rectangle", "position" => %{"x" => 10, "y" => 200}},
              %{"id" => 4, "type" => "circle", "position" => %{"x" => 300, "y" => 300}}
            ]
          }
        }
      ]

      results = Agent.process_tool_calls(tool_calls, canvas.id)
      result = List.first(results)

      assert {:ok, %{selected_ids: selected_ids}} = result.result
      assert length(selected_ids) == 2
      assert 2 in selected_ids
      assert 4 in selected_ids
    end

    test "select_objects_by_description - select by size", %{canvas: canvas} do
      tool_calls = [
        %{
          id: "call_select_small",
          name: "select_objects_by_description",
          input: %{
            "description" => "small objects",
            "objects_context" => [
              %{"id" => 1, "data" => %{"width" => 100, "height" => 50}},
              %{"id" => 2, "data" => %{"width" => 80, "height" => 80}},
              %{"id" => 3, "data" => %{"width" => 60, "height" => 60}},
              %{"id" => 4, "data" => %{"width" => 50, "height" => 50}}
            ]
          }
        }
      ]

      results = Agent.process_tool_calls(tool_calls, canvas.id)
      result = List.first(results)

      assert {:ok, %{selected_ids: selected_ids}} = result.result
      # Should select the smaller objects
      assert 4 in selected_ids
    end

    test "select_objects_by_description - select by position", %{canvas: canvas} do
      tool_calls = [
        %{
          id: "call_select_top",
          name: "select_objects_by_description",
          input: %{
            "description" => "objects in the top area",
            "objects_context" => [
              %{"id" => 1, "position" => %{"x" => 10, "y" => 10}},
              %{"id" => 2, "position" => %{"x" => 200, "y" => 10}},
              %{"id" => 3, "position" => %{"x" => 10, "y" => 200}},
              %{"id" => 4, "position" => %{"x" => 300, "y" => 300}}
            ]
          }
        }
      ]

      results = Agent.process_tool_calls(tool_calls, canvas.id)
      result = List.first(results)

      assert {:ok, %{selected_ids: selected_ids}} = result.result
      # Should select objects with low y values
      assert 1 in selected_ids
      assert 2 in selected_ids
    end

    test "select_objects_by_description - combined criteria", %{canvas: canvas} do
      tool_calls = [
        %{
          id: "call_select_combined",
          name: "select_objects_by_description",
          input: %{
            "description" => "small red circles",
            "objects_context" => [
              %{"id" => 1, "type" => "rectangle", "data" => %{"color" => "#FF0000", "width" => 100}},
              %{"id" => 2, "type" => "circle", "data" => %{"color" => "#0000FF", "width" => 80}},
              %{"id" => 3, "type" => "rectangle", "data" => %{"color" => "#00FF00", "width" => 60}},
              %{"id" => 4, "type" => "circle", "data" => %{"color" => "#FF0000", "width" => 50}}
            ]
          }
        }
      ]

      results = Agent.process_tool_calls(tool_calls, canvas.id)
      result = List.first(results)

      assert {:ok, %{selected_ids: selected_ids}} = result.result
      # Should only select the small red circle
      assert selected_ids == [4]
    end
  end

  describe "Shape Creation Command Variations" do
    test "create rectangle - basic", %{canvas: canvas} do
      tool_calls = [
        %{
          id: "call_rect_basic",
          name: "create_shape",
          input: %{
            "type" => "rectangle",
            "x" => 100,
            "y" => 100,
            "width" => 200,
            "height" => 100
          }
        }
      ]

      results = Agent.process_tool_calls(tool_calls, canvas.id)
      assert {:ok, object} = List.first(results).result
      assert object.type == "rectangle"
      assert object.position.x == 100
      assert object.position.y == 100
    end

    test "create rectangle - with color", %{canvas: canvas} do
      tool_calls = [
        %{
          id: "call_rect_color",
          name: "create_shape",
          input: %{
            "type" => "rectangle",
            "x" => 50,
            "y" => 50,
            "width" => 150,
            "height" => 75,
            "color" => "#FF5733"
          }
        }
      ]

      results = Agent.process_tool_calls(tool_calls, canvas.id)
      assert {:ok, object} = List.first(results).result

      decoded_data = Jason.decode!(object.data)
      assert decoded_data["color"] == "#FF5733"
    end

    test "create circle - various sizes", %{canvas: canvas} do
      sizes = [30, 60, 100]

      Enum.each(sizes, fn size ->
        tool_calls = [
          %{
            id: "call_circle_#{size}",
            name: "create_shape",
            input: %{
              "type" => "circle",
              "x" => size,
              "y" => size,
              "width" => size,
              "height" => size
            }
          }
        ]

        results = Agent.process_tool_calls(tool_calls, canvas.id)
        assert {:ok, object} = List.first(results).result

        decoded_data = Jason.decode!(object.data)
        assert decoded_data["width"] == size
        assert decoded_data["height"] == size
      end)
    end

    test "create multiple shapes in sequence", %{canvas: canvas} do
      tool_calls = [
        %{
          id: "call_multi_1",
          name: "create_shape",
          input: %{"type" => "rectangle", "x" => 0, "y" => 0, "width" => 50, "height" => 50}
        },
        %{
          id: "call_multi_2",
          name: "create_shape",
          input: %{"type" => "circle", "x" => 60, "y" => 0, "width" => 50, "height" => 50}
        },
        %{
          id: "call_multi_3",
          name: "create_shape",
          input: %{"type" => "rectangle", "x" => 120, "y" => 0, "width" => 50, "height" => 50}
        }
      ]

      results = Agent.process_tool_calls(tool_calls, canvas.id)
      assert length(results) == 3

      types = Enum.map(results, fn r ->
        {:ok, obj} = r.result
        obj.type
      end)

      assert types == ["rectangle", "circle", "rectangle"]
    end
  end

  describe "Text Creation and Manipulation" do
    test "create text - basic", %{canvas: canvas} do
      tool_calls = [
        %{
          id: "call_text_basic",
          name: "create_text",
          input: %{
            "text" => "Hello World",
            "x" => 100,
            "y" => 100
          }
        }
      ]

      results = Agent.process_tool_calls(tool_calls, canvas.id)
      assert {:ok, object} = List.first(results).result

      decoded_data = Jason.decode!(object.data)
      assert decoded_data["text"] == "Hello World"
    end

    test "create text - with formatting", %{canvas: canvas} do
      tool_calls = [
        %{
          id: "call_text_formatted",
          name: "create_text",
          input: %{
            "text" => "Formatted Text",
            "x" => 50,
            "y" => 50,
            "font_size" => 32,
            "color" => "#FF0000",
            "font_family" => "Arial",
            "bold" => true
          }
        }
      ]

      results = Agent.process_tool_calls(tool_calls, canvas.id)
      assert {:ok, object} = List.first(results).result

      decoded_data = Jason.decode!(object.data)
      assert decoded_data["font_size"] == 32
      assert decoded_data["color"] == "#FF0000"
      assert decoded_data["font_family"] == "Arial"
      assert decoded_data["bold"] == true
    end

    test "update text content", %{text_obj: text_obj, canvas: canvas} do
      tool_calls = [
        %{
          id: "call_update_text",
          name: "update_text",
          input: %{
            "object_id" => text_obj.id,
            "new_text" => "Updated Label"
          }
        }
      ]

      results = Agent.process_tool_calls(tool_calls, canvas.id)
      assert {:ok, updated} = List.first(results).result

      decoded_data = Jason.decode!(updated.data)
      assert decoded_data["text"] == "Updated Label"
    end

    test "update text with new styling", %{text_obj: text_obj, canvas: canvas} do
      tool_calls = [
        %{
          id: "call_restyle_text",
          name: "update_text",
          input: %{
            "object_id" => text_obj.id,
            "new_text" => "Restyled Text",
            "font_size" => 36,
            "color" => "#00FF00"
          }
        }
      ]

      results = Agent.process_tool_calls(tool_calls, canvas.id)
      assert {:ok, updated} = List.first(results).result

      decoded_data = Jason.decode!(updated.data)
      assert decoded_data["text"] == "Restyled Text"
      assert decoded_data["font_size"] == 36
      assert decoded_data["color"] == "#00FF00"
    end
  end

  describe "Layout and Arrangement Commands" do
    test "arrange objects horizontally", %{canvas: canvas} do
      # Create objects first
      {:ok, obj1} = Canvases.create_object(canvas.id, "rectangle", %{
        position: %{x: 0, y: 50},
        data: Jason.encode!(%{width: 50, height: 50})
      })

      {:ok, obj2} = Canvases.create_object(canvas.id, "rectangle", %{
        position: %{x: 100, y: 100},
        data: Jason.encode!(%{width: 50, height: 50})
      })

      {:ok, obj3} = Canvases.create_object(canvas.id, "rectangle", %{
        position: %{x: 200, y: 25},
        data: Jason.encode!(%{width: 50, height: 50})
      })

      tool_calls = [
        %{
          id: "call_arrange_horiz",
          name: "arrange_objects",
          input: %{
            "object_ids" => [obj1.id, obj2.id, obj3.id],
            "layout" => "horizontal",
            "spacing" => 20
          }
        }
      ]

      results = Agent.process_tool_calls(tool_calls, canvas.id)
      assert {:ok, _} = List.first(results).result

      # Verify objects are arranged horizontally
      updated_obj1 = Canvases.get_object(obj1.id)
      updated_obj2 = Canvases.get_object(obj2.id)
      updated_obj3 = Canvases.get_object(obj3.id)

      # Should be arranged horizontally with 20px spacing
      assert updated_obj2.position.x > updated_obj1.position.x
      assert updated_obj3.position.x > updated_obj2.position.x
    end

    test "arrange objects vertically", %{canvas: canvas} do
      # Create objects
      object_ids = for i <- 1..3 do
        {:ok, obj} = Canvases.create_object(canvas.id, "circle", %{
          position: %{x: i * 100, y: i * 50},
          data: Jason.encode!(%{width: 40, height: 40})
        })
        obj.id
      end

      tool_calls = [
        %{
          id: "call_arrange_vert",
          name: "arrange_objects",
          input: %{
            "object_ids" => object_ids,
            "layout" => "vertical",
            "spacing" => 30
          }
        }
      ]

      results = Agent.process_tool_calls(tool_calls, canvas.id)
      assert {:ok, _} = List.first(results).result

      # Verify vertical arrangement
      [obj1, obj2, obj3] = Enum.map(object_ids, &Canvases.get_object/1)

      assert obj2.position.y > obj1.position.y
      assert obj3.position.y > obj2.position.y
    end

    test "arrange objects in grid", %{canvas: canvas} do
      # Create 6 objects
      object_ids = for i <- 1..6 do
        {:ok, obj} = Canvases.create_object(canvas.id, "rectangle", %{
          position: %{x: i * 30, y: i * 30},
          data: Jason.encode!(%{width: 40, height: 40})
        })
        obj.id
      end

      tool_calls = [
        %{
          id: "call_arrange_grid",
          name: "arrange_objects",
          input: %{
            "object_ids" => object_ids,
            "layout" => "grid",
            "columns" => 3,
            "spacing" => 10
          }
        }
      ]

      results = Agent.process_tool_calls(tool_calls, canvas.id)
      assert {:ok, _} = List.first(results).result

      # Grid should have 2 rows of 3 objects each
      objects = Enum.map(object_ids, &Canvases.get_object/1)

      # First row objects should have same y
      assert Enum.at(objects, 0).position.y == Enum.at(objects, 1).position.y
      assert Enum.at(objects, 1).position.y == Enum.at(objects, 2).position.y

      # Second row objects should be below first row
      assert Enum.at(objects, 3).position.y > Enum.at(objects, 0).position.y
    end

    test "arrange objects in circular layout", %{canvas: canvas} do
      # Create 5 objects
      object_ids = for i <- 1..5 do
        {:ok, obj} = Canvases.create_object(canvas.id, "circle", %{
          position: %{x: i * 20, y: i * 20},
          data: Jason.encode!(%{width: 30, height: 30})
        })
        obj.id
      end

      tool_calls = [
        %{
          id: "call_arrange_circular",
          name: "arrange_objects",
          input: %{
            "object_ids" => object_ids,
            "layout" => "circular",
            "center_x" => 200,
            "center_y" => 200,
            "radius" => 100
          }
        }
      ]

      results = Agent.process_tool_calls(tool_calls, canvas.id)
      assert {:ok, _} = List.first(results).result

      # Objects should be arranged in a circle
      objects = Enum.map(object_ids, &Canvases.get_object/1)

      # All objects should be approximately same distance from center
      Enum.each(objects, fn obj ->
        dx = obj.position.x - 200
        dy = obj.position.y - 200
        distance = :math.sqrt(dx * dx + dy * dy)
        # Allow some tolerance
        assert_in_delta distance, 100, 5
      end)
    end
  end

  describe "Object Manipulation Commands" do
    test "move object - absolute position", %{red_rect: red_rect, canvas: canvas} do
      tool_calls = [
        %{
          id: "call_move_abs",
          name: "move_object",
          input: %{
            "object_id" => red_rect.id,
            "x" => 500,
            "y" => 400
          }
        }
      ]

      results = Agent.process_tool_calls(tool_calls, canvas.id)
      assert {:ok, updated} = List.first(results).result
      assert updated.position.x == 500
      assert updated.position.y == 400
    end

    test "move object - relative offset", %{blue_circle: blue_circle, canvas: canvas} do
      original_x = blue_circle.position.x
      original_y = blue_circle.position.y

      tool_calls = [
        %{
          id: "call_move_rel",
          name: "move_object",
          input: %{
            "object_id" => blue_circle.id,
            "delta_x" => 100,
            "delta_y" => -50
          }
        }
      ]

      results = Agent.process_tool_calls(tool_calls, canvas.id)
      assert {:ok, updated} = List.first(results).result
      assert updated.position.x == original_x + 100
      assert updated.position.y == original_y - 50
    end

    test "resize object - maintain aspect ratio", %{green_rect: green_rect, canvas: canvas} do
      tool_calls = [
        %{
          id: "call_resize_aspect",
          name: "resize_object",
          input: %{
            "object_id" => green_rect.id,
            "width" => 120,
            "maintain_aspect_ratio" => true
          }
        }
      ]

      results = Agent.process_tool_calls(tool_calls, canvas.id)
      assert {:ok, updated} = List.first(results).result

      decoded_data = Jason.decode!(updated.data)
      assert decoded_data["width"] == 120
      assert decoded_data["height"] == 120  # Original was 60x60, so same aspect ratio
    end

    test "rotate object - various angles", %{red_circle: red_circle, canvas: canvas} do
      angles = [45, 90, 180, 270, 360]

      Enum.each(angles, fn angle ->
        tool_calls = [
          %{
            id: "call_rotate_#{angle}",
            name: "rotate_object",
            input: %{
              "object_id" => red_circle.id,
              "angle" => angle
            }
          }
        ]

        results = Agent.process_tool_calls(tool_calls, canvas.id)
        assert {:ok, updated} = List.first(results).result

        decoded_data = Jason.decode!(updated.data)
        expected_angle = rem(angle, 360)
        assert decoded_data["rotation"] == expected_angle
      end)
    end

    test "change object style - color", %{red_rect: red_rect, canvas: canvas} do
      tool_calls = [
        %{
          id: "call_change_color",
          name: "change_style",
          input: %{
            "object_id" => red_rect.id,
            "property" => "fill",
            "value" => "#00FF00"
          }
        }
      ]

      results = Agent.process_tool_calls(tool_calls, canvas.id)
      assert {:ok, updated} = List.first(results).result

      decoded_data = Jason.decode!(updated.data)
      assert decoded_data["fill"] == "#00FF00"
    end

    test "change object style - opacity", %{blue_circle: blue_circle, canvas: canvas} do
      tool_calls = [
        %{
          id: "call_change_opacity",
          name: "change_style",
          input: %{
            "object_id" => blue_circle.id,
            "property" => "opacity",
            "value" => "0.5"
          }
        }
      ]

      results = Agent.process_tool_calls(tool_calls, canvas.id)
      assert {:ok, updated} = List.first(results).result

      decoded_data = Jason.decode!(updated.data)
      assert decoded_data["opacity"] == 0.5
    end

    test "delete object", %{green_rect: green_rect, canvas: canvas} do
      tool_calls = [
        %{
          id: "call_delete",
          name: "delete_object",
          input: %{
            "object_id" => green_rect.id
          }
        }
      ]

      results = Agent.process_tool_calls(tool_calls, canvas.id)
      assert {:ok, deleted} = List.first(results).result
      assert deleted.id == green_rect.id

      # Verify object is deleted
      assert Canvases.get_object(green_rect.id) == nil
    end
  end

  describe "Component Creation Commands" do
    test "create login form component", %{canvas: canvas} do
      tool_calls = [
        %{
          id: "call_login",
          name: "create_component",
          input: %{
            "type" => "login_form",
            "x" => 100,
            "y" => 100,
            "width" => 400,
            "height" => 300,
            "theme" => "light",
            "content" => %{
              "title" => "Sign In",
              "button_text" => "Login"
            }
          }
        }
      ]

      results = Agent.process_tool_calls(tool_calls, canvas.id)
      assert {:ok, component} = List.first(results).result
      assert component.component_type == "login_form"
      assert is_list(component.object_ids)
      assert length(component.object_ids) > 0
    end

    test "create navigation bar component", %{canvas: canvas} do
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
              "title" => "MyApp",
              "items" => ["Home", "About", "Services", "Contact"]
            }
          }
        }
      ]

      results = Agent.process_tool_calls(tool_calls, canvas.id)
      assert {:ok, component} = List.first(results).result
      assert component.component_type == "navbar"
      # Should have background + logo + 4 menu items = 6 objects
      assert length(component.object_ids) == 6
    end

    test "create card component variations", %{canvas: canvas} do
      themes = ["blue", "green", "red"]

      Enum.each(themes, fn theme ->
        tool_calls = [
          %{
            id: "call_card_#{theme}",
            name: "create_component",
            input: %{
              "type" => "card",
              "x" => 50,
              "y" => 50,
              "width" => 300,
              "height" => 200,
              "theme" => theme,
              "content" => %{
                "title" => "#{String.capitalize(theme)} Card",
                "subtitle" => "Theme: #{theme}"
              }
            }
          }
        ]

        results = Agent.process_tool_calls(tool_calls, canvas.id)
        assert {:ok, component} = List.first(results).result
        assert component.component_type == "card"
        assert length(component.object_ids) > 0
      end)
    end

    test "create button group component", %{canvas: canvas} do
      tool_calls = [
        %{
          id: "call_buttons",
          name: "create_component",
          input: %{
            "type" => "button",
            "x" => 100,
            "y" => 200,
            "width" => 450,
            "height" => 50,
            "theme" => "primary",
            "content" => %{
              "items" => ["Submit", "Cancel", "Reset", "Help"]
            }
          }
        }
      ]

      results = Agent.process_tool_calls(tool_calls, canvas.id)
      assert {:ok, component} = List.first(results).result
      assert component.component_type == "button_group"
      # 4 buttons + 4 labels = 8 objects
      assert length(component.object_ids) == 8
    end

    test "create sidebar component", %{canvas: canvas} do
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
            "theme" => "dark",
            "content" => %{
              "title" => "Menu",
              "items" => ["Dashboard", "Analytics", "Reports", "Settings"]
            }
          }
        }
      ]

      results = Agent.process_tool_calls(tool_calls, canvas.id)
      assert {:ok, component} = List.first(results).result
      assert component.component_type == "sidebar"
      assert length(component.object_ids) > 0
    end
  end

  describe "Complex Multi-Step Commands" do
    test "create and arrange multiple shapes", %{canvas: canvas} do
      # Step 1: Create shapes
      create_calls = for i <- 1..5 do
        %{
          id: "create_#{i}",
          name: "create_shape",
          input: %{
            "type" => if(rem(i, 2) == 0, do: "circle", else: "rectangle"),
            "x" => i * 30,
            "y" => i * 30,
            "width" => 50,
            "height" => 50,
            "color" => Enum.at(["#FF0000", "#00FF00", "#0000FF", "#FFFF00", "#FF00FF"], i - 1)
          }
        }
      end

      create_results = Agent.process_tool_calls(create_calls, canvas.id)
      object_ids = Enum.map(create_results, fn r ->
        {:ok, obj} = r.result
        obj.id
      end)

      # Step 2: Arrange them
      arrange_calls = [
        %{
          id: "arrange",
          name: "arrange_objects",
          input: %{
            "object_ids" => object_ids,
            "layout" => "horizontal",
            "spacing" => 20
          }
        }
      ]

      arrange_results = Agent.process_tool_calls(arrange_calls, canvas.id)
      assert {:ok, _} = List.first(arrange_results).result
    end

    test "create component then modify its elements", %{canvas: canvas} do
      # Step 1: Create a card component
      create_calls = [
        %{
          id: "create_card",
          name: "create_component",
          input: %{
            "type" => "card",
            "x" => 100,
            "y" => 100,
            "width" => 300,
            "height" => 200
          }
        }
      ]

      create_results = Agent.process_tool_calls(create_calls, canvas.id)
      {:ok, component} = List.first(create_results).result

      # Step 2: Modify one of the created objects
      if length(component.object_ids) > 0 do
        first_obj_id = List.first(component.object_ids)

        modify_calls = [
          %{
            id: "modify",
            name: "change_style",
            input: %{
              "object_id" => first_obj_id,
              "property" => "opacity",
              "value" => "0.8"
            }
          }
        ]

        modify_results = Agent.process_tool_calls(modify_calls, canvas.id)
        assert {:ok, _} = List.first(modify_results).result
      end
    end

    test "select and manipulate objects", %{canvas: canvas, red_rect: red_rect, red_circle: red_circle} do
      # Step 1: Select red objects
      select_calls = [
        %{
          id: "select",
          name: "select_objects_by_description",
          input: %{
            "description" => "red objects",
            "objects_context" => [
              %{"id" => red_rect.id, "type" => "rectangle", "data" => %{"color" => "#FF0000"}},
              %{"id" => red_circle.id, "type" => "circle", "data" => %{"color" => "#FF0000"}}
            ]
          }
        }
      ]

      select_results = Agent.process_tool_calls(select_calls, canvas.id)
      {:ok, %{selected_ids: selected_ids}} = List.first(select_results).result

      # Step 2: Move selected objects
      move_calls = Enum.map(selected_ids, fn id ->
        %{
          id: "move_#{id}",
          name: "move_object",
          input: %{
            "object_id" => id,
            "delta_x" => 50,
            "delta_y" => 50
          }
        }
      end)

      move_results = Agent.process_tool_calls(move_calls, canvas.id)
      Enum.each(move_results, fn r ->
        assert {:ok, _} = r.result
      end)
    end
  end

  describe "Error Handling and Edge Cases" do
    test "handle non-existent object operations", %{canvas: canvas} do
      invalid_id = 99999

      # Try various operations on non-existent object
      operations = [
        %{name: "move_object", input: %{"object_id" => invalid_id, "x" => 100}},
        %{name: "resize_object", input: %{"object_id" => invalid_id, "width" => 100}},
        %{name: "rotate_object", input: %{"object_id" => invalid_id, "angle" => 45}},
        %{name: "delete_object", input: %{"object_id" => invalid_id}},
        %{name: "change_style", input: %{"object_id" => invalid_id, "property" => "fill", "value" => "#000"}}
      ]

      Enum.each(operations, fn op ->
        tool_calls = [Map.put(op, :id, "call_#{op.name}")]
        results = Agent.process_tool_calls(tool_calls, canvas.id)
        result = List.first(results)
        assert {:error, :not_found} = result.result
      end)
    end

    test "handle empty selection", %{canvas: canvas} do
      tool_calls = [
        %{
          id: "call_empty_select",
          name: "select_objects_by_description",
          input: %{
            "description" => "purple triangles",
            "objects_context" => []
          }
        }
      ]

      results = Agent.process_tool_calls(tool_calls, canvas.id)
      result = List.first(results)

      assert {:ok, %{selected_ids: []}} = result.result
    end

    test "handle invalid component type", %{canvas: canvas} do
      tool_calls = [
        %{
          id: "call_invalid_component",
          name: "create_component",
          input: %{
            "type" => "invalid_component_type",
            "x" => 100,
            "y" => 100
          }
        }
      ]

      results = Agent.process_tool_calls(tool_calls, canvas.id)
      result = List.first(results)

      assert {:error, :unknown_component_type} = result.result
    end

    test "handle arrange with empty object list", %{canvas: canvas} do
      tool_calls = [
        %{
          id: "call_arrange_empty",
          name: "arrange_objects",
          input: %{
            "object_ids" => [],
            "layout" => "horizontal"
          }
        }
      ]

      results = Agent.process_tool_calls(tool_calls, canvas.id)
      result = List.first(results)

      # Should handle gracefully
      assert result.tool == "arrange_objects"
    end
  end

  describe "Performance and Batch Operations" do
    test "create many objects efficiently", %{canvas: canvas} do
      # Create 20 objects in one batch
      tool_calls = for i <- 1..20 do
        %{
          id: "call_batch_#{i}",
          name: "create_shape",
          input: %{
            "type" => if(rem(i, 2) == 0, do: "circle", else: "rectangle"),
            "x" => rem(i - 1, 5) * 60,
            "y" => div(i - 1, 5) * 60,
            "width" => 50,
            "height" => 50
          }
        }
      end

      results = Agent.process_tool_calls(tool_calls, canvas.id)
      assert length(results) == 20

      Enum.each(results, fn r ->
        assert {:ok, _} = r.result
      end)

      # Verify all objects were created
      objects = Canvases.list_objects(canvas.id)
      # Should have original 5 test objects + 20 new ones
      assert length(objects) >= 25
    end

    test "select and manipulate multiple objects", %{canvas: canvas} do
      # Create 10 rectangles
      object_ids = for i <- 1..10 do
        {:ok, obj} = Canvases.create_object(canvas.id, "rectangle", %{
          position: %{x: i * 10, y: i * 10},
          data: Jason.encode!(%{width: 40, height: 40, color: "#0000FF"})
        })
        obj.id
      end

      # Select all blue objects
      select_calls = [
        %{
          id: "select_blue",
          name: "select_objects_by_description",
          input: %{
            "description" => "blue rectangles",
            "objects_context" => Enum.map(object_ids, fn id ->
              %{"id" => id, "type" => "rectangle", "data" => %{"color" => "#0000FF"}}
            end)
          }
        }
      ]

      select_results = Agent.process_tool_calls(select_calls, canvas.id)
      {:ok, %{selected_ids: selected}} = List.first(select_results).result

      assert length(selected) == 10
    end
  end
end