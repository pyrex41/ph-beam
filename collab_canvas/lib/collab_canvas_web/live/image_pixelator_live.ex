defmodule CollabCanvasWeb.ImagePixelatorLive do
  @moduledoc """
  LiveView module for image pixelation functionality.

  This module provides an interactive interface for users to upload images,
  select a pixelation grid size, and view the pixelated result rendered on
  an HTML canvas. The pixelation process converts an uploaded image into a
  grid of colored squares, creating a retro pixel-art effect.

  ## Features

  - **Image Upload**: Supports JPG, JPEG, and PNG formats up to 10MB
  - **Grid Size Selection**: User-configurable grid sizes (16x16, 32x32, 64x64, 128x128)
  - **Server-Side Processing**: Uses Mogrify and Image libraries for efficient processing
  - **Client-Side Rendering**: Renders pixel data on HTML5 canvas via JavaScript hooks
  - **Error Handling**: Comprehensive validation and user-friendly error messages

  ## State Management

  The module maintains the following socket assigns:
  - `:grid_size` - Selected grid size (default: 64)
  - `:pixel_data` - Processed pixel data ready for canvas rendering
  - `:error` - Current error message (nil if no error)
  - `:processing` - Boolean flag indicating processing state

  ## Processing Flow

  1. User uploads image and selects grid size
  2. Server validates file type and size
  3. Image is resized to grid_size x grid_size using Mogrify
  4. RGB values extracted and converted to hex codes using Image library
  5. Pixel data pushed to client via push_event
  6. JavaScript hook renders on canvas
  """
  use CollabCanvasWeb, :live_view

  require Logger
  alias CollabCanvas.Canvases
  alias CollabCanvas.Accounts
  alias CollabCanvas.PixelDataStore

  @max_file_size 10_000_000
  @allowed_extensions ~w(.jpg .jpeg .png)
  @default_grid_size 64

  @doc """
  Mounts the image pixelator LiveView and initializes state.

  ## Parameters

  - `_params`: URL parameters (unused)
  - `_session`: Session data (unused for this simple view)
  - `socket`: The LiveView socket

  ## Returns

  `{:ok, socket}` with initialized assigns and file upload configuration
  """
  @impl true
  def mount(_params, _session, socket) do
    grid_size_options = [
      {"16x16", 16},
      {"32x32", 32},
      {"64x64", 64},
      {"128x128", 128}
    ]

    # Get user's canvases for selection
    user = Accounts.get_user(1) || create_default_user()
    canvases = Canvases.list_user_canvases(user.id)

    canvas_options = [{"Create New Canvas", "new"}] ++ Enum.map(canvases, fn c -> {c.name, c.id} end)

    {:ok,
     socket
     |> assign(:grid_size, @default_grid_size)
     |> assign(:grid_size_options, grid_size_options)
     |> assign(:pixel_data, nil)
     |> assign(:error, nil)
     |> assign(:processing, false)
     |> assign(:current_user, user)
     |> assign(:canvas_options, canvas_options)
     |> assign(:selected_canvas_id, "new")
     |> allow_upload(:image,
       accept: @allowed_extensions,
       max_entries: 1,
       max_file_size: @max_file_size,
       auto_upload: true
     )}
  end

  @impl true
  def handle_event("select_grid_size", %{"grid_size" => grid_size_str}, socket) do
    case Integer.parse(grid_size_str) do
      {grid_size, ""} when grid_size in [16, 32, 64, 128] ->
        {:noreply, assign(socket, :grid_size, grid_size)}

      _ ->
        {:noreply,
         socket
         |> assign(:error, "Invalid grid size selected")
         |> assign(:grid_size, @default_grid_size)}
    end
  end

  @impl true
  def handle_event("select_canvas", %{"canvas_id" => canvas_id}, socket) do
    {:noreply, assign(socket, :selected_canvas_id, canvas_id)}
  end

  @impl true
  def handle_event("process_image", _params, socket) do
    case uploaded_entries(socket, :image) do
      {[_ | _] = _entries, []} ->
        # Process the first (and only) uploaded image
        result =
          consume_uploaded_entries(socket, :image, fn %{path: path}, _entry ->
            process_image(path, socket.assigns.grid_size)
          end)

        case result do
          [%{pixels: _, width: _, height: _} = pixel_data] ->
            {:noreply,
             socket
             |> assign(:pixel_data, pixel_data)
             |> assign(:error, nil)
             |> assign(:processing, false)
             |> push_event("render_pixels", %{
               pixels: pixel_data.pixels,
               width: pixel_data.width,
               height: pixel_data.height
             })}

          [{:error, reason}] ->
            Logger.error("Image processing failed: #{inspect(reason)}")

            {:noreply,
             socket
             |> assign(:error, "Failed to process image: #{format_error(reason)}")
             |> assign(:processing, false)}

          [] ->
            {:noreply,
             socket
             |> assign(:error, "No image uploaded")
             |> assign(:processing, false)}

          other ->
            Logger.error("Unexpected result from image processing: #{inspect(other)}")

            {:noreply,
             socket
             |> assign(:error, "Failed to process image")
             |> assign(:processing, false)}
        end

      {[], []} ->
        {:noreply,
         socket
         |> assign(:error, "No image uploaded")
         |> assign(:processing, false)}

      {_completed, [_ | _] = errors} ->
        error_msg =
          errors
          |> Enum.map(fn {_ref, reason} -> format_error(reason) end)
          |> Enum.join(", ")

        {:noreply,
         socket
         |> assign(:error, "Upload failed: #{error_msg}")
         |> assign(:processing, false)}
    end
  end

  @impl true
  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :image, ref)}
  end

  @impl true
  def handle_event("add_to_canvas", _params, socket) do
    pixel_data = socket.assigns.pixel_data
    grid_size = socket.assigns.grid_size
    selected_canvas_id = socket.assigns.selected_canvas_id
    user = socket.assigns.current_user

    # Get or create canvas
    canvas_result = if selected_canvas_id == "new" do
      Canvases.create_canvas(user.id, "Pixel Art - #{grid_size}x#{grid_size}")
    else
      canvas_id = String.to_integer(selected_canvas_id)
      case Canvases.get_canvas_with_preloads(canvas_id, []) do
        nil -> {:error, :not_found}
        canvas -> {:ok, canvas}
      end
    end

    case canvas_result do
      {:ok, canvas} ->
        # Convert pixel data to rectangles for canvas rendering
        pixel_size = 8
        rectangles = Enum.map(pixel_data.pixels, fn pixel ->
          %{
            x: pixel.x * pixel_size,
            y: pixel.y * pixel_size,
            width: pixel_size,
            height: pixel_size,
            color: pixel.color
          }
        end)

        # Store pixel data server-side instead of passing through URL
        PixelDataStore.store(canvas.id, user.id, rectangles)

        {:noreply,
         socket
         |> put_flash(:info, "Animating pixel art on canvas...")
         |> push_navigate(to: ~p"/canvas/#{canvas.id}?animate_pixels=true")}

      {:error, reason} ->
        Logger.error("Failed to get/create canvas: #{inspect(reason)}")

        {:noreply,
         socket
         |> assign(:error, "Failed to add to canvas: #{format_error(reason)}")}
    end
  end

  # Private Functions

  defp create_default_user do
    # Create a default user if none exists
    {:ok, user} =
      Accounts.create_user(%{
        email: "pixelator@collabcanvas.com",
        name: "Pixel Art Creator"
      })

    user
  end

  @doc false
  defp process_image(image_path, grid_size) do
    try do
      # Step 1: Resize image to grid_size x grid_size using Mogrify
      resized_path = resize_image(image_path, grid_size)

      # Step 2: Extract pixel data using Image library
      pixel_data = extract_pixel_data(resized_path, grid_size)

      # Step 3: Clean up temporary resized file
      File.rm(resized_path)

      {:ok, pixel_data}
    rescue
      error ->
        Logger.error("Image processing error: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc false
  defp resize_image(image_path, grid_size) do
    output_path = "#{image_path}_resized.png"

    # Use Mogrify to resize the image
    image_path
    |> Mogrify.open()
    |> Mogrify.resize("#{grid_size}x#{grid_size}!")
    |> Mogrify.save(path: output_path)

    output_path
  end

  @doc false
  defp extract_pixel_data(image_path, grid_size) do
    # Use Image library to read the resized image and extract pixel data
    {:ok, image} = Image.open(image_path)

    # Convert image to pixel array
    pixels =
      for y <- 0..(grid_size - 1),
          x <- 0..(grid_size - 1) do
        # Extract pixel color at (x, y)
        {:ok, pixel} = Image.get_pixel(image, x, y)

        # Convert pixel to hex color
        hex_color = pixel_to_hex(pixel)

        %{x: x, y: y, color: hex_color}
      end

    %{
      pixels: pixels,
      width: grid_size,
      height: grid_size
    }
  end

  @doc false
  defp pixel_to_hex(pixel) when is_list(pixel) do
    # Handle list format [r, g, b] or [r, g, b, a]
    [r, g, b | _] = pixel
    "##{to_hex(r)}#{to_hex(g)}#{to_hex(b)}"
  end

  defp pixel_to_hex(pixel) when is_tuple(pixel) do
    # Handle tuple format {r, g, b} or {r, g, b, a}
    case pixel do
      {r, g, b, _a} -> "##{to_hex(r)}#{to_hex(g)}#{to_hex(b)}"
      {r, g, b} -> "##{to_hex(r)}#{to_hex(g)}#{to_hex(b)}"
    end
  end

  defp pixel_to_hex(pixel) when is_integer(pixel) do
    # Handle grayscale pixel
    "##{to_hex(pixel)}#{to_hex(pixel)}#{to_hex(pixel)}"
  end

  @doc false
  defp to_hex(value) when is_float(value) do
    # Convert float (0.0-1.0) to integer (0-255)
    value
    |> Kernel.*(255)
    |> round()
    |> to_hex()
  end

  defp to_hex(value) when is_integer(value) do
    value
    |> Integer.to_string(16)
    |> String.pad_leading(2, "0")
  end

  @doc false
  defp format_error(:too_large), do: "File is too large (max 10MB)"
  defp format_error(:not_accepted), do: "File type not accepted (JPG, JPEG, PNG only)"
  defp format_error(:too_many_files), do: "Only one file can be uploaded at a time"
  defp format_error(error) when is_binary(error), do: error
  defp format_error(error), do: "An error occurred: #{inspect(error)}"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50 py-8">
      <div class="max-w-4xl mx-auto px-4">
        <h1 class="text-3xl font-bold text-gray-900 mb-8">Image Pixelator</h1>

        <!-- Error Message -->
        <%= if @error do %>
          <div class="mb-4 p-4 bg-red-100 border border-red-400 text-red-700 rounded">
            <%= @error %>
          </div>
        <% end %>

        <!-- Upload Form -->
        <div class="bg-white rounded-lg shadow-md p-6 mb-6">
          <h2 class="text-xl font-semibold mb-4">Upload Image</h2>

          <form phx-change="validate" phx-submit="process_image">
            <!-- Grid Size Selector -->
            <div class="mb-4">
              <label for="grid_size" class="block text-sm font-medium text-gray-700 mb-2">
                Grid Size
              </label>
              <select
                id="grid_size"
                name="grid_size"
                phx-change="select_grid_size"
                class="block w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-blue-500 focus:border-blue-500"
              >
                <%= for {label, value} <- @grid_size_options do %>
                  <option value={value} selected={value == @grid_size}>
                    <%= label %>
                  </option>
                <% end %>
              </select>
            </div>

            <!-- Canvas Selector -->
            <div class="mb-4">
              <label for="canvas_id" class="block text-sm font-medium text-gray-700 mb-2">
                Target Canvas
              </label>
              <select
                id="canvas_id"
                name="canvas_id"
                phx-change="select_canvas"
                class="block w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-blue-500 focus:border-blue-500"
              >
                <%= for {label, value} <- @canvas_options do %>
                  <option value={value} selected={to_string(value) == @selected_canvas_id}>
                    <%= label %>
                  </option>
                <% end %>
              </select>
            </div>

            <!-- File Upload -->
            <div class="mb-4">
              <label class="block text-sm font-medium text-gray-700 mb-2">
                Select Image (JPG, PNG - Max 10MB)
              </label>
              <div
                class="border-2 border-dashed border-gray-300 rounded-lg p-6 text-center hover:border-gray-400 transition"
                phx-drop-target={@uploads.image.ref}
              >
                <.live_file_input upload={@uploads.image} class="hidden" />
                <label for={@uploads.image.ref} class="cursor-pointer">
                  <svg
                    class="mx-auto h-12 w-12 text-gray-400"
                    stroke="currentColor"
                    fill="none"
                    viewBox="0 0 48 48"
                  >
                    <path
                      d="M28 8H12a4 4 0 00-4 4v20m32-12v8m0 0v8a4 4 0 01-4 4H12a4 4 0 01-4-4v-4m32-4l-3.172-3.172a4 4 0 00-5.656 0L28 28M8 32l9.172-9.172a4 4 0 015.656 0L28 28m0 0l4 4m4-24h8m-4-4v8m-12 4h.02"
                      stroke-width="2"
                      stroke-linecap="round"
                      stroke-linejoin="round"
                    />
                  </svg>
                  <p class="mt-2 text-sm text-gray-600">
                    Click to upload or drag and drop
                  </p>
                </label>
              </div>

              <!-- Upload Progress -->
              <%= for entry <- @uploads.image.entries do %>
                <div class="mt-4">
                  <div class="flex items-center justify-between text-sm mb-1">
                    <span class="font-medium text-gray-700"><%= entry.client_name %></span>
                    <button
                      type="button"
                      phx-click="cancel_upload"
                      phx-value-ref={entry.ref}
                      class="text-red-600 hover:text-red-800"
                    >
                      Cancel
                    </button>
                  </div>
                  <div class="w-full bg-gray-200 rounded-full h-2">
                    <div
                      class="bg-blue-600 h-2 rounded-full transition-all"
                      style={"width: #{entry.progress}%"}
                    >
                    </div>
                  </div>
                  <!-- Upload Errors -->
                  <%= for err <- upload_errors(@uploads.image, entry) do %>
                    <p class="text-sm text-red-600 mt-1"><%= format_error(err) %></p>
                  <% end %>
                </div>
              <% end %>
            </div>

            <!-- Process Button -->
            <button
              type="submit"
              disabled={@processing || Enum.empty?(@uploads.image.entries)}
              class="w-full bg-blue-600 text-white py-2 px-4 rounded-md hover:bg-blue-700 disabled:bg-gray-400 disabled:cursor-not-allowed transition"
            >
              <%= if @processing, do: "Processing...", else: "Process Image" %>
            </button>
          </form>
        </div>

        <!-- Canvas Display -->
        <div class="bg-white rounded-lg shadow-md p-6">
          <h2 class="text-xl font-semibold mb-4">Pixelated Result</h2>
          <div class="flex justify-center">
            <canvas
              id="pixel-canvas"
              width="512"
              height="512"
              phx-hook="PixelCanvas"
              class="border border-gray-300 rounded"
            >
            </canvas>
          </div>

          <%= if @pixel_data do %>
            <div class="mt-6 flex justify-center">
              <button
                phx-click="add_to_canvas"
                class="bg-green-600 text-white px-6 py-3 rounded-md hover:bg-green-700 transition font-semibold"
              >
                Add to Canvas
              </button>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
