defmodule CollabCanvasWeb.Components.ColorPicker do
  @moduledoc """
  LiveComponent for color picking with HSL sliders, hex input, and color history.

  Features:
  - HSL sliders for intuitive color selection
  - Hex color input
  - Recent colors (last 8 used)
  - Favorite colors (pinned)
  - Default color setting
  """

  use CollabCanvasWeb, :live_component
  alias CollabCanvas.ColorPalettes

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:hue, 0)
     |> assign(:saturation, 100)
     |> assign(:lightness, 50)
     |> assign(:hex_color, "#FF0000")
     |> assign(:recent_colors, [])
     |> assign(:favorite_colors, [])
     |> assign(:default_color, "#000000")
     |> assign(:palettes, [])
     |> assign(:show_new_palette_form, false)
     |> assign(:new_palette_name, "")
     |> assign(:editing_palette_id, nil)
     |> assign(:save_timer, nil)}
  end

  @impl true
  def update(%{user_id: user_id} = assigns, socket) do
    # Load user's color preferences
    preferences = ColorPalettes.get_or_create_preferences(user_id)
    recent_colors = ColorPalettes.get_recent_colors(user_id)
    favorite_colors = ColorPalettes.get_favorite_colors(user_id)
    palettes = ColorPalettes.list_user_palettes(user_id)

    # Parse current color from hex to HSL if provided
    {h, s, l} = (assigns[:current_color] && hex_to_hsl(assigns[:current_color])) || {0, 100, 50}

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:hue, h)
     |> assign(:saturation, s)
     |> assign(:lightness, l)
     |> assign(:hex_color, assigns[:current_color] || preferences.default_color)
     |> assign(:recent_colors, recent_colors)
     |> assign(:favorite_colors, favorite_colors)
     |> assign(:palettes, palettes)
     |> assign(:default_color, preferences.default_color)}
  end

  @impl true
  def update(%{current_color: color} = assigns, socket) when is_binary(color) do
    # Update only the color (called via send_update from parent LiveView)
    # Don't reload user preferences, just update the color display
    {h, s, l} = hex_to_hsl(color)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:hue, h)
     |> assign(:saturation, s)
     |> assign(:lightness, l)
     |> assign(:hex_color, color)}
  end

  @impl true
  def handle_event("hue_changed", %{"value" => hue_str}, socket) do
    hue = String.to_integer(hue_str)
    hex_color = hsl_to_hex(hue, socket.assigns.saturation, socket.assigns.lightness)

    # Send to parent immediately for UI updates
    send(self(), {:color_changed, hex_color, "user_#{socket.assigns.user_id}"})

    # Schedule debounced database save
    socket = schedule_save(socket, hex_color)

    {:noreply, socket |> assign(:hue, hue) |> assign(:hex_color, hex_color)}
  end

  @impl true
  def handle_event("saturation_changed", %{"value" => sat_str}, socket) do
    saturation = String.to_integer(sat_str)
    hex_color = hsl_to_hex(socket.assigns.hue, saturation, socket.assigns.lightness)

    # Send to parent immediately for UI updates
    send(self(), {:color_changed, hex_color, "user_#{socket.assigns.user_id}"})

    # Schedule debounced database save
    socket = schedule_save(socket, hex_color)

    {:noreply, socket |> assign(:saturation, saturation) |> assign(:hex_color, hex_color)}
  end

  @impl true
  def handle_event("lightness_changed", %{"value" => light_str}, socket) do
    lightness = String.to_integer(light_str)
    hex_color = hsl_to_hex(socket.assigns.hue, socket.assigns.saturation, lightness)

    # Send to parent immediately for UI updates
    send(self(), {:color_changed, hex_color, "user_#{socket.assigns.user_id}"})

    # Schedule debounced database save
    socket = schedule_save(socket, hex_color)

    {:noreply, socket |> assign(:lightness, lightness) |> assign(:hex_color, hex_color)}
  end

  @impl true
  def handle_event("hex_input", %{"color" => hex_color}, socket) do
    # Validate and normalize hex color
    normalized = normalize_hex(hex_color)

    case valid_hex?(normalized) do
      true ->
        {h, s, l} = hex_to_hsl(normalized)
        # Send to parent immediately for UI updates
        send(self(), {:color_changed, normalized, "user_#{socket.assigns.user_id}"})

        # Schedule debounced database save
        socket = schedule_save(socket, normalized)

        {:noreply,
         socket
         |> assign(:hex_color, normalized)
         |> assign(:hue, h)
         |> assign(:saturation, s)
         |> assign(:lightness, l)}

      false ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("select_color", %{"color" => color}, socket) do
    require Logger

    try do
      Logger.info(
        "select_color event - user_id: #{inspect(socket.assigns.user_id)}, color: #{color}"
      )

      {h, s, l} = hex_to_hsl(color)

      # Save immediately for deliberate color selection (not slider dragging)
      result = ColorPalettes.set_default_color(socket.assigns.user_id, color)
      Logger.info("set_default_color result: #{inspect(result)}")

      send(self(), {:color_changed, color, "user_#{socket.assigns.user_id}"})

      {:noreply,
       socket
       |> assign(:hex_color, color)
       |> assign(:hue, h)
       |> assign(:saturation, s)
       |> assign(:lightness, l)
       |> assign(:default_color, color)}
    rescue
      e ->
        Logger.error("Error in select_color: #{inspect(e)}")
        Logger.error("Stacktrace: #{inspect(__STACKTRACE__)}")
        Logger.error("Socket assigns: #{inspect(socket.assigns)}")
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("add_to_favorites", _params, socket) do
    case ColorPalettes.add_favorite_color(socket.assigns.user_id, socket.assigns.hex_color) do
      {:ok, _} ->
        favorite_colors = ColorPalettes.get_favorite_colors(socket.assigns.user_id)
        {:noreply, assign(socket, :favorite_colors, favorite_colors)}

      {:error, :max_favorites_reached} ->
        # Send error message to parent LiveView
        send(self(), {:show_error, "Maximum of 20 favorite colors reached"})
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("remove_from_favorites", %{"color" => color}, socket) do
    {:ok, _} = ColorPalettes.remove_favorite_color(socket.assigns.user_id, color)
    favorite_colors = ColorPalettes.get_favorite_colors(socket.assigns.user_id)

    {:noreply, assign(socket, :favorite_colors, favorite_colors)}
  end

  @impl true
  def handle_event(
        "picker_square_changed",
        %{"saturation" => sat_str, "lightness" => light_str},
        socket
      ) do
    saturation = parse_number(sat_str)
    lightness = parse_number(light_str)

    hex_color = hsl_to_hex(socket.assigns.hue, saturation, lightness)

    # Send to parent immediately for UI updates
    send(self(), {:color_changed, hex_color, "user_#{socket.assigns.user_id}"})

    # Schedule debounced database save
    socket = schedule_save(socket, hex_color)

    {:noreply,
     socket
     |> assign(:saturation, saturation)
     |> assign(:lightness, lightness)
     |> assign(:hex_color, hex_color)}
  end

  @impl true
  def handle_event("toggle_new_palette_form", _params, socket) do
    {:noreply, assign(socket, :show_new_palette_form, !socket.assigns.show_new_palette_form)}
  end

  @impl true
  def handle_event("create_palette", %{"name" => name}, socket) do
    case ColorPalettes.create_palette(socket.assigns.user_id, name) do
      {:ok, _palette} ->
        palettes = ColorPalettes.list_user_palettes(socket.assigns.user_id)

        {:noreply,
         socket
         |> assign(:palettes, palettes)
         |> assign(:show_new_palette_form, false)
         |> assign(:new_palette_name, "")}

      {:error, _} ->
        send(self(), {:show_error, "Failed to create palette"})
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("add_color_to_palette", %{"palette-id" => palette_id}, socket) do
    case ColorPalettes.add_color_to_palette(palette_id, socket.assigns.hex_color) do
      {:ok, _} ->
        palettes = ColorPalettes.list_user_palettes(socket.assigns.user_id)
        {:noreply, assign(socket, :palettes, palettes)}

      {:error, _} ->
        send(self(), {:show_error, "Failed to add color to palette"})
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("delete_palette", %{"palette-id" => palette_id}, socket) do
    case ColorPalettes.delete_palette(palette_id) do
      {:ok, _} ->
        palettes = ColorPalettes.list_user_palettes(socket.assigns.user_id)
        {:noreply, assign(socket, :palettes, palettes)}

      {:error, _} ->
        send(self(), {:show_error, "Failed to delete palette"})
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("remove_color_from_palette", %{"color-id" => color_id}, socket) do
    case ColorPalettes.remove_color_from_palette(color_id) do
      {:ok, _} ->
        palettes = ColorPalettes.list_user_palettes(socket.assigns.user_id)
        {:noreply, assign(socket, :palettes, palettes)}

      {:error, _} ->
        send(self(), {:show_error, "Failed to remove color"})
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("start_edit_palette", %{"palette-id" => palette_id}, socket) do
    {:noreply, assign(socket, :editing_palette_id, palette_id)}
  end

  @impl true
  def handle_event("cancel_edit_palette", _params, socket) do
    {:noreply, assign(socket, :editing_palette_id, nil)}
  end

  @impl true
  def handle_event("rename_palette", %{"palette-id" => palette_id, "name" => name}, socket) do
    case ColorPalettes.update_palette(palette_id, name) do
      {:ok, _} ->
        palettes = ColorPalettes.list_user_palettes(socket.assigns.user_id)
        {:noreply, socket |> assign(:palettes, palettes) |> assign(:editing_palette_id, nil)}

      {:error, _} ->
        send(self(), {:show_error, "Failed to rename palette"})
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:save_default_color, color}, socket) do
    # Save to database after debounce delay
    ColorPalettes.set_default_color(socket.assigns.user_id, color)
    {:noreply, socket |> assign(:save_timer, nil) |> assign(:default_color, color)}
  end

  # Helper function to schedule debounced save
  defp schedule_save(socket, color) do
    # Cancel existing timer if any
    if socket.assigns.save_timer do
      Process.cancel_timer(socket.assigns.save_timer)
    end

    # Schedule new save after 500ms
    timer_ref = Process.send_after(self(), {:save_default_color, color}, 500)

    assign(socket, :save_timer, timer_ref)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      class="color-picker bg-white rounded-lg shadow-lg p-4 w-80"
      phx-hook="ColorPicker"
      id="color-picker-hook"
    >
      <div class="mb-4">
        <div class="text-sm font-medium text-gray-700 mb-2">Current Color</div>
        <div class="flex items-center gap-3">
          <div
            class="w-16 h-16 rounded border-2 border-gray-300"
            style={"background-color: #{@hex_color}"}
          >
          </div>
          <form phx-change="hex_input" phx-target={@myself} class="flex-1">
            <input
              type="text"
              name="color"
              value={@hex_color}
              phx-debounce="300"
              class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 font-mono text-sm"
              placeholder="#RRGGBB"
            />
          </form>
        </div>
      </div>
      
    <!-- 2D Color Picker -->
      <div class="mb-4">
        <!-- Saturation/Lightness Square -->
        <div
          id="color-picker-square"
          data-hue={@hue}
          data-saturation={@saturation}
          data-lightness={@lightness}
          class="relative w-full h-48 rounded cursor-crosshair mb-3 border-2 border-gray-300"
          style={"background: linear-gradient(to bottom, transparent, black), linear-gradient(to right, white, #{hsl_to_hex(@hue, 100, 50)})"}
        >
          <!-- Color picker indicator (white circle with border) -->
          <div
            id="color-picker-indicator"
            class="absolute w-4 h-4 border-2 border-white rounded-full pointer-events-none shadow-lg"
            style={"left: #{@saturation}%; top: #{100 - @lightness}%; transform: translate(-50%, -50%)"}
          >
          </div>
        </div>
        
    <!-- Hue Slider -->
        <div>
          <label class="text-xs font-medium text-gray-600 mb-1 block">Hue: {@hue}°</label>
          <form phx-change="hue_changed" phx-target={@myself}>
            <input
              type="range"
              name="value"
              min="0"
              max="360"
              value={@hue}
              class="w-full h-3 rounded-lg appearance-none cursor-pointer"
              style="background: linear-gradient(to right, #FF0000 0%, #FFFF00 16.67%, #00FF00 33.33%, #00FFFF 50%, #0000FF 66.67%, #FF00FF 83.33%, #FF0000 100%)"
            />
          </form>
        </div>
      </div>
      
    <!-- Action Buttons -->
      <div class="mb-4">
        <button
          phx-click="add_to_favorites"
          phx-target={@myself}
          class="w-full px-3 py-2 text-xs font-medium text-white bg-blue-500 hover:bg-blue-600 rounded transition"
        >
          ★ Add to Favorites
        </button>
      </div>
      
    <!-- Recent Colors -->
      <%= if length(@recent_colors) > 0 do %>
        <div class="mb-4">
          <div class="text-xs font-medium text-gray-600 mb-2">Recent Colors</div>
          <div class="flex flex-wrap gap-2">
            <%= for color <- @recent_colors do %>
              <button
                phx-click="select_color"
                phx-value-color={color}
                phx-target={@myself}
                class="w-8 h-8 rounded border-2 border-gray-300 hover:border-blue-500 transition cursor-pointer"
                style={"background-color: #{color}"}
                title={color}
              >
              </button>
            <% end %>
          </div>
        </div>
      <% end %>
      
    <!-- Favorite Colors -->
      <%= if length(@favorite_colors) > 0 do %>
        <div class="mb-4">
          <div class="text-xs font-medium text-gray-600 mb-2">Favorite Colors</div>
          <div class="flex flex-wrap gap-2">
            <%= for color <- @favorite_colors do %>
              <div class="relative group">
                <button
                  phx-click="select_color"
                  phx-value-color={color}
                  phx-target={@myself}
                  class="w-8 h-8 rounded border-2 border-gray-300 hover:border-blue-500 transition cursor-pointer"
                  style={"background-color: #{color}"}
                  title={color}
                >
                </button>
                <button
                  phx-click="remove_from_favorites"
                  phx-value-color={color}
                  phx-target={@myself}
                  class="absolute -top-1 -right-1 w-4 h-4 bg-red-500 text-white rounded-full text-xs opacity-0 group-hover:opacity-100 transition"
                >
                  ×
                </button>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>
      
    <!-- Color Palettes -->
      <div class="border-t border-gray-200 pt-4">
        <div class="flex items-center justify-between mb-2">
          <div class="text-xs font-medium text-gray-600">Color Palettes</div>
          <button
            phx-click="toggle_new_palette_form"
            phx-target={@myself}
            class="text-xs px-2 py-1 bg-green-500 text-white rounded hover:bg-green-600 transition"
          >
            + New
          </button>
        </div>
        
    <!-- New Palette Form -->
        <%= if @show_new_palette_form do %>
          <div class="mb-3 p-2 bg-gray-50 rounded border border-gray-200">
            <form phx-submit="create_palette" phx-target={@myself}>
              <div class="flex gap-2">
                <input
                  type="text"
                  name="name"
                  value=""
                  placeholder="Palette name"
                  class="flex-1 px-2 py-1 text-xs border border-gray-300 rounded focus:outline-none focus:ring-1 focus:ring-blue-500"
                  required
                />
                <button
                  type="submit"
                  class="px-3 py-1 text-xs bg-blue-500 text-white rounded hover:bg-blue-600"
                >
                  Create
                </button>
                <button
                  type="button"
                  phx-click="toggle_new_palette_form"
                  phx-target={@myself}
                  class="px-2 py-1 text-xs bg-gray-300 text-gray-700 rounded hover:bg-gray-400"
                >
                  Cancel
                </button>
              </div>
            </form>
          </div>
        <% end %>
        
    <!-- Palettes List -->
        <%= if length(@palettes) == 0 && !@show_new_palette_form do %>
          <div class="text-xs text-gray-400 italic py-2">
            No palettes yet. Create one to get started!
          </div>
        <% end %>

        <%= for palette <- @palettes do %>
          <div class="mb-3 p-2 bg-gray-50 rounded border border-gray-200">
            <!-- Palette Header -->
            <div class="flex items-center justify-between mb-2">
              <%= if @editing_palette_id == palette.id do %>
                <form phx-submit="rename_palette" phx-target={@myself} class="flex-1 flex gap-1">
                  <input type="hidden" name="palette-id" value={palette.id} />
                  <input
                    type="text"
                    name="name"
                    value={palette.name}
                    class="flex-1 px-2 py-1 text-xs border border-gray-300 rounded focus:outline-none focus:ring-1 focus:ring-blue-500"
                    required
                  />
                  <button
                    type="submit"
                    class="px-2 py-1 text-xs bg-blue-500 text-white rounded hover:bg-blue-600"
                  >
                    Save
                  </button>
                  <button
                    type="button"
                    phx-click="cancel_edit_palette"
                    phx-target={@myself}
                    class="px-2 py-1 text-xs bg-gray-300 text-gray-700 rounded hover:bg-gray-400"
                  >
                    Cancel
                  </button>
                </form>
              <% else %>
                <div class="text-xs font-medium text-gray-700">{palette.name}</div>
                <div class="flex gap-1">
                  <button
                    phx-click="add_color_to_palette"
                    phx-value-palette-id={palette.id}
                    phx-target={@myself}
                    class="px-2 py-1 text-xs bg-blue-500 text-white rounded hover:bg-blue-600 transition"
                    title="Add current color to this palette"
                  >
                    +
                  </button>
                  <button
                    phx-click="start_edit_palette"
                    phx-value-palette-id={palette.id}
                    phx-target={@myself}
                    class="px-2 py-1 text-xs bg-gray-300 text-gray-700 rounded hover:bg-gray-400 transition"
                    title="Rename palette"
                  >
                    ✎
                  </button>
                  <button
                    phx-click="delete_palette"
                    phx-value-palette-id={palette.id}
                    phx-target={@myself}
                    class="px-2 py-1 text-xs bg-red-500 text-white rounded hover:bg-red-600 transition"
                    title="Delete palette"
                    data-confirm="Are you sure you want to delete this palette?"
                  >
                    🗑
                  </button>
                </div>
              <% end %>
            </div>
            
    <!-- Palette Colors -->
            <%= if length(palette.colors) > 0 do %>
              <div class="flex flex-wrap gap-1">
                <%= for color <- Enum.sort_by(palette.colors, & &1.position) do %>
                  <div class="relative group">
                    <button
                      phx-click="select_color"
                      phx-value-color={color.color_hex}
                      phx-target={@myself}
                      class="w-6 h-6 rounded border border-gray-300 hover:border-blue-500 transition cursor-pointer"
                      style={"background-color: #{color.color_hex}"}
                      title={color.color_hex}
                    >
                    </button>
                    <button
                      phx-click="remove_color_from_palette"
                      phx-value-color-id={color.id}
                      phx-target={@myself}
                      class="absolute -top-1 -right-1 w-3 h-3 bg-red-500 text-white rounded-full text-xs opacity-0 group-hover:opacity-100 transition flex items-center justify-center"
                      style="font-size: 8px; line-height: 1;"
                    >
                      ×
                    </button>
                  </div>
                <% end %>
              </div>
            <% else %>
              <div class="text-xs text-gray-400 italic">Empty palette</div>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Helper function to parse number strings that may be integers or floats
  defp parse_number(str) when is_binary(str) do
    case Float.parse(str) do
      {num, _} -> round(num)
      :error -> 0
    end
  end

  defp parse_number(num) when is_number(num), do: round(num)
  defp parse_number(_), do: 0

  # Color conversion helpers

  defp hex_to_hsl("#" <> hex) do
    hex_to_hsl(hex)
  end

  defp hex_to_hsl(hex) when byte_size(hex) == 6 do
    {r, _} = hex |> String.slice(0, 2) |> Integer.parse(16)
    {g, _} = hex |> String.slice(2, 2) |> Integer.parse(16)
    {b, _} = hex |> String.slice(4, 2) |> Integer.parse(16)

    rgb_to_hsl(r / 255, g / 255, b / 255)
  end

  defp hex_to_hsl(_), do: {0, 100, 50}

  defp rgb_to_hsl(r, g, b) do
    max_val = Enum.max([r, g, b])
    min_val = Enum.min([r, g, b])
    delta = max_val - min_val

    # Lightness
    l = (max_val + min_val) / 2

    # Saturation
    s =
      if delta == 0 do
        0
      else
        delta / (1 - abs(2 * l - 1))
      end

    # Hue
    h =
      if delta == 0 do
        0
      else
        cond do
          max_val == r ->
            h_temp = (g - b) / delta
            h_temp = if g < b, do: h_temp + 6, else: h_temp
            60 * h_temp

          max_val == g ->
            60 * ((b - r) / delta + 2)

          max_val == b ->
            60 * ((r - g) / delta + 4)
        end
      end

    h = rem(round(h), 360)
    h = if h < 0, do: h + 360, else: h

    {h, round(s * 100), round(l * 100)}
  end

  defp hsl_to_hex(h, s, l) do
    hsl_to_rgb(h, s / 100, l / 100)
    |> rgb_to_hex()
  end

  defp hsl_to_rgb(h, s, l) do
    # Standard HSL to RGB conversion algorithm
    c = (1 - abs(2 * l - 1)) * s
    h_normalized = h / 60
    x = c * (1 - abs(:math.fmod(h_normalized, 2) - 1))
    m = l - c / 2

    {r1, g1, b1} =
      case trunc(h_normalized) do
        0 -> {c, x, 0}
        1 -> {x, c, 0}
        2 -> {0, c, x}
        3 -> {0, x, c}
        4 -> {x, 0, c}
        5 -> {c, 0, x}
        # Handle 360 degrees
        6 -> {c, 0, 0}
        _ -> {0, 0, 0}
      end

    r = round((r1 + m) * 255)
    g = round((g1 + m) * 255)
    b = round((b1 + m) * 255)

    # Clamp values to 0-255
    r = max(0, min(255, r))
    g = max(0, min(255, g))
    b = max(0, min(255, b))

    {r, g, b}
  end

  defp rgb_to_hex({r, g, b}) do
    ("#" <>
       (r |> Integer.to_string(16) |> String.pad_leading(2, "0")) <>
       (g |> Integer.to_string(16) |> String.pad_leading(2, "0")) <>
       (b |> Integer.to_string(16) |> String.pad_leading(2, "0")))
    |> String.upcase()
  end

  defp normalize_hex("#" <> hex), do: "#" <> String.upcase(hex)
  defp normalize_hex(hex), do: "#" <> String.upcase(hex)

  defp valid_hex?("#" <> hex) when byte_size(hex) == 6 do
    String.match?(hex, ~r/^[0-9A-F]{6}$/i)
  end

  defp valid_hex?(_), do: false
end
