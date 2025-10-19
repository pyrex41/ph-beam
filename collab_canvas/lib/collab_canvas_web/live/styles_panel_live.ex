defmodule CollabCanvasWeb.StylesPanelLive do
  @moduledoc """
  LiveView component for managing color palettes, text styles, and effects.

  This module provides a complete styles management panel with real-time
  synchronization across multiple users. It integrates with the Styles context
  to provide CRUD operations for design styles and design token export.

  ## Features

  ### Style Management
  - Create, update, and delete color, text, and effect styles
  - Apply styles to canvas objects with one click
  - Real-time synchronization via PubSub
  - Style categories for organization (primary, secondary, heading, body, etc.)

  ### Design Token Export
  - Export styles in multiple formats: CSS, SCSS, JSON, JavaScript
  - Download design tokens for use in other projects
  - Maintains consistency across design and development

  ### Real-time Collaboration
  - All style changes are broadcast to connected collaborators
  - PubSub integration ensures instant updates
  - Performance target: < 50ms for style application

  ## State Management

  The socket assigns include:
  - `:canvas_id` - Canvas identifier for loading styles
  - `:styles` - List of all styles for this canvas
  - `:selected_style` - Currently selected style for preview
  - `:show_modal` - Boolean indicating if creation modal is open
  - `:modal_type` - Type of style being created ("color", "text", "effect")
  - `:export_format` - Selected export format for design tokens
  - `:topic` - PubSub topic string for style updates

  ## Usage

  This component is typically rendered as a side panel in the canvas view:

      <.live_component
        module={CollabCanvasWeb.StylesPanelLive}
        id="styles-panel"
        canvas_id={@canvas_id}
      />
  """

  use CollabCanvasWeb, :live_component

  alias CollabCanvas.Styles
  alias Phoenix.PubSub

  require Logger

  @impl true
  def mount(socket) do
    {:ok, socket}
  end

  @impl true
  def update(%{canvas_id: canvas_id} = assigns, socket) do
    # Subscribe to style changes if not already subscribed
    if connected?(socket) do
      topic = "styles:#{canvas_id}"
      PubSub.subscribe(CollabCanvas.PubSub, topic)
    end

    # Load all styles for this canvas
    styles = Styles.list_styles(canvas_id)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:canvas_id, canvas_id)
     |> assign(:styles, styles)
     |> assign(:selected_style, nil)
     |> assign(:show_modal, false)
     |> assign(:modal_type, "color")
     |> assign(:export_format, "css")
     |> assign(:topic, "styles:#{canvas_id}")}
  end

  @impl true
  def handle_event("open_create_modal", %{"type" => type}, socket) do
    {:noreply,
     socket
     |> assign(:show_modal, true)
     |> assign(:modal_type, type)}
  end

  @impl true
  def handle_event("close_modal", _params, socket) do
    {:noreply, assign(socket, :show_modal, false)}
  end

  @impl true
  def handle_event("create_style", params, socket) do
    canvas_id = socket.assigns.canvas_id
    style_type = params["type"]

    # Build style attributes based on type
    attrs = %{
      name: params["name"],
      type: style_type,
      category: params["category"],
      definition: build_definition(style_type, params)
    }

    case Styles.create_style(canvas_id, attrs) do
      {:ok, style} ->
        # Update local state (broadcast is handled by Styles context)
        styles = [style | socket.assigns.styles]

        {:noreply,
         socket
         |> assign(:styles, styles)
         |> assign(:show_modal, false)
         |> put_flash(:info, "Style '#{style.name}' created successfully")}

      {:error, changeset} ->
        errors = format_changeset_errors(changeset)

        {:noreply,
         socket
         |> put_flash(:error, "Failed to create style: #{errors}")}
    end
  end

  @impl true
  def handle_event("update_style", %{"id" => style_id} = params, socket) do
    style_id = String.to_integer(style_id)

    attrs = %{
      name: params["name"],
      category: params["category"],
      definition: build_definition(params["type"], params)
    }

    case Styles.update_style(style_id, attrs) do
      {:ok, updated_style} ->
        # Update local state
        styles =
          Enum.map(socket.assigns.styles, fn style ->
            if style.id == updated_style.id, do: updated_style, else: style
          end)

        {:noreply,
         socket
         |> assign(:styles, styles)
         |> put_flash(:info, "Style '#{updated_style.name}' updated successfully")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Style not found")}

      {:error, changeset} ->
        errors = format_changeset_errors(changeset)

        {:noreply,
         socket
         |> put_flash(:error, "Failed to update style: #{errors}")}
    end
  end

  @impl true
  def handle_event("delete_style", %{"id" => style_id}, socket) do
    style_id = String.to_integer(style_id)

    case Styles.delete_style(style_id) do
      {:ok, deleted_style} ->
        # Update local state
        styles = Enum.reject(socket.assigns.styles, fn s -> s.id == deleted_style.id end)

        {:noreply,
         socket
         |> assign(:styles, styles)
         |> put_flash(:info, "Style '#{deleted_style.name}' deleted successfully")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Style not found")}
    end
  end

  @impl true
  def handle_event("apply_style", %{"style_id" => style_id, "object_id" => object_id}, socket) do
    style_id = String.to_integer(style_id)
    object_id = String.to_integer(object_id)

    case Styles.apply_style(object_id, style_id) do
      {:ok, _updated_object} ->
        {:noreply,
         socket
         |> put_flash(:info, "Style applied successfully")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Style or object not found")}

      {:error, :incompatible_type} ->
        {:noreply, put_flash(socket, :error, "Cannot apply this style to the selected object")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to apply style: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("select_export_format", %{"format" => format}, socket) do
    {:noreply, assign(socket, :export_format, format)}
  end

  @impl true
  def handle_event("export_design_tokens", _params, socket) do
    canvas_id = socket.assigns.canvas_id
    format = String.to_atom(socket.assigns.export_format)

    case Styles.export_design_tokens(canvas_id, format) do
      {:ok, tokens} ->
        # Send download event to client
        send(self(), {:download_tokens, tokens, format})

        {:noreply,
         socket
         |> put_flash(:info, "Design tokens exported as #{format}")}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to export: #{reason}")}
    end
  end

  @impl true
  def handle_event("select_style", %{"id" => style_id}, socket) do
    style_id = String.to_integer(style_id)
    selected_style = Enum.find(socket.assigns.styles, &(&1.id == style_id))

    {:noreply, assign(socket, :selected_style, selected_style)}
  end

  # Handle PubSub broadcasts for style changes
  @impl true
  def handle_info({:style_created, style}, socket) do
    # Check if style is already in our list (deduplication)
    exists? = Enum.any?(socket.assigns.styles, fn s -> s.id == style.id end)

    if exists? do
      {:noreply, socket}
    else
      styles = [style | socket.assigns.styles]
      {:noreply, assign(socket, :styles, styles)}
    end
  end

  @impl true
  def handle_info({:style_updated, updated_style}, socket) do
    styles =
      Enum.map(socket.assigns.styles, fn style ->
        if style.id == updated_style.id, do: updated_style, else: style
      end)

    {:noreply, assign(socket, :styles, styles)}
  end

  @impl true
  def handle_info({:style_deleted, style_id}, socket) do
    styles = Enum.reject(socket.assigns.styles, fn s -> s.id == style_id end)

    # Clear selection if deleted style was selected
    selected_style =
      if socket.assigns.selected_style && socket.assigns.selected_style.id == style_id do
        nil
      else
        socket.assigns.selected_style
      end

    {:noreply,
     socket
     |> assign(:styles, styles)
     |> assign(:selected_style, selected_style)}
  end

  @impl true
  def handle_info({:download_tokens, tokens, format}, socket) do
    # Push download event to JavaScript
    {:noreply,
     push_event(socket, "download_tokens", %{
       content: tokens,
       filename: "design-tokens.#{format}",
       format: format
     })}
  end

  # Helper to build style definition based on type
  defp build_definition("color", params) do
    %{
      "r" => String.to_integer(params["r"] || "0"),
      "g" => String.to_integer(params["g"] || "0"),
      "b" => String.to_integer(params["b"] || "0"),
      "a" => String.to_float(params["a"] || "1.0")
    }
  end

  defp build_definition("text", params) do
    %{
      "fontFamily" => params["fontFamily"] || "inherit",
      "fontSize" => String.to_integer(params["fontSize"] || "16"),
      "fontWeight" => String.to_integer(params["fontWeight"] || "400"),
      "lineHeight" => String.to_float(params["lineHeight"] || "1.5")
    }
  end

  defp build_definition("effect", params) do
    %{
      "type" => params["effectType"] || "shadow",
      "offsetX" => String.to_integer(params["offsetX"] || "0"),
      "offsetY" => String.to_integer(params["offsetY"] || "0"),
      "blur" => String.to_integer(params["blur"] || "0"),
      "color" => params["effectColor"] || "rgba(0,0,0,0.5)"
    }
  end

  defp build_definition(_, _params), do: %{}

  # Helper to format changeset errors
  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map(fn {field, errors} -> "#{field}: #{Enum.join(errors, ", ")}" end)
    |> Enum.join("; ")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="h-full flex flex-col bg-white">
      <!-- Header -->
      <div class="p-4 border-b border-gray-200">
        <div class="flex items-center justify-between mb-2">
          <h2 class="text-lg font-semibold text-gray-800">Styles</h2>
          <button
            phx-click="export_design_tokens"
            phx-target={@myself}
            class="text-sm px-3 py-1 bg-gray-100 hover:bg-gray-200 rounded-md transition-colors"
            title="Export design tokens"
          >
            Export
          </button>
        </div>
        <p class="text-sm text-gray-500">Manage colors, text styles, and effects</p>
      </div>
      
    <!-- Export Format Selector -->
      <div class="px-4 py-2 border-b border-gray-200 bg-gray-50">
        <label class="block text-xs font-medium text-gray-700 mb-1">Export Format</label>
        <select
          phx-change="select_export_format"
          phx-target={@myself}
          class="w-full text-sm border border-gray-300 rounded-md px-2 py-1"
        >
          <option value="css" selected={@export_format == "css"}>CSS Custom Properties</option>
          <option value="scss" selected={@export_format == "scss"}>SCSS Variables</option>
          <option value="json" selected={@export_format == "json"}>JSON</option>
          <option value="js" selected={@export_format == "js"}>JavaScript/TypeScript</option>
        </select>
      </div>
      
    <!-- Styles List -->
      <div class="flex-1 overflow-y-auto">
        <!-- Color Styles Section -->
        <div class="p-4 border-b border-gray-200">
          <div class="flex items-center justify-between mb-3">
            <h3 class="text-sm font-semibold text-gray-700 uppercase tracking-wide">Colors</h3>
            <button
              phx-click="open_create_modal"
              phx-value-type="color"
              phx-target={@myself}
              class="text-xs px-2 py-1 bg-blue-600 text-white rounded hover:bg-blue-700 transition-colors"
            >
              + Add
            </button>
          </div>

          <div class="grid grid-cols-4 gap-2">
            <%= for style <- Enum.filter(@styles, &(&1.type == "color")) do %>
              <div
                phx-click="select_style"
                phx-value-id={style.id}
                phx-target={@myself}
                class={[
                  "aspect-square rounded-lg cursor-pointer border-2 transition-all group relative",
                  @selected_style && @selected_style.id == style.id &&
                    "border-blue-500 ring-2 ring-blue-200",
                  (!@selected_style || @selected_style.id != style.id) &&
                    "border-gray-200 hover:border-gray-300"
                ]}
                style={"background-color: #{format_color(style)}"}
                title={style.name}
              >
                <button
                  phx-click="delete_style"
                  phx-value-id={style.id}
                  phx-target={@myself}
                  class="absolute top-1 right-1 opacity-0 group-hover:opacity-100 transition-opacity bg-white rounded-full p-0.5 shadow-sm"
                  title="Delete"
                >
                  <svg
                    class="w-3 h-3 text-red-600"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M6 18L18 6M6 6l12 12"
                    />
                  </svg>
                </button>
              </div>
            <% end %>
          </div>

          <%= if Enum.empty?(Enum.filter(@styles, &(&1.type == "color"))) do %>
            <p class="text-sm text-gray-400 text-center py-4">No color styles yet</p>
          <% end %>
        </div>
        
    <!-- Text Styles Section -->
        <div class="p-4 border-b border-gray-200">
          <div class="flex items-center justify-between mb-3">
            <h3 class="text-sm font-semibold text-gray-700 uppercase tracking-wide">Text Styles</h3>
            <button
              phx-click="open_create_modal"
              phx-value-type="text"
              phx-target={@myself}
              class="text-xs px-2 py-1 bg-blue-600 text-white rounded hover:bg-blue-700 transition-colors"
            >
              + Add
            </button>
          </div>

          <div class="space-y-2">
            <%= for style <- Enum.filter(@styles, &(&1.type == "text")) do %>
              <div
                phx-click="select_style"
                phx-value-id={style.id}
                phx-target={@myself}
                class={[
                  "p-3 rounded-lg border cursor-pointer transition-all group relative",
                  @selected_style && @selected_style.id == style.id &&
                    "border-blue-500 bg-blue-50",
                  (!@selected_style || @selected_style.id != style.id) &&
                    "border-gray-200 hover:border-gray-300 hover:bg-gray-50"
                ]}
              >
                <div class="flex items-start justify-between">
                  <div class="flex-1">
                    <div class="text-sm font-medium text-gray-900 mb-1">{style.name}</div>
                    <div class="text-xs text-gray-500" style={format_text_preview(style)}>
                      The quick brown fox
                    </div>
                  </div>
                  <button
                    phx-click="delete_style"
                    phx-value-id={style.id}
                    phx-target={@myself}
                    class="opacity-0 group-hover:opacity-100 transition-opacity text-red-600 hover:text-red-800"
                    title="Delete"
                  >
                    <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M6 18L18 6M6 6l12 12"
                      />
                    </svg>
                  </button>
                </div>
              </div>
            <% end %>
          </div>

          <%= if Enum.empty?(Enum.filter(@styles, &(&1.type == "text"))) do %>
            <p class="text-sm text-gray-400 text-center py-4">No text styles yet</p>
          <% end %>
        </div>
        
    <!-- Effect Styles Section -->
        <div class="p-4">
          <div class="flex items-center justify-between mb-3">
            <h3 class="text-sm font-semibold text-gray-700 uppercase tracking-wide">Effects</h3>
            <button
              phx-click="open_create_modal"
              phx-value-type="effect"
              phx-target={@myself}
              class="text-xs px-2 py-1 bg-blue-600 text-white rounded hover:bg-blue-700 transition-colors"
            >
              + Add
            </button>
          </div>

          <div class="space-y-2">
            <%= for style <- Enum.filter(@styles, &(&1.type == "effect")) do %>
              <div
                phx-click="select_style"
                phx-value-id={style.id}
                phx-target={@myself}
                class={[
                  "p-3 rounded-lg border cursor-pointer transition-all group relative",
                  @selected_style && @selected_style.id == style.id &&
                    "border-blue-500 bg-blue-50",
                  (!@selected_style || @selected_style.id != style.id) &&
                    "border-gray-200 hover:border-gray-300 hover:bg-gray-50"
                ]}
              >
                <div class="flex items-center justify-between">
                  <div class="text-sm font-medium text-gray-900">{style.name}</div>
                  <button
                    phx-click="delete_style"
                    phx-value-id={style.id}
                    phx-target={@myself}
                    class="opacity-0 group-hover:opacity-100 transition-opacity text-red-600 hover:text-red-800"
                    title="Delete"
                  >
                    <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M6 18L18 6M6 6l12 12"
                      />
                    </svg>
                  </button>
                </div>
              </div>
            <% end %>
          </div>

          <%= if Enum.empty?(Enum.filter(@styles, &(&1.type == "effect"))) do %>
            <p class="text-sm text-gray-400 text-center py-4">No effect styles yet</p>
          <% end %>
        </div>
      </div>
      
    <!-- Style Creation Modal -->
      <%= if @show_modal do %>
        <div class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
          <div class="bg-white rounded-lg shadow-xl max-w-md w-full mx-4">
            <div class="p-4 border-b border-gray-200 flex items-center justify-between">
              <h3 class="text-lg font-semibold text-gray-900">
                Create {String.capitalize(@modal_type)} Style
              </h3>
              <button
                phx-click="close_modal"
                phx-target={@myself}
                class="text-gray-400 hover:text-gray-600"
              >
                <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M6 18L18 6M6 6l12 12"
                  />
                </svg>
              </button>
            </div>

            <form phx-submit="create_style" phx-target={@myself} class="p-4 space-y-4">
              <input type="hidden" name="type" value={@modal_type} />
              
    <!-- Name Field -->
              <div>
                <label class="block text-sm font-medium text-gray-700 mb-1">Name</label>
                <input
                  type="text"
                  name="name"
                  required
                  class="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                  placeholder="e.g., Primary Blue"
                />
              </div>
              
    <!-- Category Field -->
              <div>
                <label class="block text-sm font-medium text-gray-700 mb-1">Category</label>
                <select
                  name="category"
                  class="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                >
                  <%= if @modal_type == "color" do %>
                    <option value="primary">Primary</option>
                    <option value="secondary">Secondary</option>
                    <option value="accent">Accent</option>
                    <option value="neutral">Neutral</option>
                  <% end %>
                  <%= if @modal_type == "text" do %>
                    <option value="heading">Heading</option>
                    <option value="body">Body</option>
                    <option value="caption">Caption</option>
                  <% end %>
                  <%= if @modal_type == "effect" do %>
                    <option value="shadow">Shadow</option>
                    <option value="blur">Blur</option>
                  <% end %>
                </select>
              </div>
              
    <!-- Type-specific Fields -->
              <%= if @modal_type == "color" do %>
                <div class="grid grid-cols-4 gap-2">
                  <div>
                    <label class="block text-xs font-medium text-gray-700 mb-1">R</label>
                    <input
                      type="number"
                      name="r"
                      min="0"
                      max="255"
                      value="0"
                      required
                      class="w-full px-2 py-2 border border-gray-300 rounded-md text-sm"
                    />
                  </div>
                  <div>
                    <label class="block text-xs font-medium text-gray-700 mb-1">G</label>
                    <input
                      type="number"
                      name="g"
                      min="0"
                      max="255"
                      value="0"
                      required
                      class="w-full px-2 py-2 border border-gray-300 rounded-md text-sm"
                    />
                  </div>
                  <div>
                    <label class="block text-xs font-medium text-gray-700 mb-1">B</label>
                    <input
                      type="number"
                      name="b"
                      min="0"
                      max="255"
                      value="0"
                      required
                      class="w-full px-2 py-2 border border-gray-300 rounded-md text-sm"
                    />
                  </div>
                  <div>
                    <label class="block text-xs font-medium text-gray-700 mb-1">A</label>
                    <input
                      type="number"
                      name="a"
                      min="0"
                      max="1"
                      step="0.1"
                      value="1.0"
                      required
                      class="w-full px-2 py-2 border border-gray-300 rounded-md text-sm"
                    />
                  </div>
                </div>
              <% end %>

              <%= if @modal_type == "text" do %>
                <div>
                  <label class="block text-sm font-medium text-gray-700 mb-1">Font Family</label>
                  <input
                    type="text"
                    name="fontFamily"
                    value="Arial, sans-serif"
                    required
                    class="w-full px-3 py-2 border border-gray-300 rounded-md"
                  />
                </div>
                <div class="grid grid-cols-3 gap-2">
                  <div>
                    <label class="block text-xs font-medium text-gray-700 mb-1">Size (px)</label>
                    <input
                      type="number"
                      name="fontSize"
                      value="16"
                      required
                      class="w-full px-2 py-2 border border-gray-300 rounded-md text-sm"
                    />
                  </div>
                  <div>
                    <label class="block text-xs font-medium text-gray-700 mb-1">Weight</label>
                    <input
                      type="number"
                      name="fontWeight"
                      value="400"
                      required
                      class="w-full px-2 py-2 border border-gray-300 rounded-md text-sm"
                    />
                  </div>
                  <div>
                    <label class="block text-xs font-medium text-gray-700 mb-1">Line Height</label>
                    <input
                      type="number"
                      name="lineHeight"
                      step="0.1"
                      value="1.5"
                      required
                      class="w-full px-2 py-2 border border-gray-300 rounded-md text-sm"
                    />
                  </div>
                </div>
              <% end %>

              <%= if @modal_type == "effect" do %>
                <div>
                  <label class="block text-sm font-medium text-gray-700 mb-1">Effect Type</label>
                  <select
                    name="effectType"
                    class="w-full px-3 py-2 border border-gray-300 rounded-md"
                  >
                    <option value="shadow">Shadow</option>
                    <option value="blur">Blur</option>
                  </select>
                </div>
                <div class="grid grid-cols-3 gap-2">
                  <div>
                    <label class="block text-xs font-medium text-gray-700 mb-1">Offset X</label>
                    <input
                      type="number"
                      name="offsetX"
                      value="0"
                      class="w-full px-2 py-2 border border-gray-300 rounded-md text-sm"
                    />
                  </div>
                  <div>
                    <label class="block text-xs font-medium text-gray-700 mb-1">Offset Y</label>
                    <input
                      type="number"
                      name="offsetY"
                      value="2"
                      class="w-full px-2 py-2 border border-gray-300 rounded-md text-sm"
                    />
                  </div>
                  <div>
                    <label class="block text-xs font-medium text-gray-700 mb-1">Blur</label>
                    <input
                      type="number"
                      name="blur"
                      value="4"
                      class="w-full px-2 py-2 border border-gray-300 rounded-md text-sm"
                    />
                  </div>
                </div>
                <div>
                  <label class="block text-sm font-medium text-gray-700 mb-1">Color</label>
                  <input
                    type="text"
                    name="effectColor"
                    value="rgba(0,0,0,0.5)"
                    class="w-full px-3 py-2 border border-gray-300 rounded-md"
                  />
                </div>
              <% end %>
              
    <!-- Actions -->
              <div class="flex items-center justify-end gap-2 pt-4">
                <button
                  type="button"
                  phx-click="close_modal"
                  phx-target={@myself}
                  class="px-4 py-2 border border-gray-300 rounded-md text-gray-700 hover:bg-gray-50 transition-colors"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  class="px-4 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700 transition-colors"
                >
                  Create Style
                </button>
              </div>
            </form>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # Helper to format color for display
  defp format_color(style) do
    definition = Styles.Style.decode_definition(style)

    case definition do
      %{"r" => r, "g" => g, "b" => b, "a" => a} when a < 1.0 ->
        "rgba(#{r}, #{g}, #{b}, #{a})"

      %{"r" => r, "g" => g, "b" => b} ->
        "rgb(#{r}, #{g}, #{b})"

      _ ->
        "#cccccc"
    end
  end

  # Helper to format text style for preview
  defp format_text_preview(style) do
    definition = Styles.Style.decode_definition(style)

    [
      "font-family: #{definition["fontFamily"] || "inherit"}",
      "font-size: #{definition["fontSize"] || 16}px",
      "font-weight: #{definition["fontWeight"] || 400}",
      "line-height: #{definition["lineHeight"] || 1.5}"
    ]
    |> Enum.join("; ")
  end
end
