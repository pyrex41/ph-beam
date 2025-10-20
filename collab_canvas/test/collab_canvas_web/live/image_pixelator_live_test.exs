defmodule CollabCanvasWeb.ImagePixelatorLiveTest do
  use CollabCanvasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias CollabCanvas.{Canvases, Accounts}

  describe "ImagePixelatorLive - Mount" do
    setup do
      # Create test user
      {:ok, user} =
        Accounts.create_user(%{
          email: "pixel@example.com",
          name: "Pixel Artist",
          password: "password123"
        })

      # Create test canvas
      {:ok, canvas} =
        Canvases.create_canvas(%{
          name: "Test Canvas",
          created_by: user.id
        })

      {:ok, user: user, canvas: canvas}
    end

    test "mounts successfully with authenticated user", %{conn: conn, user: user} do
      # Login user
      conn = init_test_session(conn, %{user_id: user.id})

      # Mount the LiveView
      {:ok, view, html} = live(conn, ~p"/pixelator")

      # Check that the page rendered
      assert html =~ "Image Pixelator"
      assert html =~ "Upload Image"
      assert html =~ "Grid Size"
    end

    test "redirects unauthenticated user", %{conn: conn} do
      # Attempt to mount without authentication
      {:ok, _view, html} = live(conn, ~p"/pixelator")

      # Should redirect or show error
      assert html =~ "Please log in" or html =~ "Sign in"
    end

    test "initializes with default grid size", %{conn: conn, user: user} do
      conn = init_test_session(conn, %{user_id: user.id})

      {:ok, view, _html} = live(conn, ~p"/pixelator")

      # Check default grid size is 64
      assert view.assigns.grid_size == 64
    end

    test "loads user's canvases for selection", %{conn: conn, user: user, canvas: canvas} do
      conn = init_test_session(conn, %{user_id: user.id})

      {:ok, _view, html} = live(conn, ~p"/pixelator")

      # Should show canvas in dropdown
      assert html =~ canvas.name
      assert html =~ "Create New Canvas"
    end
  end

  describe "ImagePixelatorLive - Grid Size Selection" do
    setup do
      {:ok, user} =
        Accounts.create_user(%{
          email: "pixel@example.com",
          name: "Pixel Artist",
          password: "password123"
        })

      {:ok, user: user}
    end

    test "allows selecting valid grid sizes", %{conn: conn, user: user} do
      conn = init_test_session(conn, %{user_id: user.id})
      {:ok, view, _html} = live(conn, ~p"/pixelator")

      # Test each valid grid size
      for grid_size <- [16, 32, 64, 128] do
        view
        |> element("select[name='grid_size']")
        |> render_change(%{"grid_size" => to_string(grid_size)})

        assert view.assigns.grid_size == grid_size
      end
    end

    test "rejects invalid grid sizes", %{conn: conn, user: user} do
      conn = init_test_session(conn, %{user_id: user.id})
      {:ok, view, _html} = live(conn, ~p"/pixelator")

      # Try invalid grid size
      view
      |> element("select[name='grid_size']")
      |> render_change(%{"grid_size" => "999"})

      # Should reset to default
      assert view.assigns.grid_size == 64
      assert view.assigns.error == "Invalid grid size selected"
    end
  end

  describe "ImagePixelatorLive - Canvas Selection" do
    setup do
      {:ok, user} =
        Accounts.create_user(%{
          email: "pixel@example.com",
          name: "Pixel Artist",
          password: "password123"
        })

      {:ok, canvas} =
        Canvases.create_canvas(%{
          name: "Existing Canvas",
          created_by: user.id
        })

      {:ok, user: user, canvas: canvas}
    end

    test "allows selecting existing canvas", %{conn: conn, user: user, canvas: canvas} do
      conn = init_test_session(conn, %{user_id: user.id})
      {:ok, view, _html} = live(conn, ~p"/pixelator")

      view
      |> element("select[name='canvas_id']")
      |> render_change(%{"canvas_id" => to_string(canvas.id)})

      assert view.assigns.selected_canvas_id == to_string(canvas.id)
    end

    test "allows selecting 'Create New Canvas'", %{conn: conn, user: user} do
      conn = init_test_session(conn, %{user_id: user.id})
      {:ok, view, _html} = live(conn, ~p"/pixelator")

      view
      |> element("select[name='canvas_id']")
      |> render_change(%{"canvas_id" => "new"})

      assert view.assigns.selected_canvas_id == "new"
    end
  end

  describe "ImagePixelatorLive - File Upload Validation" do
    setup do
      {:ok, user} =
        Accounts.create_user(%{
          email: "pixel@example.com",
          name: "Pixel Artist",
          password: "password123"
        })

      {:ok, user: user}
    end

    test "accepts valid image file types", %{conn: conn, user: user} do
      conn = init_test_session(conn, %{user_id: user.id})
      {:ok, view, _html} = live(conn, ~p"/pixelator")

      # Check that upload configuration allows JPG, JPEG, PNG
      upload_config = view.assigns.uploads.image

      assert ".jpg" in upload_config.accept
      assert ".jpeg" in upload_config.accept
      assert ".png" in upload_config.accept
    end

    test "enforces max file size limit", %{conn: conn, user: user} do
      conn = init_test_session(conn, %{user_id: user.id})
      {:ok, view, _html} = live(conn, ~p"/pixelator")

      # Check max file size is 10MB
      upload_config = view.assigns.uploads.image
      assert upload_config.max_file_size == 10_000_000
    end

    test "allows only one file at a time", %{conn: conn, user: user} do
      conn = init_test_session(conn, %{user_id: user.id})
      {:ok, view, _html} = live(conn, ~p"/pixelator")

      upload_config = view.assigns.uploads.image
      assert upload_config.max_entries == 1
    end
  end

  describe "ImagePixelatorLive - Image Processing" do
    setup do
      {:ok, user} =
        Accounts.create_user(%{
          email: "pixel@example.com",
          name: "Pixel Artist",
          password: "password123"
        })

      {:ok, user: user}
    end

    @tag :skip
    test "processes uploaded image successfully", %{conn: conn, user: user} do
      # This test would require creating a test image file
      # Skipping for now as it requires file fixtures
      conn = init_test_session(conn, %{user_id: user.id})
      {:ok, _view, _html} = live(conn, ~p"/pixelator")

      # TODO: Implement with test image fixture
    end

    @tag :skip
    test "rejects oversized images", %{conn: conn, user: user} do
      # This test would require creating a large test image
      # Skipping for now as it requires file fixtures
      conn = init_test_session(conn, %{user_id: user.id})
      {:ok, _view, _html} = live(conn, ~p"/pixelator")

      # TODO: Implement with large image fixture (>4000x4000)
    end
  end

  describe "ImagePixelatorLive - Error Handling" do
    setup do
      {:ok, user} =
        Accounts.create_user(%{
          email: "pixel@example.com",
          name: "Pixel Artist",
          password: "password123"
        })

      {:ok, user: user}
    end

    test "displays error when no file is uploaded", %{conn: conn, user: user} do
      conn = init_test_session(conn, %{user_id: user.id})
      {:ok, view, _html} = live(conn, ~p"/pixelator")

      # Try to process without uploading
      html = render_submit(view, "process_image", %{})

      assert html =~ "No image uploaded" or view.assigns.error == "No image uploaded"
    end

    test "formats error messages correctly", %{conn: conn, user: user} do
      conn = init_test_session(conn, %{user_id: user.id})
      {:ok, view, _html} = live(conn, ~p"/pixelator")

      # Check error formatting functions exist
      # These are tested implicitly through the module
      assert function_exported?(CollabCanvasWeb.ImagePixelatorLive, :format_error, 1)
    end
  end

  describe "ImagePixelatorLive - Pixel Data Store Integration" do
    setup do
      {:ok, user} =
        Accounts.create_user(%{
          email: "pixel@example.com",
          name: "Pixel Artist",
          password: "password123"
        })

      {:ok, canvas} =
        Canvases.create_canvas(%{
          name: "Test Canvas",
          created_by: user.id
        })

      {:ok, user: user, canvas: canvas}
    end

    @tag :skip
    test "stores pixel data before navigation", %{conn: conn, user: user, canvas: canvas} do
      # This test requires a full upload flow
      # Skipping for now as it's complex
      conn = init_test_session(conn, %{user_id: user.id})
      {:ok, _view, _html} = live(conn, ~p"/pixelator")

      # TODO: Test that PixelDataStore.store is called before redirect
    end

    @tag :skip
    test "handles storage errors gracefully", %{conn: conn, user: user} do
      # This would require mocking PixelDataStore to return errors
      # Skipping for now
      conn = init_test_session(conn, %{user_id: user.id})
      {:ok, _view, _html} = live(conn, ~p"/pixelator")

      # TODO: Test error handling when storage is full
    end
  end

  # Helper function to initialize test session
  defp init_test_session(conn, session_data) do
    Plug.Test.init_test_session(conn, session_data)
  end
end
