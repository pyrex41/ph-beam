defmodule CollabCanvas.StylesTest do
  use CollabCanvas.DataCase, async: true

  alias CollabCanvas.Styles
  alias CollabCanvas.Styles.Style
  alias CollabCanvas.{Accounts, Canvases}

  describe "create_style/2" do
    setup do
      user = create_user()
      {:ok, canvas} = Canvases.create_canvas(user.id, "Test Canvas")
      %{canvas: canvas, user: user}
    end

    test "creates a color style successfully", %{canvas: canvas, user: user} do
      attrs = %{
        name: "Primary Blue",
        type: "color",
        category: "primary",
        definition: %{r: 37, g: 99, b: 235, a: 1.0},
        created_by: user.id
      }

      assert {:ok, %Style{} = style} = Styles.create_style(canvas.id, attrs)
      assert style.name == "Primary Blue"
      assert style.type == "color"
      assert style.category == "primary"
      assert style.canvas_id == canvas.id
      assert style.created_by == user.id
    end

    test "creates a text style successfully", %{canvas: canvas} do
      attrs = %{
        name: "Heading 1",
        type: "text",
        category: "heading",
        definition: %{
          fontFamily: "Inter",
          fontSize: 32,
          fontWeight: 700,
          lineHeight: 1.2
        }
      }

      assert {:ok, %Style{} = style} = Styles.create_style(canvas.id, attrs)
      assert style.name == "Heading 1"
      assert style.type == "text"
    end

    test "creates an effect style successfully", %{canvas: canvas} do
      attrs = %{
        name: "Drop Shadow",
        type: "effect",
        category: "shadow",
        definition: %{
          type: "shadow",
          offsetX: 0,
          offsetY: 4,
          blur: 8,
          color: %{r: 0, g: 0, b: 0, a: 0.1}
        }
      }

      assert {:ok, %Style{} = style} = Styles.create_style(canvas.id, attrs)
      assert style.name == "Drop Shadow"
      assert style.type == "effect"
    end

    test "accepts definition as JSON string", %{canvas: canvas} do
      attrs = %{
        name: "Test Color",
        type: "color",
        definition: ~s({"r": 255, "g": 0, "b": 0, "a": 1.0})
      }

      assert {:ok, %Style{} = style} = Styles.create_style(canvas.id, attrs)
      assert style.definition =~ "255"
    end

    test "returns error for invalid type", %{canvas: canvas} do
      attrs = %{
        name: "Invalid Style",
        type: "invalid_type",
        definition: %{test: "data"}
      }

      assert {:error, changeset} = Styles.create_style(canvas.id, attrs)
      assert "is invalid" in errors_on(changeset).type
    end

    test "returns error for invalid JSON definition", %{canvas: canvas} do
      attrs = %{
        name: "Bad JSON",
        type: "color",
        definition: "{invalid json"
      }

      assert {:error, changeset} = Styles.create_style(canvas.id, attrs)
      assert "must be valid JSON" in errors_on(changeset).definition
    end

    test "returns error for missing required fields", %{canvas: canvas} do
      attrs = %{name: "Incomplete"}

      assert {:error, changeset} = Styles.create_style(canvas.id, attrs)
      assert "can't be blank" in errors_on(changeset).type
      assert "can't be blank" in errors_on(changeset).definition
    end

    test "broadcasts style_created event", %{canvas: canvas} do
      Styles.subscribe_to_styles(canvas.id)

      attrs = %{
        name: "Broadcast Test",
        type: "color",
        definition: %{r: 255, g: 0, b: 0, a: 1.0}
      }

      {:ok, style} = Styles.create_style(canvas.id, attrs)

      assert_receive {:style_created, ^style}
    end
  end

  describe "get_style/1" do
    setup do
      {user, canvas, style} = create_test_style()
      %{user: user, canvas: canvas, style: style}
    end

    test "returns the style when it exists", %{style: style} do
      found_style = Styles.get_style(style.id)
      assert found_style.id == style.id
      assert found_style.name == style.name
    end

    test "returns nil when style doesn't exist" do
      assert Styles.get_style(99999) == nil
    end
  end

  describe "get_style_with_preloads/2" do
    setup do
      {user, canvas, style} = create_test_style()
      %{user: user, canvas: canvas, style: style}
    end

    test "returns style with preloaded associations", %{style: style} do
      loaded_style = Styles.get_style_with_preloads(style.id)
      assert loaded_style.id == style.id
      assert %Canvases.Canvas{} = loaded_style.canvas
      assert %Accounts.User{} = loaded_style.creator
    end

    test "returns nil when style doesn't exist" do
      assert Styles.get_style_with_preloads(99999) == nil
    end
  end

  describe "list_styles/2" do
    setup do
      user = create_user()
      {:ok, canvas} = Canvases.create_canvas(user.id, "Test Canvas")

      # Create multiple styles
      {:ok, color1} =
        Styles.create_style(canvas.id, %{
          name: "Blue",
          type: "color",
          category: "primary",
          definition: %{r: 0, g: 0, b: 255, a: 1.0}
        })

      {:ok, color2} =
        Styles.create_style(canvas.id, %{
          name: "Red",
          type: "color",
          category: "accent",
          definition: %{r: 255, g: 0, b: 0, a: 1.0}
        })

      {:ok, text1} =
        Styles.create_style(canvas.id, %{
          name: "Heading",
          type: "text",
          category: "heading",
          definition: %{fontSize: 24}
        })

      %{canvas: canvas, color1: color1, color2: color2, text1: text1}
    end

    test "lists all styles for a canvas", %{canvas: canvas} do
      styles = Styles.list_styles(canvas.id)
      assert length(styles) == 3
    end

    test "filters styles by type", %{canvas: canvas} do
      color_styles = Styles.list_styles(canvas.id, type: "color")
      assert length(color_styles) == 2
      assert Enum.all?(color_styles, &(&1.type == "color"))

      text_styles = Styles.list_styles(canvas.id, type: "text")
      assert length(text_styles) == 1
      assert hd(text_styles).type == "text"
    end

    test "filters styles by category", %{canvas: canvas} do
      primary_styles = Styles.list_styles(canvas.id, category: "primary")
      assert length(primary_styles) == 1
      assert hd(primary_styles).category == "primary"
    end

    test "filters by type and category", %{canvas: canvas} do
      styles = Styles.list_styles(canvas.id, type: "color", category: "accent")
      assert length(styles) == 1
      assert hd(styles).name == "Red"
    end

    test "returns empty list for canvas with no styles" do
      user = create_user()
      {:ok, empty_canvas} = Canvases.create_canvas(user.id, "Empty")
      assert Styles.list_styles(empty_canvas.id) == []
    end
  end

  describe "update_style/2" do
    setup do
      {user, canvas, style} = create_test_style()
      %{user: user, canvas: canvas, style: style}
    end

    test "updates style successfully", %{style: style} do
      new_definition = %{r: 100, g: 100, b: 100, a: 1.0}
      assert {:ok, updated} = Styles.update_style(style.id, %{definition: new_definition})
      assert updated.id == style.id

      # Decode returns string keys, so compare with string keys
      decoded = Style.decode_definition(updated)
      assert decoded["r"] == 100
      assert decoded["g"] == 100
      assert decoded["b"] == 100
      assert decoded["a"] == 1.0
    end

    test "updates style name", %{style: style} do
      assert {:ok, updated} = Styles.update_style(style.id, %{name: "Updated Name"})
      assert updated.name == "Updated Name"
    end

    test "returns error for non-existent style" do
      assert {:error, :not_found} = Styles.update_style(99999, %{name: "Test"})
    end

    test "returns error for invalid data", %{style: style} do
      assert {:error, changeset} = Styles.update_style(style.id, %{type: "invalid"})
      assert "is invalid" in errors_on(changeset).type
    end

    test "broadcasts style_updated event", %{canvas: canvas, style: style} do
      Styles.subscribe_to_styles(canvas.id)

      {:ok, updated} = Styles.update_style(style.id, %{name: "Broadcast Test"})

      assert_receive {:style_updated, ^updated}
    end

    test "completes within performance target", %{style: style} do
      {elapsed, {:ok, _}} =
        :timer.tc(fn ->
          Styles.update_style(style.id, %{name: "Performance Test"})
        end)

      elapsed_ms = div(elapsed, 1000)
      assert elapsed_ms < 50, "Style update took #{elapsed_ms}ms, expected < 50ms"
    end
  end

  describe "delete_style/1" do
    setup do
      {user, canvas, style} = create_test_style()
      %{user: user, canvas: canvas, style: style}
    end

    test "deletes style successfully", %{style: style} do
      assert {:ok, deleted} = Styles.delete_style(style.id)
      assert deleted.id == style.id
      assert Styles.get_style(style.id) == nil
    end

    test "returns error for non-existent style" do
      assert {:error, :not_found} = Styles.delete_style(99999)
    end

    test "broadcasts style_deleted event", %{canvas: canvas, style: style} do
      Styles.subscribe_to_styles(canvas.id)

      {:ok, _} = Styles.delete_style(style.id)

      assert_receive {:style_deleted, style_id}
      assert style_id == style.id
    end
  end

  describe "apply_style/2" do
    setup do
      user = create_user()
      {:ok, canvas} = Canvases.create_canvas(user.id, "Test Canvas")

      {:ok, object} =
        Canvases.create_object(canvas.id, "rectangle", %{
          position: %{x: 10, y: 20},
          data: Jason.encode!(%{width: 100, height: 50})
        })

      {:ok, color_style} =
        Styles.create_style(canvas.id, %{
          name: "Test Color",
          type: "color",
          definition: %{r: 255, g: 0, b: 0, a: 1.0}
        })

      %{canvas: canvas, object: object, style: color_style}
    end

    test "applies color style to object", %{object: object, style: style} do
      assert {:ok, updated_object} = Styles.apply_style(object.id, style.id)
      assert updated_object.id == object.id

      # Parse the JSON data to check the fill
      {:ok, data} = Jason.decode(updated_object.data)
      assert data["fill"]["r"] == 255
      assert data["fill"]["g"] == 0
      assert data["fill"]["b"] == 0
    end

    test "applies text style to object", %{canvas: canvas, object: object} do
      {:ok, text_style} =
        Styles.create_style(canvas.id, %{
          name: "Text Style",
          type: "text",
          definition: %{fontFamily: "Arial", fontSize: 16}
        })

      assert {:ok, updated_object} = Styles.apply_style(object.id, text_style.id)

      # Parse the JSON data to check the text style
      {:ok, data} = Jason.decode(updated_object.data)
      assert data["textStyle"]["fontFamily"] == "Arial"
      assert data["textStyle"]["fontSize"] == 16
    end

    test "applies effect style to object", %{canvas: canvas, object: object} do
      {:ok, effect_style} =
        Styles.create_style(canvas.id, %{
          name: "Shadow",
          type: "effect",
          definition: %{type: "shadow", blur: 10}
        })

      assert {:ok, updated_object} = Styles.apply_style(object.id, effect_style.id)

      # Parse the JSON data to check the effects
      {:ok, data} = Jason.decode(updated_object.data)
      assert is_list(data["effects"])
      assert length(data["effects"]) > 0
    end

    test "returns error for non-existent object", %{style: style} do
      assert {:error, :not_found} = Styles.apply_style(99999, style.id)
    end

    test "returns error for non-existent style", %{object: object} do
      assert {:error, :not_found} = Styles.apply_style(object.id, 99999)
    end

    test "completes within performance target", %{object: object, style: style} do
      {elapsed, {:ok, _}} =
        :timer.tc(fn ->
          Styles.apply_style(object.id, style.id)
        end)

      elapsed_ms = div(elapsed, 1000)
      assert elapsed_ms < 50, "Style application took #{elapsed_ms}ms, expected < 50ms"
    end
  end

  describe "export_design_tokens/2" do
    setup do
      user = create_user()
      {:ok, canvas} = Canvases.create_canvas(user.id, "Design System")

      # Create various styles
      {:ok, _} =
        Styles.create_style(canvas.id, %{
          name: "Primary Blue",
          type: "color",
          category: "primary",
          definition: %{r: 37, g: 99, b: 235, a: 1.0}
        })

      {:ok, _} =
        Styles.create_style(canvas.id, %{
          name: "Heading 1",
          type: "text",
          category: "heading",
          definition: %{fontFamily: "Inter", fontSize: 32, fontWeight: 700, lineHeight: 1.2}
        })

      %{canvas: canvas}
    end

    test "exports to CSS format", %{canvas: canvas} do
      assert {:ok, css} = Styles.export_design_tokens(canvas.id, :css)
      assert css =~ ":root"
      assert css =~ "--primary-blue"
      assert css =~ "rgb(37, 99, 235)"
      assert css =~ "--heading-1-font-family"
      assert css =~ "Inter"
    end

    test "exports to SCSS format", %{canvas: canvas} do
      assert {:ok, scss} = Styles.export_design_tokens(canvas.id, :scss)
      assert scss =~ "$primary-blue"
      assert scss =~ "rgb(37, 99, 235)"
      assert scss =~ "$heading-1-font-family"
    end

    test "exports to JSON format", %{canvas: canvas} do
      assert {:ok, json} = Styles.export_design_tokens(canvas.id, :json)
      assert json =~ "colors"
      assert json =~ "primary-blue"
      assert json =~ "texts"
      assert json =~ "heading-1"

      # Verify it's valid JSON
      assert {:ok, _parsed} = Jason.decode(json)
    end

    test "exports to JavaScript format", %{canvas: canvas} do
      assert {:ok, js} = Styles.export_design_tokens(canvas.id, :js)
      assert js =~ "export const tokens"
      assert js =~ "primary_blue"
      assert js =~ "heading_1"
    end

    test "returns error for unsupported format", %{canvas: canvas} do
      assert {:error, message} = Styles.export_design_tokens(canvas.id, :xml)
      assert message =~ "Unsupported format"
    end

    test "handles RGBA colors in CSS export", %{canvas: canvas} do
      {:ok, _} =
        Styles.create_style(canvas.id, %{
          name: "Transparent Blue",
          type: "color",
          definition: %{r: 37, g: 99, b: 235, a: 0.5}
        })

      assert {:ok, css} = Styles.export_design_tokens(canvas.id, :css)
      assert css =~ "rgba(37, 99, 235, 0.5)"
    end

    test "exports empty canvas", %{canvas: _canvas} do
      user = create_user()
      {:ok, empty_canvas} = Canvases.create_canvas(user.id, "Empty")

      assert {:ok, css} = Styles.export_design_tokens(empty_canvas.id, :css)
      assert css =~ ":root"
    end
  end

  describe "PubSub integration" do
    setup do
      user = create_user()
      {:ok, canvas} = Canvases.create_canvas(user.id, "Test Canvas")
      %{canvas: canvas, user: user}
    end

    test "subscribe_to_styles/1 allows receiving broadcasts", %{canvas: canvas} do
      assert :ok = Styles.subscribe_to_styles(canvas.id)

      attrs = %{
        name: "Test Style",
        type: "color",
        definition: %{r: 255, g: 0, b: 0, a: 1.0}
      }

      {:ok, style} = Styles.create_style(canvas.id, attrs)

      assert_receive {:style_created, ^style}
    end

    test "unsubscribe_from_styles/1 stops receiving broadcasts", %{canvas: canvas} do
      Styles.subscribe_to_styles(canvas.id)
      Styles.unsubscribe_from_styles(canvas.id)

      attrs = %{
        name: "Test Style",
        type: "color",
        definition: %{r: 255, g: 0, b: 0, a: 1.0}
      }

      Styles.create_style(canvas.id, attrs)

      refute_receive {:style_created, _}, 100
    end

    test "broadcasts are scoped to canvas", %{canvas: canvas1} do
      user = create_user()
      {:ok, canvas2} = Canvases.create_canvas(user.id, "Canvas 2")

      Styles.subscribe_to_styles(canvas1.id)

      # Create style on canvas2
      attrs = %{
        name: "Test Style",
        type: "color",
        definition: %{r: 255, g: 0, b: 0, a: 1.0}
      }

      Styles.create_style(canvas2.id, attrs)

      # Should not receive broadcast for canvas2
      refute_receive {:style_created, _}, 100
    end
  end

  # Helper functions

  defp create_user do
    unique_email = "user_#{System.unique_integer([:positive])}@example.com"

    {:ok, user} =
      Accounts.create_user(%{
        email: unique_email,
        name: "Test User"
      })

    user
  end

  defp create_test_style do
    user = create_user()
    {:ok, canvas} = Canvases.create_canvas(user.id, "Test Canvas")

    {:ok, style} =
      Styles.create_style(canvas.id, %{
        name: "Test Color",
        type: "color",
        category: "primary",
        definition: %{r: 37, g: 99, b: 235, a: 1.0},
        created_by: user.id
      })

    {user, canvas, style}
  end
end
