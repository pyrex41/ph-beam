defmodule CollabCanvas.AI.Providers.Claude do
  @moduledoc """
  Anthropic Claude provider for complex reasoning tasks.
  
  Used as fallback when Groq fails or for complex multi-step commands
  that require superior reasoning capabilities.
  
  ## Performance Characteristics
  
  - **Model:** claude-3-5-sonnet-20241022
  - **Average Latency:** 1.5-2.0s
  - **Best For:** Complex components, multi-step operations, ambiguous commands
  - **Strengths:** Superior reasoning, better context understanding
  - **Limitations:** Higher latency, higher cost
  
  ## Configuration
  
  Requires `CLAUDE_API_KEY` environment variable:
  
      export CLAUDE_API_KEY="sk-ant-..."
  
  ## Examples
  
      iex> tools = CollabCanvas.AI.Tools.get_tool_definitions()
      iex> Claude.call("create a login form with email and password", tools)
      {:ok, [%{id: "toolu_xyz", name: "create_component", input: %{...}}]}
  """
  
  @behaviour CollabCanvas.AI.Provider
  
  require Logger
  
  @api_url "https://api.anthropic.com/v1/messages"
  @model "claude-3-5-sonnet-20241022"
  @api_version "2023-06-01"
  
  @impl true
  def call(command, tools, opts \\ []) do
    api_key = get_api_key()
    
    if is_nil(api_key) or api_key == "" do
      {:error, :missing_api_key}
    else
      headers = [
        {"x-api-key", api_key},
        {"anthropic-version", @api_version},
        {"content-type", "application/json"}
      ]
      
      body = %{
        model: @model,
        max_tokens: max_tokens(),
        tools: tools,
        messages: [
          %{
            role: "user",
            content: command
          }
        ]
      }
      
      timeout = get_timeout(opts)
      
      Logger.debug("Calling Claude API with command: #{String.slice(command, 0..50)}...")
      
      case Req.post(@api_url, json: body, headers: headers, receive_timeout: timeout) do
        {:ok, %{status: 200, body: response}} ->
          Logger.debug("Claude API response received successfully")
          parse_response(response)
          
        {:ok, %{status: status, body: error_body}} ->
          Logger.error("Claude API error: #{status} - #{inspect(error_body)}")
          {:error, {:api_error, status, error_body}}
          
        {:error, reason} ->
          Logger.error("Claude API request failed: #{inspect(reason)}")
          {:error, {:request_failed, reason}}
      end
    end
  end
  
  @impl true
  def model_name, do: @model
  
  @impl true
  def avg_latency, do: 1800  # 1.8s average
  
  @impl true
  def max_tokens, do: 1024
  
  # Private functions
  
  defp get_api_key do
    System.get_env("CLAUDE_API_KEY")
  end
  
  defp parse_response(%{"content" => content, "stop_reason" => stop_reason}) do
    case stop_reason do
      "tool_use" ->
        tool_calls =
          content
          |> Enum.filter(fn item -> item["type"] == "tool_use" end)
          |> Enum.map(fn tool_use ->
            %{
              id: tool_use["id"],
              name: tool_use["name"],
              input: tool_use["input"]
            }
          end)
        
        Logger.debug("Claude returned #{length(tool_calls)} tool call(s)")
        {:ok, tool_calls}
      
      "end_turn" ->
        Logger.debug("Claude returned text-only response (no tool calls)")
        {:ok, []}
      
      other ->
        Logger.warning("Unexpected stop_reason: #{other}")
        {:ok, []}
    end
  end
  
  defp parse_response(response) do
    Logger.error("Unexpected Claude response format: #{inspect(response)}")
    {:error, :invalid_response_format}
  end
  
  defp get_timeout(opts) do
    Keyword.get(opts, :timeout) || 
      Application.get_env(:collab_canvas, [:ai, :claude_timeout], 10_000)
  end
end
