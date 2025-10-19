defmodule CollabCanvasWeb.StylesPanelLiveTest do
  use CollabCanvasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias CollabCanvas.{Canvases, Styles, Accounts}

  describe "StylesPanelLive" do
    setup do
      # Create test user
      {:ok, user} =
        Accounts.create_user(%{
          email: "test@example.com",
          name: "Test User",
          password: "password123"
        })

      # Create test canvas
      {:ok, canvas} =
        Canvases.create_canvas(%{
          name: "Test Canvas",
          created_by: user.id
        })

      # Create test styles
      {:ok, color_style} =
        Styles.create_style(canvas.id, %{
          name: "Primary Blue",
          type: "color",
          category: "primary",
          definition: %{r: 37, g: 99, b: 235, a: 1.0}
        })

      {:ok, text_style} =
        Styles.create_style(canvas.id, %{
          name: "Heading 1",
          type: "text",
          category: "heading",
          definition: %{
            fontFamily: "Arial, sans-serif",
            fontSize: 24,
            fontWeight: 700,
            lineHeight: 1.2
          }
        })

      {:ok, effect_style} =
        Styles.create_style(canvas.id, %{
          name: "Drop Shadow",
          type: "effect",
          category: "shadow",
          definition: %{
            type: "shadow",
            offsetX: 0,
            offsetY: 2,
            blur: 4,
            color: "rgba(0,0,0,0.5)"
          }
        })

      %{
        user: user,
        canvas: canvas,
        color_style: color_style,
        text_style: text_style,
        effect_style: effect_style
      }
    end

    test "renders styles panel with all style types", %{
      canvas: canvas,
      color_style: color_style,
      text_style: text_style,
      effect_style: effect_style
    } do
      # Render component
      html =
        render_component(CollabCanvasWeb.StylesPanelLive,
          id: "styles-panel",
          canvas_id: canvas.id
        )

      # Assert header is present
      assert html =~ "Styles"
      assert html =~ "Manage colors, text styles, and effects"

      # Assert export button is present
      assert html =~ "Export"

      # Assert all style sections are present
      assert html =~ "Colors"
      assert html =~ "Text Styles"
      assert html =~ "Effects"

      # Assert styles are rendered
      assert html =~ color_style.name
      assert html =~ text_style.name
      assert html =~ effect_style.name
    end

    test "opens and closes create style modal", %{canvas: canvas} do
      # Render component in live view
      {:ok, view, _html} =
        live_isolated(build_conn(), CollabCanvasWeb.StylesPanelLive,
          session: %{
            "canvas_id" => canvas.id
          }
        )

      # Open modal for color creation
      html =
        view
        |> element("button", "+ Add")
        |> render_click(%{"type" => "color"})

      assert html =~ "Create Color Style"
      assert html =~ "Name"
      assert html =~ "Category"

      # Close modal
      html =
        view
        |> element("button", "Cancel")
        |> render_click()

      refute html =~ "Create Color Style"
    end

    test "creates a new color style", %{canvas: canvas} do
      {:ok, view, _html} =
        live_isolated(build_conn(), CollabCanvasWeb.StylesPanelLive,
          session: %{
            "canvas_id" => canvas.id
          }
        )

      # Open modal
      view
      |> element("button[phx-value-type='color']")
      |> render_click()

      # Submit form
      view
      |> form("form", %{
        "type" => "color",
        "name" => "Test Red",
        "category" => "primary",
        "r" => "255",
        "g" => "0",
        "b" => "0",
        "a" => "1.0"
      })
      |> render_submit()

      # Assert style was created
      styles = Styles.list_styles(canvas.id, type: "color")
      assert Enum.any?(styles, fn s -> s.name == "Test Red" end)

      # Assert flash message
      assert view |> element(".alert-info") |> render() =~ "Test Red"
    end

    test "creates a new text style", %{canvas: canvas} do
      {:ok, view, _html} =
        live_isolated(build_conn(), CollabCanvasWeb.StylesPanelLive,
          session: %{
            "canvas_id" => canvas.id
          }
        )

      # Open modal
      view
      |> element("button[phx-value-type='text']")
      |> render_click()

      # Submit form
      view
      |> form("form", %{
        "type" => "text",
        "name" => "Body Text",
        "category" => "body",
        "fontFamily" => "Georgia, serif",
        "fontSize" => "16",
        "fontWeight" => "400",
        "lineHeight" => "1.5"
      })
      |> render_submit()

      # Assert style was created
      styles = Styles.list_styles(canvas.id, type: "text")
      assert Enum.any?(styles, fn s -> s.name == "Body Text" end)
    end

    test "creates a new effect style", %{canvas: canvas} do
      {:ok, view, _html} =
        live_isolated(build_conn(), CollabCanvasWeb.StylesPanelLive,
          session: %{
            "canvas_id" => canvas.id
          }
        )

      # Open modal
      view
      |> element("button[phx-value-type='effect']")
      |> render_click()

      # Submit form
      view
      |> form("form", %{
        "type" => "effect",
        "name" => "Glow Effect",
        "category" => "blur",
        "effectType" => "blur",
        "offsetX" => "0",
        "offsetY" => "0",
        "blur" => "8",
        "effectColor" => "rgba(0,0,255,0.3)"
      })
      |> render_submit()

      # Assert style was created
      styles = Styles.list_styles(canvas.id, type: "effect")
      assert Enum.any?(styles, fn s -> s.name == "Glow Effect" end)
    end

    test "deletes a style", %{canvas: canvas, color_style: color_style} do
      {:ok, view, _html} =
        live_isolated(build_conn(), CollabCanvasWeb.StylesPanelLive,
          session: %{
            "canvas_id" => canvas.id
          }
        )

      # Delete style
      view
      |> element("button[phx-value-id='#{color_style.id}']")
      |> render_click()

      # Assert style was deleted
      assert Styles.get_style(color_style.id) == nil

      # Assert flash message
      assert view |> element(".alert-info") |> render() =~ "deleted successfully"
    end

    test "selects a style", %{canvas: canvas, color_style: color_style} do
      {:ok, view, _html} =
        live_isolated(build_conn(), CollabCanvasWeb.StylesPanelLive,
          session: %{
            "canvas_id" => canvas.id
          }
        )

      # Select style
      html =
        view
        |> element("div[phx-value-id='#{color_style.id}']")
        |> render_click()

      # Assert style is selected (has blue border)
      assert html =~ "border-blue-500"
    end

    test "exports design tokens in CSS format", %{canvas: canvas} do
      {:ok, view, _html} =
        live_isolated(build_conn(), CollabCanvasWeb.StylesPanelLive,
          session: %{
            "canvas_id" => canvas.id
          }
        )

      # Select CSS format (default)
      view
      |> element("select")
      |> render_change(%{"format" => "css"})

      # Trigger export
      view
      |> element("button", "Export")
      |> render_click()

      # Assert export was successful (check for download event)
      assert_push_event(view, "download_tokens", %{
        format: "css",
        filename: "design-tokens.css"
      })
    end

    test "exports design tokens in SCSS format", %{canvas: canvas} do
      {:ok, view, _html} =
        live_isolated(build_conn(), CollabCanvasWeb.StylesPanelLive,
          session: %{
            "canvas_id" => canvas.id
          }
        )

      # Select SCSS format
      view
      |> element("select")
      |> render_change(%{"format" => "scss"})

      # Trigger export
      view
      |> element("button", "Export")
      |> render_click()

      # Assert export was successful
      assert_push_event(view, "download_tokens", %{
        format: "scss",
        filename: "design-tokens.scss"
      })
    end

    test "exports design tokens in JSON format", %{canvas: canvas} do
      {:ok, view, _html} =
        live_isolated(build_conn(), CollabCanvasWeb.StylesPanelLive,
          session: %{
            "canvas_id" => canvas.id
          }
        )

      # Select JSON format
      view
      |> element("select")
      |> render_change(%{"format" => "json"})

      # Trigger export
      view
      |> element("button", "Export")
      |> render_click()

      # Assert export was successful
      assert_push_event(view, "download_tokens", %{
        format: "json",
        filename: "design-tokens.json"
      })
    end

    test "exports design tokens in JS format", %{canvas: canvas} do
      {:ok, view, _html} =
        live_isolated(build_conn(), CollabCanvasWeb.StylesPanelLive,
          session: %{
            "canvas_id" => canvas.id
          }
        )

      # Select JS format
      view
      |> element("select")
      |> render_change(%{"format" => "js"})

      # Trigger export
      view
      |> element("button", "Export")
      |> render_click()

      # Assert export was successful
      assert_push_event(view, "download_tokens", %{
        format: "js",
        filename: "design-tokens.js"
      })
    end

    test "applies style to an object", %{canvas: canvas, color_style: color_style} do
      # Create a test object
      {:ok, object} =
        Canvases.create_object(canvas.id, "rectangle", %{
          position: %{x: 100, y: 100},
          data: Jason.encode!(%{width: 200, height: 100})
        })

      {:ok, view, _html} =
        live_isolated(build_conn(), CollabCanvasWeb.StylesPanelLive,
          session: %{
            "canvas_id" => canvas.id
          }
        )

      # Apply style (this would typically be triggered by a button in the UI)
      view
      |> element("button[phx-click='apply_style']")
      |> render_click(%{
        "style_id" => to_string(color_style.id),
        "object_id" => to_string(object.id)
      })

      # Assert style was applied
      updated_object = Canvases.get_object(object.id)
      assert updated_object != nil

      # Verify object data includes style properties
      data = Jason.decode!(updated_object.data)
      assert Map.has_key?(data, "fill")
    end

    test "handles style_created PubSub broadcast", %{canvas: canvas} do
      {:ok, view, _html} =
        live_isolated(build_conn(), CollabCanvasWeb.StylesPanelLive,
          session: %{
            "canvas_id" => canvas.id
          }
        )

      # Create new style (simulating another user's action)
      {:ok, new_style} =
        Styles.create_style(canvas.id, %{
          name: "Broadcast Test",
          type: "color",
          category: "primary",
          definition: %{r: 100, g: 200, b: 50, a: 1.0}
        })

      # Give LiveView time to process broadcast
      :timer.sleep(100)

      # Assert new style appears in the rendered HTML
      html = render(view)
      assert html =~ "Broadcast Test"
    end

    test "handles style_updated PubSub broadcast", %{canvas: canvas, color_style: color_style} do
      {:ok, view, _html} =
        live_isolated(build_conn(), CollabCanvasWeb.StylesPanelLive,
          session: %{
            "canvas_id" => canvas.id
          }
        )

      # Update style (simulating another user's action)
      {:ok, _updated_style} =
        Styles.update_style(color_style.id, %{
          name: "Updated Name"
        })

      # Give LiveView time to process broadcast
      :timer.sleep(100)

      # Assert updated name appears
      html = render(view)
      assert html =~ "Updated Name"
      refute html =~ color_style.name
    end

    test "handles style_deleted PubSub broadcast", %{canvas: canvas, color_style: color_style} do
      {:ok, view, _html} =
        live_isolated(build_conn(), CollabCanvasWeb.StylesPanelLive,
          session: %{
            "canvas_id" => canvas.id
          }
        )

      # Delete style (simulating another user's action)
      {:ok, _deleted_style} = Styles.delete_style(color_style.id)

      # Give LiveView time to process broadcast
      :timer.sleep(100)

      # Assert style no longer appears
      html = render(view)
      refute html =~ color_style.name
    end

    test "validates required fields when creating style", %{canvas: canvas} do
      {:ok, view, _html} =
        live_isolated(build_conn(), CollabCanvasWeb.StylesPanelLive,
          session: %{
            "canvas_id" => canvas.id
          }
        )

      # Open modal
      view
      |> element("button[phx-value-type='color']")
      |> render_click()

      # Submit form with missing name
      html =
        view
        |> form("form", %{
          "type" => "color",
          "name" => "",
          "category" => "primary",
          "r" => "255",
          "g" => "0",
          "b" => "0",
          "a" => "1.0"
        })
        |> render_submit()

      # Assert error is shown
      assert html =~ "Failed to create style"
    end

    test "displays empty state messages", %{user: user} do
      # Create canvas with no styles
      {:ok, empty_canvas} =
        Canvases.create_canvas(%{
          name: "Empty Canvas",
          created_by: user.id
        })

      html =
        render_component(CollabCanvasWeb.StylesPanelLive,
          id: "styles-panel",
          canvas_id: empty_canvas.id
        )

      # Assert empty state messages
      assert html =~ "No color styles yet"
      assert html =~ "No text styles yet"
      assert html =~ "No effect styles yet"
    end

    test "renders color preview correctly", %{canvas: canvas, color_style: color_style} do
      html =
        render_component(CollabCanvasWeb.StylesPanelLive,
          id: "styles-panel",
          canvas_id: canvas.id
        )

      # Assert color is rendered with correct RGB values
      assert html =~ "rgb(37, 99, 235)"
    end

    test "renders text style preview correctly", %{canvas: canvas, text_style: text_style} do
      html =
        render_component(CollabCanvasWeb.StylesPanelLive,
          id: "styles-panel",
          canvas_id: canvas.id
        )

      # Assert text preview has correct style attributes
      assert html =~ "font-family: Arial, sans-serif"
      assert html =~ "font-size: 24px"
      assert html =~ "font-weight: 700"
      assert html =~ "line-height: 1.2"
    end

    test "performance: style application completes within 50ms", %{
      canvas: canvas,
      color_style: color_style
    } do
      # Create a test object
      {:ok, object} =
        Canvases.create_object(canvas.id, "rectangle", %{
          position: %{x: 100, y: 100},
          data: Jason.encode!(%{width: 200, height: 100})
        })

      # Measure style application time
      start_time = System.monotonic_time(:millisecond)
      {:ok, _} = Styles.apply_style(object.id, color_style.id)
      elapsed = System.monotonic_time(:millisecond) - start_time

      # Assert performance target is met
      assert elapsed < 50, "Style application took #{elapsed}ms, exceeding 50ms target"
    end
  end
end
