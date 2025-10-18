defmodule CollabCanvas.AI.Tool do
  @moduledoc """
  Behaviour for AI tools in the CollabCanvas system.

  This module defines the contract that all AI tools must implement. Tools are
  self-contained modules that provide both their definition (for the Claude API)
  and their execution logic.

  ## Usage

  To create a new AI tool:

  1. Create a module in `lib/collab_canvas/ai/tools/`
  2. Implement the `CollabCanvas.AI.Tool` behaviour
  3. Define `definition/0` to return the tool schema
  4. Implement `execute/2` to handle tool execution

  The tool will be automatically discovered by `CollabCanvas.AI.ToolRegistry`
  and made available to the AI agent.

  ## Example

      defmodule CollabCanvas.AI.Tools.CreateShape do
        @behaviour CollabCanvas.AI.Tool

        @impl true
        def definition do
          %{
            name: "create_shape",
            description: "Create a shape (rectangle or circle) on the canvas",
            input_schema: %{
              type: "object",
              properties: %{
                type: %{type: "string", enum: ["rectangle", "circle"]},
                x: %{type: "number", description: "X coordinate"},
                y: %{type: "number", description: "Y coordinate"}
              },
              required: ["type", "x", "y"]
            }
          }
        end

        @impl true
        def execute(params, context) do
          # Implementation here
          {:ok, result}
        end
      end

  ## Tool Definition Format

  The `definition/0` callback must return a map with:

  - `:name` - String identifier for the tool (must be unique)
  - `:description` - Human-readable description of what the tool does
  - `:input_schema` - JSON Schema object defining parameters (Claude API format)

  ## Execution Context

  The `execute/2` callback receives:

  - `params` - Map of validated parameters from the AI
  - `context` - Map containing:
    - `:canvas_id` - ID of the canvas being operated on
    - `:current_color` - Current color from color picker
    - `:user_id` - ID of the user making the request (optional)

  ## Return Values

  The `execute/2` callback must return:

  - `{:ok, result}` - Successful execution with result data
  - `{:error, reason}` - Execution failed with error reason

  Results are used to build AI responses and update the canvas state.
  """

  @doc """
  Returns the tool definition for the Claude API.

  This definition includes the tool's name, description, and JSON Schema for
  parameter validation. It is used by the AI to understand what actions the
  tool can perform and what parameters it requires.

  ## Return Format

      %{
        name: "tool_name",
        description: "What the tool does",
        input_schema: %{
          type: "object",
          properties: %{
            param_name: %{
              type: "string" | "number" | "array" | "object",
              description: "Parameter description",
              enum: [...],        # Optional: allowed values
              default: value      # Optional: default value
            }
          },
          required: ["param1", "param2"]
        }
      }
  """
  @callback definition() :: %{
              name: String.t(),
              description: String.t(),
              input_schema: map()
            }

  @doc """
  Executes the tool with the given parameters and context.

  This is where the actual tool logic is implemented. The function receives
  validated parameters from the AI and a context map with canvas and user
  information.

  ## Parameters

    * `params` - Map of tool parameters (validated against input_schema)
    * `context` - Execution context map containing:
      - `:canvas_id` - Canvas ID to operate on
      - `:current_color` - Current color selection
      - Additional context as needed

  ## Return Values

    * `{:ok, result}` - Tool executed successfully
    * `{:error, reason}` - Tool execution failed

  The result can be any term that represents the outcome of the tool's operation.
  Common patterns:

  - `{:ok, %Object{}}` - Created or updated object
  - `{:ok, %{updated: count}}` - Batch operation result
  - `{:ok, {:text_response, "message"}}` - Text feedback to user
  - `{:error, :not_found}` - Object/resource not found
  - `{:error, :invalid_params}` - Parameter validation failed
  """
  @callback execute(params :: map(), context :: map()) ::
              {:ok, term()} | {:error, term()}
end
