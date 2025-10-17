defmodule CollabCanvas.AI.ProviderHealth do
  @moduledoc """
  Health check system for AI providers.
  
  Periodically tests provider availability and tracks health status.
  Supports OpenAI, Groq, and Claude providers.
  
  ## Health Status
  
  - `:healthy` - Provider responding normally
  - `:degraded` - Provider slow but functional
  - `:unhealthy` - Provider failing or unavailable
  - `:unknown` - Not yet checked
  
  ## Usage
  
      # Check current health
      ProviderHealth.get_status(:groq)
      # => :healthy
      
      # Manually trigger health check
      ProviderHealth.check_provider(:groq)
  """
  
  use GenServer
  require Logger
  
  alias CollabCanvas.AI.Providers.{Groq, Claude}
  
  defmodule State do
    @moduledoc false
    defstruct status: %{},
              last_check: %{},
              response_times: %{}
  end
  
  @type health_status :: :healthy | :degraded | :unhealthy | :unknown
  
  # Client API
  
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %State{}, name: __MODULE__)
  end
  
  @doc """
  Get current health status for a provider.
  """
  @spec get_status(atom()) :: health_status()
  def get_status(provider) do
    GenServer.call(__MODULE__, {:get_status, provider})
  end
  
  @doc """
  Get last response time for a provider.
  """
  def get_response_time(provider) do
    GenServer.call(__MODULE__, {:get_response_time, provider})
  end
  
  @doc """
  Manually trigger health check for a provider.
  """
  def check_provider(provider) do
    GenServer.cast(__MODULE__, {:check, provider})
  end
  
  @doc """
  Check all configured providers.
  """
  def check_all do
    GenServer.cast(__MODULE__, :check_all)
  end
  
  # Server Callbacks
  
  @impl true
  def init(state) do
    if enabled?() do
      # Initial health check
      send(self(), :check_all)
      # Schedule periodic checks
      schedule_health_check()
    end
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:get_status, provider}, _from, state) do
    status = Map.get(state.status, provider, :unknown)
    {:reply, status, state}
  end
  
  @impl true
  def handle_call({:get_response_time, provider}, _from, state) do
    time = Map.get(state.response_times, provider)
    {:reply, time, state}
  end
  
  @impl true
  def handle_cast({:check, provider}, state) do
    new_state = perform_health_check(provider, state)
    {:noreply, new_state}
  end
  
  @impl true
  def handle_cast(:check_all, state) do
    providers = [:groq, :claude, :openai]
    
    new_state = Enum.reduce(providers, state, fn provider, acc ->
      perform_health_check(provider, acc)
    end)
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info(:check_all, state) do
    send(self(), {:check_all_async, self()})
    schedule_health_check()
    {:noreply, state}
  end
  
  @impl true
  def handle_info({:check_all_async, _pid}, state) do
    # Perform checks asynchronously
    GenServer.cast(self(), :check_all)
    {:noreply, state}
  end
  
  # Private Functions
  
  defp perform_health_check(provider, state) do
    Logger.debug("[ProviderHealth] Checking #{provider}")
    
    start_time = System.monotonic_time(:millisecond)
    
    {status, response_time} = case check_provider_api(provider) do
      {:ok, duration} ->
        cond do
          duration < 1000 -> {:healthy, duration}
          duration < 3000 -> {:degraded, duration}
          true -> {:unhealthy, duration}
        end
      
      {:error, _reason} ->
        {:unhealthy, nil}
    end
    
    log_health_status(provider, status, response_time)
    
    state
    |> put_in([Access.key(:status), provider], status)
    |> put_in([Access.key(:last_check), provider], System.monotonic_time(:millisecond))
    |> put_in([Access.key(:response_times), provider], response_time)
  end
  
  defp check_provider_api(:groq) do
    if api_key_present?("GROQ_API_KEY") do
      test_provider(Groq, "test health check")
    else
      Logger.debug("[ProviderHealth] Groq API key not configured")
      {:error, :no_api_key}
    end
  end
  
  defp check_provider_api(:claude) do
    if api_key_present?("CLAUDE_API_KEY") do
      test_provider(Claude, "test health check")
    else
      Logger.debug("[ProviderHealth] Claude API key not configured")
      {:error, :no_api_key}
    end
  end
  
  defp check_provider_api(:openai) do
    # OpenAI support can be added when implemented
    Logger.debug("[ProviderHealth] OpenAI provider not yet implemented")
    {:error, :not_implemented}
  end
  
  defp test_provider(provider_module, test_command) do
    start = System.monotonic_time(:millisecond)
    
    # Use a simple test command
    case provider_module.call(test_command, [], timeout: 3000) do
      {:ok, _} ->
        duration = System.monotonic_time(:millisecond) - start
        {:ok, duration}
      
      {:error, :missing_api_key} ->
        {:error, :no_api_key}
      
      {:error, reason} ->
        {:error, reason}
    end
  rescue
    _ -> {:error, :exception}
  end
  
  defp api_key_present?(env_var) do
    case System.get_env(env_var) do
      nil -> false
      "" -> false
      _key -> true
    end
  end
  
  defp log_health_status(provider, status, response_time) do
    case status do
      :healthy ->
        Logger.info("[ProviderHealth] #{provider} is healthy (#{response_time}ms)")
      
      :degraded ->
        Logger.warning("[ProviderHealth] #{provider} is degraded (#{response_time}ms)")
      
      :unhealthy ->
        Logger.error("[ProviderHealth] #{provider} is unhealthy")
      
      :unknown ->
        Logger.debug("[ProviderHealth] #{provider} status unknown")
    end
  end
  
  defp enabled? do
    Application.get_env(:collab_canvas, [:ai, :health_check_enabled], true)
  end
  
  defp schedule_health_check do
    interval = Application.get_env(:collab_canvas, [:ai, :health_check_interval], 300_000)
    Process.send_after(self(), :check_all, interval)
  end
end
