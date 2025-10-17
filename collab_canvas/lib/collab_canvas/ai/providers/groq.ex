defmodule CollabCanvas.AI.Providers.Groq do
  @moduledoc """
  Groq provider for fast inference with Llama 3.3 70B.
  
  Optimized for simple, single-turn commands with 300-500ms latency.
  Uses OpenAI-compatible API format.
  
  ## Performance Characteristics
  
  - **Model:** llama-3.3-70b-versatile
  - **Average Latency:** 300-500ms
  - **Best For:** Simple commands (create, move, delete, resize)
  - **Strengths:** Fast inference, cost-effective, high throughput
  - **Limitations:** Less nuanced reasoning than Claude
  
  ## Configuration
  
  Requires `GROQ_API_KEY` environment variable:
  
      export GROQ_API_KEY="gsk_..."
  
  ## Examples
  
      iex> tools = CollabCanvas.AI.Tools.get_tool_definitions()
      iex> Groq.call("create a red circle at 100,100", tools)
      {:ok, [%{id: "call_xyz", name: "create_shape", input: %{...}}]}
  """
  
  @behaviour CollabCanvas.AI.Provider
  
  require Logger
  
  @api_url "https://api.groq.com/openai/v1/chat/completions"
  @model "llama-3.3-70b-versatile"
  
  @impl true
  def call(command, tools, _opts \\ []) do
    api_key = get_api_key()
    
    if is_nil(api_key) or api_key == "" do
      {:error, :missing_api_key}
    else
      body = build_request_body(command, tools)
      headers = build_headers(api_key)
      
      Logger.debug("Calling Groq API with command: #{String.slice(command, 0..50)}...")
      
      case Req.post(@api_url, json: body, headers: headers) do
        {:ok, %{status: 200, body: response}} ->
          Logger.debug("Groq API response received successfully")
          parse_response(response)
          
        {:ok, %{status: status, body: error_body}} ->
          Logger.error("Groq API error: #{status} - #{inspect(error_body)}")
          {:error, {:api_error, status, error_body}}
          
        {:error, reason} ->
          Logger.error("Groq API request failed: #{inspect(reason)}")
          {:error, {:request_failed, reason}}
      end
    end
  end
  
  @impl true
  def model_name, do: @model
  
  @impl true
  def avg_latency, do: 400  # 400ms average
  
  @impl true
  def max_tokens, do: 1024
  
  # Private functions
  
  defp get_api_key do
    System.get_env("GROQ_API_KEY")
  end
  
  defp build_headers(api_key) do
    [
      {"authorization", "Bearer #{api_key}"},
      {"content-type", "application/json"}
    ]
  end
  
  defp build_request_body(command, tools) do
    %{
      model: @model,
      messages: [
        %{
          role: "system",
          content: """
          You are a canvas design assistant. Use the provided tools to execute user commands precisely.
          
          Guidelines:
          - Always use exact coordinates and dimensions provided by the user
          - For colors, accept common names (red, blue) or hex codes (#FF0000)
          - Default to reasonable sizes if not specified (e.g., 100x100 for shapes)
          - When creating multiple objects, space them appropriately
          - Execute all requested operations in a single response
          """
        },
        %{
          role: "user",
          content: command
        }
      ],
      tools: convert_tools_to_openai_format(tools),
      tool_choice: "auto",
      temperature: 0.1,  # Low temperature for consistency
      max_tokens: max_tokens()
    }
  end
  
  defp convert_tools_to_openai_format(tools) do
    Enum.map(tools, fn tool ->
      %{
        type: "function",
        function: %{
          name: tool.name,
          description: tool.description,
          parameters: tool.input_schema
        }
      }
    end)
  end
  
  defp parse_response(%{"choices" => [%{"message" => message} | _]}) do
    tool_calls = Map.get(message, "tool_calls", [])
    
    if Enum.empty?(tool_calls) do
      # No tool calls - just text response
      Logger.debug("Groq returned text-only response (no tool calls)")
      {:ok, []}
    else
      parsed_calls = Enum.map(tool_calls, &parse_tool_call/1)
      Logger.debug("Groq returned #{length(parsed_calls)} tool call(s)")
      {:ok, parsed_calls}
    end
  end
  
  defp parse_response(response) do
    Logger.error("Unexpected Groq response format: #{inspect(response)}")
    {:error, :invalid_response_format}
  end
  
  defp parse_tool_call(tool_call) do
    function = tool_call["function"]
    
    # Parse arguments JSON string to map
    arguments = case Jason.decode(function["arguments"]) do
      {:ok, args} -> args
      {:error, _} -> 
        Logger.warning("Failed to parse tool call arguments: #{function["arguments"]}")
        %{}
    end
    
    %{
      id: tool_call["id"],
      name: function["name"],
      input: arguments
    }
  end
end
