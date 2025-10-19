defmodule CollabCanvas.AI.ComponentBuilder do
  @moduledoc """
  Builds complex UI components for the AI agent.

  This module provides functions to create multi-element UI components like login forms,
  navbars, cards, button groups, and sidebars. Each component consists of multiple shapes
  and text elements that are created and positioned together.
  """

  alias CollabCanvas.Canvases
  alias CollabCanvas.AI.Themes

  @doc """
  Creates a login form component with username, password fields, and submit button.

  ## Parameters
    * `canvas_id` - The canvas to create the component on
    * `x`, `y` - Position coordinates
    * `width`, `height` - Component dimensions
    * `theme` - Color theme ("light", "dark", "blue", or "green")
    * `content` - Map with optional :title key

  ## Returns
    * `{:ok, %{component_type: "login_form", object_ids: [...]}}` on success
  """
  def create_login_form(canvas_id, x, y, width, height, theme, content) do
    colors = Themes.get_theme_colors(theme)
    title = Map.get(content, "title", "Login")

    created_objects = []

    # Create background container
    {:ok, bg} =
      create_shape_for_component(
        canvas_id,
        "rectangle",
        x,
        y,
        width,
        height,
        colors.bg,
        colors.border,
        2
      )

    created_objects = [bg.id | created_objects]

    # Create title text
    {:ok, title_text} =
      create_text_for_component(
        canvas_id,
        title,
        x + width / 2,
        y + 20,
        24,
        "Arial",
        colors.text_primary,
        "center"
      )

    created_objects = [title_text.id | created_objects]

    # Username label
    {:ok, username_label} =
      create_text_for_component(
        canvas_id,
        "Username:",
        x + 20,
        y + 60,
        14,
        "Arial",
        colors.text_secondary,
        "left"
      )

    created_objects = [username_label.id | created_objects]

    # Username input box
    {:ok, username_input} =
      create_shape_for_component(
        canvas_id,
        "rectangle",
        x + 20,
        y + 80,
        width - 40,
        40,
        colors.input_bg,
        colors.input_border,
        1
      )

    created_objects = [username_input.id | created_objects]

    # Password label
    {:ok, password_label} =
      create_text_for_component(
        canvas_id,
        "Password:",
        x + 20,
        y + 130,
        14,
        "Arial",
        colors.text_secondary,
        "left"
      )

    created_objects = [password_label.id | created_objects]

    # Password input box
    {:ok, password_input} =
      create_shape_for_component(
        canvas_id,
        "rectangle",
        x + 20,
        y + 150,
        width - 40,
        40,
        colors.input_bg,
        colors.input_border,
        1
      )

    created_objects = [password_input.id | created_objects]

    # Submit button
    {:ok, submit_btn} =
      create_shape_for_component(
        canvas_id,
        "rectangle",
        x + 20,
        y + 210,
        width - 40,
        45,
        colors.button_bg,
        colors.button_border,
        0
      )

    created_objects = [submit_btn.id | created_objects]

    # Button text
    {:ok, btn_text} =
      create_text_for_component(
        canvas_id,
        "Sign In",
        x + width / 2,
        y + 225,
        16,
        "Arial",
        colors.button_text,
        "center"
      )

    created_objects = [btn_text.id | created_objects]

    {:ok, %{component_type: "login_form", object_ids: Enum.reverse(created_objects)}}
  end

  @doc """
  Creates a navigation bar component with logo and menu items.

  ## Parameters
    * `canvas_id` - The canvas to create the component on
    * `x`, `y` - Position coordinates
    * `width`, `height` - Component dimensions
    * `theme` - Color theme
    * `content` - Map with optional :title and :items keys

  ## Returns
    * `{:ok, %{component_type: "navbar", object_ids: [...]}}` on success
  """
  def create_navbar(canvas_id, x, y, width, height, theme, content) do
    colors = Themes.get_theme_colors(theme)
    items = Map.get(content, "items", ["Home", "About", "Services", "Contact"])
    title = Map.get(content, "title", "Brand")

    created_objects = []

    # Create navbar background
    {:ok, bg} =
      create_shape_for_component(
        canvas_id,
        "rectangle",
        x,
        y,
        width,
        height,
        colors.navbar_bg,
        colors.border,
        0
      )

    created_objects = [bg.id | created_objects]

    # Create logo/brand text
    {:ok, logo} =
      create_text_for_component(
        canvas_id,
        title,
        x + 20,
        y + height / 2 - 10,
        20,
        "Arial",
        colors.text_primary,
        "left"
      )

    created_objects = [logo.id | created_objects]

    # Calculate spacing for menu items
    item_count = length(items)
    available_width = width - 200
    item_spacing = if item_count > 1, do: available_width / (item_count - 1), else: 0

    # Create menu items
    created_objects =
      items
      |> Enum.with_index()
      |> Enum.reduce(created_objects, fn {item, index}, acc ->
        item_x = x + 200 + index * item_spacing

        {:ok, menu_item} =
          create_text_for_component(
            canvas_id,
            item,
            item_x,
            y + height / 2 - 8,
            16,
            "Arial",
            colors.text_secondary,
            "center"
          )

        [menu_item.id | acc]
      end)

    {:ok, %{component_type: "navbar", object_ids: Enum.reverse(created_objects)}}
  end

  @doc """
  Creates a card component with header, content, and footer sections.

  ## Parameters
    * `canvas_id` - The canvas to create the component on
    * `x`, `y` - Position coordinates
    * `width`, `height` - Component dimensions
    * `theme` - Color theme
    * `content` - Map with optional :title and :subtitle keys

  ## Returns
    * `{:ok, %{component_type: "card", object_ids: [...]}}` on success
  """
  def create_card(canvas_id, x, y, width, height, theme, content) do
    colors = Themes.get_theme_colors(theme)
    title = Map.get(content, "title", "Card Title")
    subtitle = Map.get(content, "subtitle", "Card description goes here")

    created_objects = []

    # Create shadow effect (slightly offset darker rectangle)
    {:ok, shadow} =
      create_shape_for_component(
        canvas_id,
        "rectangle",
        x + 4,
        y + 4,
        width,
        height,
        colors.shadow,
        colors.shadow,
        0
      )

    created_objects = [shadow.id | created_objects]

    # Create card background
    {:ok, bg} =
      create_shape_for_component(
        canvas_id,
        "rectangle",
        x,
        y,
        width,
        height,
        colors.card_bg,
        colors.border,
        1
      )

    created_objects = [bg.id | created_objects]

    # Create header section
    {:ok, header} =
      create_shape_for_component(
        canvas_id,
        "rectangle",
        x,
        y,
        width,
        60,
        colors.card_header_bg,
        colors.border,
        0
      )

    created_objects = [header.id | created_objects]

    # Create title text
    {:ok, title_text} =
      create_text_for_component(
        canvas_id,
        title,
        x + 20,
        y + 20,
        18,
        "Arial",
        colors.text_primary,
        "left"
      )

    created_objects = [title_text.id | created_objects]

    # Create content area text
    {:ok, content_text} =
      create_text_for_component(
        canvas_id,
        subtitle,
        x + 20,
        y + 80,
        14,
        "Arial",
        colors.text_secondary,
        "left"
      )

    created_objects = [content_text.id | created_objects]

    # Create footer section
    footer_y = y + height - 50

    {:ok, footer} =
      create_shape_for_component(
        canvas_id,
        "rectangle",
        x,
        footer_y,
        width,
        50,
        colors.card_footer_bg,
        colors.border,
        0
      )

    created_objects = [footer.id | created_objects]

    {:ok, %{component_type: "card", object_ids: Enum.reverse(created_objects)}}
  end

  @doc """
  Creates a button group component with multiple buttons side by side.

  ## Parameters
    * `canvas_id` - The canvas to create the component on
    * `x`, `y` - Position coordinates
    * `width`, `height` - Component dimensions
    * `theme` - Color theme
    * `content` - Map with optional :items key (array of button labels)

  ## Returns
    * `{:ok, %{component_type: "button_group", object_ids: [...]}}` on success
  """
  def create_button_group(canvas_id, x, y, width, height, theme, content) do
    colors = Themes.get_theme_colors(theme)
    items = Map.get(content, "items", ["Button 1", "Button 2", "Button 3"])

    created_objects = []
    button_width = (width - 20 * (length(items) - 1)) / length(items)

    created_objects =
      items
      |> Enum.with_index()
      |> Enum.reduce(created_objects, fn {label, index}, acc ->
        btn_x = x + index * (button_width + 20)

        # Button background
        {:ok, btn} =
          create_shape_for_component(
            canvas_id,
            "rectangle",
            btn_x,
            y,
            button_width,
            height,
            colors.button_bg,
            colors.button_border,
            1
          )

        acc = [btn.id | acc]

        # Button text
        {:ok, btn_text} =
          create_text_for_component(
            canvas_id,
            label,
            btn_x + button_width / 2,
            y + height / 2 - 8,
            14,
            "Arial",
            colors.button_text,
            "center"
          )

        [btn_text.id | acc]
      end)

    {:ok, %{component_type: "button_group", object_ids: Enum.reverse(created_objects)}}
  end

  @doc """
  Creates a sidebar component with title and menu items.

  ## Parameters
    * `canvas_id` - The canvas to create the component on
    * `x`, `y` - Position coordinates
    * `width`, `height` - Component dimensions
    * `theme` - Color theme
    * `content` - Map with optional :title and :items keys

  ## Returns
    * `{:ok, %{component_type: "sidebar", object_ids: [...]}}` on success
  """
  def create_sidebar(canvas_id, x, y, width, height, theme, content) do
    colors = Themes.get_theme_colors(theme)
    items = Map.get(content, "items", ["Dashboard", "Profile", "Settings", "Logout"])
    title = Map.get(content, "title", "Menu")

    created_objects = []

    # Create sidebar background
    {:ok, bg} =
      create_shape_for_component(
        canvas_id,
        "rectangle",
        x,
        y,
        width,
        height,
        colors.sidebar_bg,
        colors.border,
        1
      )

    created_objects = [bg.id | created_objects]

    # Create title
    {:ok, title_text} =
      create_text_for_component(
        canvas_id,
        title,
        x + 20,
        y + 20,
        20,
        "Arial",
        colors.text_primary,
        "left"
      )

    created_objects = [title_text.id | created_objects]

    # Create menu items
    created_objects =
      items
      |> Enum.with_index()
      |> Enum.reduce(created_objects, fn {item, index}, acc ->
        item_y = y + 60 + index * 50

        # Menu item background (hover state)
        {:ok, item_bg} =
          create_shape_for_component(
            canvas_id,
            "rectangle",
            x + 10,
            item_y,
            width - 20,
            40,
            colors.sidebar_item_bg,
            colors.sidebar_item_border,
            1
          )

        acc = [item_bg.id | acc]

        # Menu item text
        {:ok, item_text} =
          create_text_for_component(
            canvas_id,
            item,
            x + 25,
            item_y + 12,
            14,
            "Arial",
            colors.text_secondary,
            "left"
          )

        [item_text.id | acc]
      end)

    {:ok, %{component_type: "sidebar", object_ids: Enum.reverse(created_objects)}}
  end

  # Helper functions for component creation

  @doc """
  Creates a shape object for use within a component.

  Internal helper function used by component builders to create individual shape elements.
  """
  def create_shape_for_component(canvas_id, type, x, y, width, height, fill, stroke, stroke_width) do
    data = %{
      width: width,
      height: height,
      fill: fill,
      stroke: stroke,
      stroke_width: stroke_width
    }

    attrs = %{
      position: %{x: x, y: y},
      data: Jason.encode!(data)
    }

    Canvases.create_object(canvas_id, type, attrs)
  end

  @doc """
  Creates a text object for use within a component.

  Internal helper function used by component builders to create individual text elements.
  """
  def create_text_for_component(canvas_id, text, x, y, font_size, font_family, color, align) do
    data = %{
      text: text,
      font_size: font_size,
      font_family: font_family,
      color: color,
      align: align
    }

    attrs = %{
      position: %{x: x, y: y},
      data: Jason.encode!(data)
    }

    Canvases.create_object(canvas_id, "text", attrs)
  end
end
