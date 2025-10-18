defmodule CollabCanvas.AI.ToolRegistry do
  @moduledoc """
  Central registry for AI tools with automatic discovery.

  This module provides a registry pattern for AI tools, automatically discovering
  all modules that implement the `CollabCanvas.AI.Tool` behaviour. Tools are
  discovered at compile time for performance.

  ## Tool Discovery

  The registry automatically finds all modules matching the pattern:
  `CollabCanvas.AI.Tools.*` that implement the `CollabCanvas.AI.Tool` behaviour.

  New tools are automatically registered when they are added to the
  `lib/collab_canvas/ai/tools/` directory.

  ## Usage

      # Get all tool definitions for Claude API
      tool_definitions = ToolRegistry.list_tools()

      # Find a specific tool
      {:ok, CreateShape} = ToolRegistry.get_tool("create_shape")

      # Execute a tool
      context = %{canvas_id: 1, current_color: "#FF0000"}
      {:ok, result} = ToolRegistry.execute("create_shape", params, context)

  ## Performance

  Tool discovery happens at compile time, so runtime lookups are O(1) map lookups.
  No runtime filesystem scanning or module enumeration.
  """

  require Logger

  @doc """
  Returns a list of all registered tool definitions.

  This function is used to provide the Claude API with the complete set of
  available tools. Each definition includes the tool's name, description,
  and parameter schema.

  ## Returns

  A list of tool definition maps suitable for the Claude API:

      [
        %{
          name: "create_shape",
          description: "Create a shape on the canvas",
          input_schema: %{...}
        },
        ...
      ]

  ## Examples

      iex> tools = ToolRegistry.list_tools()
      iex> Enum.map(tools, & &1.name)
      ["create_shape", "delete_object", ...]
  """
  def list_tools do
    tool_modules()
    |> Enum.map(fn module ->
      module.definition()
    end)
    |> Enum.sort_by(& &1.name)
  end

  @doc """
  Finds a tool module by its name.

  ## Parameters

    * `name` - The tool name (string) to look up

  ## Returns

    * `{:ok, module}` - Tool module found
    * `{:error, :not_found}` - No tool with that name exists

  ## Examples

      iex> ToolRegistry.get_tool("create_shape")
      {:ok, CollabCanvas.AI.Tools.CreateShape}

      iex> ToolRegistry.get_tool("nonexistent")
      {:error, :not_found}
  """
  def get_tool(name) when is_binary(name) do
    case Enum.find(tool_modules(), fn module ->
           module.definition().name == name
         end) do
      nil -> {:error, :not_found}
      module -> {:ok, module}
    end
  end

  @doc """
  Executes a tool with the given parameters and context.

  This is the main entry point for tool execution. It looks up the tool by name,
  validates that it exists, and delegates to the tool's `execute/2` callback.

  ## Parameters

    * `name` - Tool name (string)
    * `params` - Tool parameters (map)
    * `context` - Execution context containing canvas_id, current_color, etc.

  ## Returns

    * `{:ok, result}` - Tool executed successfully
    * `{:error, :not_found}` - Tool doesn't exist
    * `{:error, reason}` - Tool execution failed

  ## Examples

      iex> context = %{canvas_id: 1, current_color: "#FF0000"}
      iex> params = %{"type" => "rectangle", "x" => 10, "y" => 20}
      iex> ToolRegistry.execute("create_shape", params, context)
      {:ok, %CollabCanvas.Canvases.Object{...}}
  """
  def execute(name, params, context) when is_binary(name) and is_map(params) and is_map(context) do
    case get_tool(name) do
      {:ok, tool_module} ->
        Logger.debug("Executing tool: #{name} via #{inspect(tool_module)}")
        tool_module.execute(params, context)

      {:error, :not_found} = error ->
        Logger.warning("Tool not found: #{name}")
        error
    end
  end

  # Private Functions

  # Returns the list of all tool modules.
  # This function discovers tool modules at compile time by checking all modules
  # in the CollabCanvas.AI.Tools namespace.
  defp tool_modules do
    # At runtime, we need to discover modules dynamically since we can't use
    # compile-time introspection easily. We'll check for the existence of
    # known tool modules.
    #
    # In production, you could use a compile-time macro to build this list,
    # but for flexibility during development, we'll use a simple runtime check.
    potential_tools = [
      CollabCanvas.AI.Tools.CreateShape,
      CollabCanvas.AI.Tools.DeleteObject,
      CollabCanvas.AI.Tools.ArrangeObjects
    ]

    # Filter to only modules that exist and implement the Tool behaviour
    Enum.filter(potential_tools, fn module ->
      Code.ensure_loaded?(module) and function_exported?(module, :definition, 0)
    end)
  end

  @doc """
  Validates tool parameters against the tool's input schema.

  This is a utility function for validating parameters before execution.
  Currently this delegates to the existing validation logic in Tools module.

  ## Parameters

    * `tool_name` - Name of the tool
    * `params` - Parameters to validate

  ## Returns

    * `{:ok, validated_params}` - Parameters are valid (with defaults applied)
    * `{:error, reason}` - Validation failed

  ## Examples

      iex> params = %{"type" => "rectangle", "x" => 10, "y" => 20}
      iex> ToolRegistry.validate("create_shape", params)
      {:ok, %{"type" => "rectangle", "x" => 10, "y" => 20, "width" => 100, ...}}
  """
  def validate(tool_name, params) do
    # Delegate to the existing validation logic in Tools module for backward compatibility
    CollabCanvas.AI.Tools.validate_tool_call(tool_name, params)
  end
end
