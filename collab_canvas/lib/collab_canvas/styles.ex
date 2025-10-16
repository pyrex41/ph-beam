defmodule CollabCanvas.Styles do
  @moduledoc """
  The Styles context.

  This module provides the business logic layer for managing styles in the
  CollabCanvas application. It handles colors, text styles, and effects that
  can be applied to canvas objects and exported as design tokens.

  ## Features

  - **CRUD Operations**: Create, read, update, and delete styles
  - **Real-time Sync**: PubSub broadcasts for style changes across collaborators
  - **Style Application**: Apply styles to canvas objects
  - **Design Token Export**: Export styles in various design token formats
  - **Performance**: Style application optimized to meet 50ms target

  ## Style Types

  - **Color**: RGB/RGBA color definitions
  - **Text**: Typography styles (font family, size, weight, line-height)
  - **Effect**: Visual effects (shadows, blurs, etc.)

  ## Real-time Collaboration

  All style operations broadcast changes via Phoenix.PubSub to ensure
  real-time synchronization across all collaborators on a canvas.

  ## Usage Examples

      # Create a color style
      {:ok, style} = create_style(canvas_id, %{
        name: "Primary Blue",
        type: "color",
        category: "primary",
        definition: %{r: 37, g: 99, b: 235, a: 1.0}
      })

      # Apply style to an object
      {:ok, object} = apply_style(object_id, style_id)

      # Export design tokens
      {:ok, tokens} = export_design_tokens(canvas_id, :css)

      # Update style and propagate changes
      {:ok, updated} = update_style(style_id, %{
        definition: %{r: 40, g: 100, b: 240, a: 1.0}
      })
  """

  import Ecto.Query, warn: false
  alias CollabCanvas.Repo
  alias CollabCanvas.Styles.Style
  alias CollabCanvas.Canvases
  alias Phoenix.PubSub

  @pubsub CollabCanvas.PubSub
  @performance_target_ms 50

  # ============================================================================
  # CRUD Operations
  # ============================================================================

  @doc """
  Creates a new style on a canvas.

  ## Parameters
    * `canvas_id` - The ID of the canvas
    * `attrs` - Map of style attributes

  ## Required Attributes
    * `name` - Style name
    * `type` - Style type (color, text, effect)
    * `definition` - Style properties (map or JSON string)

  ## Optional Attributes
    * `category` - Style category
    * `created_by` - User ID who created the style

  ## Returns
    * `{:ok, style}` on success
    * `{:error, changeset}` on validation failure

  ## Examples

      iex> create_style(1, %{
      ...>   name: "Primary Blue",
      ...>   type: "color",
      ...>   definition: %{r: 37, g: 99, b: 235, a: 1.0}
      ...> })
      {:ok, %Style{}}

      iex> create_style(1, %{name: "Invalid"})
      {:error, %Ecto.Changeset{}}

  ## Broadcasts
    * `"styles:canvas_id"` - `{:style_created, style}`
  """
  def create_style(canvas_id, attrs) do
    attrs = Map.put(attrs, :canvas_id, canvas_id)

    result =
      %Style{}
      |> Style.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, style} ->
        broadcast_style_change(canvas_id, {:style_created, style})
        {:ok, style}

      error ->
        error
    end
  end

  @doc """
  Gets a single style by ID.

  ## Parameters
    * `id` - The style ID

  ## Returns
    * The style struct if found
    * `nil` if not found

  ## Examples

      iex> get_style(123)
      %Style{}

      iex> get_style(456)
      nil
  """
  def get_style(id) do
    Repo.get(Style, id)
  end

  @doc """
  Gets a style with preloaded associations.

  ## Parameters
    * `id` - The style ID
    * `preloads` - List of associations to preload (default: [:canvas, :creator])

  ## Returns
    * The style struct with preloaded associations if found
    * `nil` if not found

  ## Examples

      iex> get_style_with_preloads(123)
      %Style{canvas: %Canvas{}, creator: %User{}}
  """
  def get_style_with_preloads(id, preloads \\ [:canvas, :creator]) do
    case get_style(id) do
      nil -> nil
      style -> Repo.preload(style, preloads)
    end
  end

  @doc """
  Lists all styles for a specific canvas.

  ## Parameters
    * `canvas_id` - The canvas ID

  ## Options
    * `:type` - Filter by style type (e.g., "color", "text")
    * `:category` - Filter by category

  ## Returns
    * List of style structs

  ## Examples

      iex> list_styles(1)
      [%Style{}, %Style{}]

      iex> list_styles(1, type: "color")
      [%Style{type: "color"}, %Style{type: "color"}]
  """
  def list_styles(canvas_id, opts \\ []) do
    query =
      Style
      |> where([s], s.canvas_id == ^canvas_id)
      |> order_by([s], asc: s.name)

    query =
      if type = opts[:type] do
        where(query, [s], s.type == ^type)
      else
        query
      end

    query =
      if category = opts[:category] do
        where(query, [s], s.category == ^category)
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Updates an existing style.

  When a style is updated, all objects using that style are notified
  via PubSub for automatic re-rendering with the new style properties.

  ## Parameters
    * `id` - The style ID
    * `attrs` - Map of attributes to update

  ## Returns
    * `{:ok, style}` on success
    * `{:error, changeset}` on validation failure
    * `{:error, :not_found}` if style doesn't exist

  ## Examples

      iex> update_style(1, %{name: "Primary Blue Updated"})
      {:ok, %Style{}}

      iex> update_style(999, %{name: "Test"})
      {:error, :not_found}

  ## Broadcasts
    * `"styles:canvas_id"` - `{:style_updated, style}`

  ## Performance
    * Target: < 50ms including database update and PubSub broadcast
  """
  def update_style(id, attrs) do
    start_time = System.monotonic_time(:millisecond)

    result =
      case Repo.get(Style, id) do
        nil ->
          {:error, :not_found}

        style ->
          changeset = Style.changeset(style, attrs)

          case Repo.update(changeset) do
            {:ok, updated_style} ->
              # Broadcast style change for real-time sync
              broadcast_style_change(updated_style.canvas_id, {:style_updated, updated_style})

              # Log performance if it exceeds target
              elapsed = System.monotonic_time(:millisecond) - start_time

              if elapsed > @performance_target_ms do
                require Logger

                Logger.warning(
                  "Style update exceeded #{@performance_target_ms}ms target: #{elapsed}ms"
                )
              end

              {:ok, updated_style}

            error ->
              error
          end
      end

    result
  end

  @doc """
  Deletes a style.

  ## Parameters
    * `id` - The style ID

  ## Returns
    * `{:ok, style}` on success
    * `{:error, :not_found}` if style doesn't exist

  ## Examples

      iex> delete_style(1)
      {:ok, %Style{}}

      iex> delete_style(999)
      {:error, :not_found}

  ## Broadcasts
    * `"styles:canvas_id"` - `{:style_deleted, style_id}`
  """
  def delete_style(id) do
    case Repo.get(Style, id) do
      nil ->
        {:error, :not_found}

      style ->
        canvas_id = style.canvas_id

        case Repo.delete(style) do
          {:ok, deleted_style} ->
            broadcast_style_change(canvas_id, {:style_deleted, deleted_style.id})
            {:ok, deleted_style}

          error ->
            error
        end
    end
  end

  # ============================================================================
  # Style Application
  # ============================================================================

  @doc """
  Applies a style to a canvas object.

  This function updates the object's properties to match the style definition.
  The actual property mapping depends on the object type and style type.

  ## Parameters
    * `object_id` - The ID of the object to style
    * `style_id` - The ID of the style to apply

  ## Returns
    * `{:ok, object}` on success
    * `{:error, :not_found}` if object or style doesn't exist
    * `{:error, :incompatible_type}` if style cannot be applied to object

  ## Examples

      iex> apply_style(object_id, style_id)
      {:ok, %Object{}}

  ## Performance
    * Target: < 50ms including database operations
  """
  def apply_style(object_id, style_id) do
    start_time = System.monotonic_time(:millisecond)

    with {:ok, object} <- fetch_object(object_id),
         {:ok, style} <- fetch_style(style_id),
         {:ok, style_props} <- parse_style_definition(style),
         {:ok, updated_attrs} <- build_style_attrs(object, style_props, style.type) do
      # Update object with style attributes
      result = Canvases.update_object(object_id, updated_attrs)

      # Log performance
      elapsed = System.monotonic_time(:millisecond) - start_time

      if elapsed > @performance_target_ms do
        require Logger

        Logger.warning(
          "Style application exceeded #{@performance_target_ms}ms target: #{elapsed}ms"
        )
      end

      result
    end
  end

  # Helper to fetch object
  defp fetch_object(object_id) do
    case Canvases.get_object(object_id) do
      nil -> {:error, :not_found}
      object -> {:ok, object}
    end
  end

  # Helper to fetch style
  defp fetch_style(style_id) do
    case get_style(style_id) do
      nil -> {:error, :not_found}
      style -> {:ok, style}
    end
  end

  # Helper to parse style definition
  defp parse_style_definition(%Style{} = style) do
    {:ok, Style.decode_definition(style)}
  end

  # Helper to build style attributes for object
  defp build_style_attrs(object, style_props, style_type) do
    # Parse current object data (it's stored as JSON string)
    current_data =
      case object.data do
        nil ->
          %{}

        data_string when is_binary(data_string) ->
          case Jason.decode(data_string) do
            {:ok, parsed} -> parsed
            {:error, _} -> %{}
          end

        data when is_map(data) ->
          data
      end

    # Merge style properties based on type
    updated_data =
      case style_type do
        "color" ->
          Map.merge(current_data, %{"fill" => style_props})

        "text" ->
          Map.merge(current_data, %{"textStyle" => style_props})

        "effect" ->
          effects = Map.get(current_data, "effects", [])
          Map.put(current_data, "effects", effects ++ [style_props])

        _ ->
          current_data
      end

    # Convert back to JSON string for storage
    case Jason.encode(updated_data) do
      {:ok, json_data} ->
        {:ok, %{data: json_data}}

      {:error, _} ->
        {:error, :encoding_failed}
    end
  end

  # ============================================================================
  # Design Token Export
  # ============================================================================

  @doc """
  Exports styles as design tokens in the specified format.

  ## Parameters
    * `canvas_id` - The canvas ID
    * `format` - Export format (`:css`, `:scss`, `:json`, `:js`)

  ## Returns
    * `{:ok, token_string}` on success
    * `{:error, reason}` on failure

  ## Formats

  - `:css` - CSS custom properties
  - `:scss` - SCSS variables
  - `:json` - JSON design tokens
  - `:js` - JavaScript/TypeScript constants

  ## Examples

      iex> export_design_tokens(1, :css)
      {:ok, ":root {\\n  --primary-blue: rgb(37, 99, 235);\\n}"}

      iex> export_design_tokens(1, :json)
      {:ok, "{\\"colors\\": {\\"primary-blue\\": \\"#2563eb\\"}}"}
  """
  def export_design_tokens(canvas_id, format) when format in [:css, :scss, :json, :js] do
    styles = list_styles(canvas_id)

    case format do
      :css -> export_to_css(styles)
      :scss -> export_to_scss(styles)
      :json -> export_to_json(styles)
      :js -> export_to_js(styles)
    end
  end

  def export_design_tokens(_canvas_id, format) do
    {:error, "Unsupported format: #{format}"}
  end

  # Export to CSS custom properties
  defp export_to_css(styles) do
    tokens =
      styles
      |> Enum.map(&style_to_css_token/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n")

    css = ":root {\n#{tokens}\n}"
    {:ok, css}
  end

  defp style_to_css_token(%Style{type: "color", name: name} = style) do
    props = Style.decode_definition(style)
    color_value = format_css_color(props)
    var_name = String.downcase(name) |> String.replace(" ", "-")
    "  --#{var_name}: #{color_value};"
  end

  defp style_to_css_token(%Style{type: "text", name: name} = style) do
    props = Style.decode_definition(style)
    var_name = String.downcase(name) |> String.replace(" ", "-")

    [
      "  --#{var_name}-font-family: #{props["fontFamily"] || "inherit"};",
      "  --#{var_name}-font-size: #{props["fontSize"] || 16}px;",
      "  --#{var_name}-font-weight: #{props["fontWeight"] || 400};",
      "  --#{var_name}-line-height: #{props["lineHeight"] || 1.5};"
    ]
    |> Enum.join("\n")
  end

  defp style_to_css_token(_), do: nil

  # Export to SCSS variables
  defp export_to_scss(styles) do
    tokens =
      styles
      |> Enum.map(&style_to_scss_token/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n")

    {:ok, tokens}
  end

  defp style_to_scss_token(%Style{type: "color", name: name} = style) do
    props = Style.decode_definition(style)
    color_value = format_css_color(props)
    var_name = String.downcase(name) |> String.replace(" ", "-")
    "$#{var_name}: #{color_value};"
  end

  defp style_to_scss_token(%Style{type: "text", name: name} = style) do
    props = Style.decode_definition(style)
    var_name = String.downcase(name) |> String.replace(" ", "-")

    [
      "$#{var_name}-font-family: #{props["fontFamily"] || "inherit"};",
      "$#{var_name}-font-size: #{props["fontSize"] || 16}px;",
      "$#{var_name}-font-weight: #{props["fontWeight"] || 400};",
      "$#{var_name}-line-height: #{props["lineHeight"] || 1.5};"
    ]
    |> Enum.join("\n")
  end

  defp style_to_scss_token(_), do: nil

  # Export to JSON design tokens
  defp export_to_json(styles) do
    tokens =
      styles
      |> Enum.group_by(& &1.type)
      |> Map.new(fn {type, type_styles} ->
        style_map =
          type_styles
          |> Map.new(fn style ->
            name = String.downcase(style.name) |> String.replace(" ", "-")
            {name, Style.decode_definition(style)}
          end)

        {type <> "s", style_map}
      end)

    case Jason.encode(tokens, pretty: true) do
      {:ok, json} -> {:ok, json}
      {:error, reason} -> {:error, "JSON encoding failed: #{inspect(reason)}"}
    end
  end

  # Export to JavaScript/TypeScript constants
  defp export_to_js(styles) do
    tokens =
      styles
      |> Enum.map(&style_to_js_token/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n")

    js = "export const tokens = {\n#{tokens}\n};"
    {:ok, js}
  end

  defp style_to_js_token(%Style{type: "color", name: name} = style) do
    props = Style.decode_definition(style)
    color_value = format_css_color(props)
    var_name = String.downcase(name) |> String.replace(" ", "-") |> String.replace("-", "_")
    "  #{var_name}: '#{color_value}',"
  end

  defp style_to_js_token(%Style{type: "text", name: name} = style) do
    props = Style.decode_definition(style)
    var_name = String.downcase(name) |> String.replace(" ", "-") |> String.replace("-", "_")

    props_json = Jason.encode!(props)
    "  #{var_name}: #{props_json},"
  end

  defp style_to_js_token(_), do: nil

  # Format color as CSS rgb/rgba
  defp format_css_color(%{"r" => r, "g" => g, "b" => b, "a" => a}) when a < 1.0 do
    "rgba(#{r}, #{g}, #{b}, #{a})"
  end

  defp format_css_color(%{"r" => r, "g" => g, "b" => b}) do
    "rgb(#{r}, #{g}, #{b})"
  end

  defp format_css_color(_), do: "transparent"

  # ============================================================================
  # PubSub Integration
  # ============================================================================

  @doc """
  Subscribes to style changes for a canvas.

  ## Parameters
    * `canvas_id` - The canvas ID

  ## Examples

      iex> subscribe_to_styles(123)
      :ok
  """
  def subscribe_to_styles(canvas_id) do
    PubSub.subscribe(@pubsub, "styles:#{canvas_id}")
  end

  @doc """
  Unsubscribes from style changes for a canvas.

  ## Parameters
    * `canvas_id` - The canvas ID

  ## Examples

      iex> unsubscribe_from_styles(123)
      :ok
  """
  def unsubscribe_from_styles(canvas_id) do
    PubSub.unsubscribe(@pubsub, "styles:#{canvas_id}")
  end

  @doc """
  Broadcasts a style change event to all subscribers.

  ## Parameters
    * `canvas_id` - The canvas ID
    * `message` - The message to broadcast

  ## Message Formats
    * `{:style_created, style}`
    * `{:style_updated, style}`
    * `{:style_deleted, style_id}`

  ## Examples

      iex> broadcast_style_change(123, {:style_updated, style})
      :ok
  """
  def broadcast_style_change(canvas_id, message) do
    PubSub.broadcast(@pubsub, "styles:#{canvas_id}", message)
  end
end
