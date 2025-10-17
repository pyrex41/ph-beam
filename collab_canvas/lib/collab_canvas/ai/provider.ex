defmodule CollabCanvas.AI.Provider do
  @moduledoc """
  Behaviour for LLM providers.
  
  Allows switching between different AI providers (Groq, Claude, etc.)
  based on command complexity and performance requirements.
  
  ## Purpose
  
  This behaviour enables:
  - Hot-swapping between LLM providers
  - Performance optimization (fast providers for simple commands)
  - Fallback mechanisms when primary provider fails
  - Cost optimization (cheaper providers when appropriate)
  
  ## Example Implementation
  
      defmodule MyProvider do
        @behaviour CollabCanvas.AI.Provider
        
        def call(command, tools, _opts) do
          # Make API call
          {:ok, tool_calls}
        end
        
        def model_name, do: "my-model-v1"
        def avg_latency, do: 500  # milliseconds
        def max_tokens, do: 1024
      end
  """
  
  @doc """
  Calls the LLM provider with a command and tool definitions.
  
  ## Parameters
    * `command` - Natural language command string
    * `tools` - List of tool definition maps (from Tools.get_tool_definitions/0)
    * `opts` - Keyword list of options (provider-specific)
  
  ## Returns
    * `{:ok, tool_calls}` - List of tool call maps with :id, :name, :input
    * `{:error, reason}` - Error tuple with reason
  
  ## Tool Call Format
  
  Each tool call should be a map with:
  - `:id` - Unique identifier for the tool call (string)
  - `:name` - Name of the tool to execute (string)
  - `:input` - Map of parameters for the tool
  
  ## Examples
  
      iex> call("create a circle", tools, [])
      {:ok, [%{id: "call_123", name: "create_shape", input: %{"type" => "circle"}}]}
  """
  @callback call(
    command :: String.t(),
    tools :: list(map()),
    opts :: keyword()
  ) :: {:ok, list(map())} | {:error, term()}
  
  @doc """
  Returns the model name/identifier used by this provider.
  
  Used for logging, monitoring, and debugging purposes.
  """
  @callback model_name() :: String.t()
  
  @doc """
  Returns the average latency in milliseconds for this provider.
  
  Used for provider selection and performance monitoring.
  This should be an empirical average based on real-world usage.
  """
  @callback avg_latency() :: integer()
  
  @doc """
  Returns the maximum tokens this provider can handle.
  
  Used to prevent overly large requests that would fail.
  """
  @callback max_tokens() :: integer()
end
