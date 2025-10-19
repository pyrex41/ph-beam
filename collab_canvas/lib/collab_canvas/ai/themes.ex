defmodule CollabCanvas.AI.Themes do
  @moduledoc """
  Provides color themes for UI components.

  Supports multiple themes including light, dark, blue, and green color schemes.
  Each theme provides colors for backgrounds, text, buttons, and other UI elements.
  """

  @doc """
  Returns a color scheme map for the specified theme.

  ## Parameters
    * `theme` - Theme name ("light", "dark", "blue", or "green")

  ## Returns
    * Map with color values in hex format

  ## Examples

      iex> get_theme_colors("dark")
      %{bg: "#1f2937", text_primary: "#f9fafb", ...}

      iex> get_theme_colors("light")
      %{bg: "#ffffff", text_primary: "#111827", ...}
  """
  def get_theme_colors(theme) do
    case theme do
      "dark" ->
        %{
          bg: "#1f2937",
          border: "#374151",
          text_primary: "#f9fafb",
          text_secondary: "#d1d5db",
          input_bg: "#374151",
          input_border: "#4b5563",
          button_bg: "#3b82f6",
          button_border: "#2563eb",
          button_text: "#ffffff",
          navbar_bg: "#111827",
          card_bg: "#1f2937",
          card_header_bg: "#374151",
          card_footer_bg: "#374151",
          shadow: "#00000066",
          sidebar_bg: "#1f2937",
          sidebar_item_bg: "#374151",
          sidebar_item_border: "#4b5563"
        }

      "blue" ->
        %{
          bg: "#eff6ff",
          border: "#93c5fd",
          text_primary: "#1e3a8a",
          text_secondary: "#3b82f6",
          input_bg: "#ffffff",
          input_border: "#93c5fd",
          button_bg: "#3b82f6",
          button_border: "#2563eb",
          button_text: "#ffffff",
          navbar_bg: "#3b82f6",
          card_bg: "#ffffff",
          card_header_bg: "#dbeafe",
          card_footer_bg: "#f0f9ff",
          shadow: "#3b82f633",
          sidebar_bg: "#dbeafe",
          sidebar_item_bg: "#bfdbfe",
          sidebar_item_border: "#93c5fd"
        }

      "green" ->
        %{
          bg: "#f0fdf4",
          border: "#86efac",
          text_primary: "#14532d",
          text_secondary: "#16a34a",
          input_bg: "#ffffff",
          input_border: "#86efac",
          button_bg: "#22c55e",
          button_border: "#16a34a",
          button_text: "#ffffff",
          navbar_bg: "#22c55e",
          card_bg: "#ffffff",
          card_header_bg: "#dcfce7",
          card_footer_bg: "#f0fdf4",
          shadow: "#22c55e33",
          sidebar_bg: "#dcfce7",
          sidebar_item_bg: "#bbf7d0",
          sidebar_item_border: "#86efac"
        }

      # "light" or default
      _ ->
        %{
          bg: "#ffffff",
          border: "#e5e7eb",
          text_primary: "#111827",
          text_secondary: "#6b7280",
          input_bg: "#ffffff",
          input_border: "#d1d5db",
          button_bg: "#3b82f6",
          button_border: "#2563eb",
          button_text: "#ffffff",
          navbar_bg: "#f9fafb",
          card_bg: "#ffffff",
          card_header_bg: "#f9fafb",
          card_footer_bg: "#f9fafb",
          shadow: "#00000026",
          sidebar_bg: "#f9fafb",
          sidebar_item_bg: "#ffffff",
          sidebar_item_border: "#e5e7eb"
        }
    end
  end
end
