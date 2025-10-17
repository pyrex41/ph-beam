defmodule CollabCanvas.AI.ApiKeyValidator do
  @moduledoc """
  Validates AI provider API keys on application startup.
  
  Checks for presence and basic validity of API keys to catch
  configuration issues early rather than at runtime.
  
  ## Usage
  
  Called automatically during application startup if enabled in config:
  
      config :collab_canvas, :ai,
        validate_keys_on_startup: true
  """
  
  require Logger
  
  @doc """
  Validate all configured AI provider API keys.
  
  Returns :ok if all required keys are valid, or logs warnings for
  missing/invalid keys and returns :ok (non-blocking).
  """
  def validate_all do
    if enabled?() do
      Logger.info("[ApiKeyValidator] Validating AI provider API keys...")
      
      results = [
        validate_groq_key(),
        validate_claude_key()
      ]
      
      if Enum.all?(results, &(&1 == :ok)) do
        Logger.info("[ApiKeyValidator] ✓ All API keys validated successfully")
        :ok
      else
        Logger.warning("[ApiKeyValidator] ⚠ Some API keys are missing or invalid")
        :ok  # Non-blocking, allow app to start
      end
    else
      :ok
    end
  end
  
  @doc """
  Validate Groq API key.
  """
  def validate_groq_key do
    case System.get_env("GROQ_API_KEY") do
      nil ->
        Logger.warning("[ApiKeyValidator] ✗ GROQ_API_KEY not set")
        {:error, :missing}
      
      "" ->
        Logger.warning("[ApiKeyValidator] ✗ GROQ_API_KEY is empty")
        {:error, :empty}
      
      key ->
        if valid_groq_key_format?(key) do
          Logger.info("[ApiKeyValidator] ✓ GROQ_API_KEY is present (#{String.length(key)} chars)")
          :ok
        else
          Logger.warning("[ApiKeyValidator] ✗ GROQ_API_KEY appears invalid (expected format: gsk_...)")
          {:error, :invalid_format}
        end
    end
  end
  
  @doc """
  Validate Claude API key.
  """
  def validate_claude_key do
    case System.get_env("CLAUDE_API_KEY") do
      nil ->
        Logger.info("[ApiKeyValidator] ℹ CLAUDE_API_KEY not set (optional fallback)")
        :ok  # Claude is optional
      
      "" ->
        Logger.warning("[ApiKeyValidator] ✗ CLAUDE_API_KEY is empty")
        {:error, :empty}
      
      key ->
        if valid_claude_key_format?(key) do
          Logger.info("[ApiKeyValidator] ✓ CLAUDE_API_KEY is present (#{String.length(key)} chars)")
          :ok
        else
          Logger.warning("[ApiKeyValidator] ✗ CLAUDE_API_KEY appears invalid (expected format: sk-ant-...)")
          {:error, :invalid_format}
        end
    end
  end
  
  # Private Functions
  
  defp enabled? do
    Application.get_env(:collab_canvas, [:ai, :validate_keys_on_startup], true)
  end
  
  defp valid_groq_key_format?(key) do
    # Groq keys start with "gsk_"
    String.starts_with?(key, "gsk_") and String.length(key) > 20
  end
  
  defp valid_claude_key_format?(key) do
    # Claude keys start with "sk-ant-"
    String.starts_with?(key, "sk-ant-") and String.length(key) > 30
  end
end
