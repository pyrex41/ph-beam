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
     |> assign(:default_color, "#000000")}
  end

  @impl true
  def update(%{user_id: user_id} = assigns, socket) do
    # Load user's color preferences
    preferences = ColorPalettes.get_or_create_preferences(user_id)
    recent_colors = ColorPalettes.get_recent_colors(user_id)
    favorite_colors = ColorPalettes.get_favorite_colors(user_id)

    # Parse current color from hex to HSL if provided
    {h, s, l} = assigns[:current_color] && hex_to_hsl(assigns[:current_color]) || {0, 100, 50}

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:hue, h)
     |> assign(:saturation, s)
     |> assign(:lightness, l)
     |> assign(:hex_color, assigns[:current_color] || preferences.default_color)
     |> assign(:recent_colors, recent_colors)
     |> assign(:favorite_colors, favorite_colors)
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

    # Auto-save as default color
    ColorPalettes.set_default_color(socket.assigns.user_id, hex_color)
    # Send to parent with user_id in correct format
    send(self(), {:color_changed, hex_color, "user_#{socket.assigns.user_id}"})

    {:noreply, socket |> assign(:hue, hue) |> assign(:hex_color, hex_color) |> assign(:default_color, hex_color)}
  end

  @impl true
  def handle_event("saturation_changed", %{"value" => sat_str}, socket) do
    saturation = String.to_integer(sat_str)
    hex_color = hsl_to_hex(socket.assigns.hue, saturation, socket.assigns.lightness)

    # Auto-save as default color
    ColorPalettes.set_default_color(socket.assigns.user_id, hex_color)
    send(self(), {:color_changed, hex_color, "user_#{socket.assigns.user_id}"})

    {:noreply, socket |> assign(:saturation, saturation) |> assign(:hex_color, hex_color) |> assign(:default_color, hex_color)}
  end

  @impl true
  def handle_event("lightness_changed", %{"value" => light_str}, socket) do
    lightness = String.to_integer(light_str)
    hex_color = hsl_to_hex(socket.assigns.hue, socket.assigns.saturation, lightness)

    # Auto-save as default color
    ColorPalettes.set_default_color(socket.assigns.user_id, hex_color)
    send(self(), {:color_changed, hex_color, "user_#{socket.assigns.user_id}"})

    {:noreply, socket |> assign(:lightness, lightness) |> assign(:hex_color, hex_color) |> assign(:default_color, hex_color)}
  end

  @impl true
  def handle_event("hex_input", %{"color" => hex_color}, socket) do
    # Validate and normalize hex color
    normalized = normalize_hex(hex_color)

    case valid_hex?(normalized) do
      true ->
        {h, s, l} = hex_to_hsl(normalized)
        # Auto-save as default color
        ColorPalettes.set_default_color(socket.assigns.user_id, normalized)
        send(self(), {:color_changed, normalized, "user_#{socket.assigns.user_id}"})

        {:noreply,
         socket
         |> assign(:hex_color, normalized)
         |> assign(:hue, h)
         |> assign(:saturation, s)
         |> assign(:lightness, l)
         |> assign(:default_color, normalized)}

      false ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("select_color", %{"color" => color}, socket) do
    {h, s, l} = hex_to_hsl(color)
    # Auto-save as default color
    ColorPalettes.set_default_color(socket.assigns.user_id, color)
    send(self(), {:color_changed, color, "user_#{socket.assigns.user_id}"})

    {:noreply,
     socket
     |> assign(:hex_color, color)
     |> assign(:hue, h)
     |> assign(:saturation, s)
     |> assign(:lightness, l)
     |> assign(:default_color, color)}
  end

  @impl true
  def handle_event("add_to_favorites", _params, socket) do
    {:ok, _} = ColorPalettes.add_favorite_color(socket.assigns.user_id, socket.assigns.hex_color)
    favorite_colors = ColorPalettes.get_favorite_colors(socket.assigns.user_id)

    {:noreply, assign(socket, :favorite_colors, favorite_colors)}
  end

  @impl true
  def handle_event("remove_from_favorites", %{"color" => color}, socket) do
    {:ok, _} = ColorPalettes.remove_favorite_color(socket.assigns.user_id, color)
    favorite_colors = ColorPalettes.get_favorite_colors(socket.assigns.user_id)

    {:noreply, assign(socket, :favorite_colors, favorite_colors)}
  end

  @impl true
  def handle_event("picker_square_changed", %{"saturation" => sat_str, "lightness" => light_str}, socket) do
    saturation = String.to_float(sat_str) |> round()
    lightness = String.to_float(light_str) |> round()

    hex_color = hsl_to_hex(socket.assigns.hue, saturation, lightness)

    # Auto-save as default color
    ColorPalettes.set_default_color(socket.assigns.user_id, hex_color)
    send(self(), {:color_changed, hex_color, "user_#{socket.assigns.user_id}"})

    {:noreply, socket |> assign(:saturation, saturation) |> assign(:lightness, lightness) |> assign(:hex_color, hex_color) |> assign(:default_color, hex_color)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="color-picker bg-white rounded-lg shadow-lg p-4 w-80" phx-hook="ColorPicker" id="color-picker-hook">
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
        <div class="mb-2">
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
    </div>
    """
  end

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
    s = if delta == 0 do
      0
    else
      delta / (1 - abs(2 * l - 1))
    end

    # Hue
    h = if delta == 0 do
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

    {r1, g1, b1} = case trunc(h_normalized) do
      0 -> {c, x, 0}
      1 -> {x, c, 0}
      2 -> {0, c, x}
      3 -> {0, x, c}
      4 -> {x, 0, c}
      5 -> {c, 0, x}
      6 -> {c, 0, 0}  # Handle 360 degrees
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
    "#" <>
      (r |> Integer.to_string(16) |> String.pad_leading(2, "0")) <>
      (g |> Integer.to_string(16) |> String.pad_leading(2, "0")) <>
      (b |> Integer.to_string(16) |> String.pad_leading(2, "0"))
    |> String.upcase()
  end

  defp normalize_hex("#" <> hex), do: "#" <> String.upcase(hex)
  defp normalize_hex(hex), do: "#" <> String.upcase(hex)

  defp valid_hex?("#" <> hex) when byte_size(hex) == 6 do
    String.match?(hex, ~r/^[0-9A-F]{6}$/i)
  end

  defp valid_hex?(_), do: false
end
