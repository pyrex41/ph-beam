defmodule CollabCanvas.AI.RateLimiter do
  @moduledoc """
  Token bucket rate limiter for AI provider requests.
  
  Prevents hitting API rate limits by tracking requests per provider
  and enforcing configurable limits.
  
  ## Configuration
  
  - `max_requests_per_minute`: Maximum requests allowed (default: 60)
  - `rate_limit_window_ms`: Time window in milliseconds (default: 60000)
  
  ## Usage
  
      case RateLimiter.check_rate(:groq) do
        :ok ->
          # Proceed with request
          provider.call(...)
        {:error, :rate_limited} ->
          # Wait or use fallback
      end
  """
  
  use GenServer
  require Logger
  
  defmodule State do
    @moduledoc false
    defstruct requests: %{}
  end
  
  # Client API
  
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %State{}, name: __MODULE__)
  end
  
  @doc """
  Check if request is within rate limit.
  
  Returns :ok if allowed, {:error, :rate_limited} if limit exceeded.
  """
  def check_rate(provider) do
    GenServer.call(__MODULE__, {:check_rate, provider})
  end
  
  @doc """
  Get current request count for a provider.
  """
  def get_count(provider) do
    GenServer.call(__MODULE__, {:get_count, provider})
  end
  
  @doc """
  Reset rate limit for a provider.
  """
  def reset(provider) do
    GenServer.cast(__MODULE__, {:reset, provider})
  end
  
  # Server Callbacks
  
  @impl true
  def init(state) do
    # Schedule cleanup of old requests
    schedule_cleanup()
    {:ok, state}
  end
  
  @impl true
  def handle_call({:check_rate, provider}, _from, state) do
    now = System.monotonic_time(:millisecond)
    window = get_rate_limit_window()
    max_requests = get_max_requests()
    
    # Get recent requests within window
    recent_requests = state.requests
    |> Map.get(provider, [])
    |> Enum.filter(fn timestamp -> now - timestamp < window end)
    
    if length(recent_requests) >= max_requests do
      Logger.warning("[RateLimiter] Rate limit exceeded for #{provider}: #{length(recent_requests)}/#{max_requests}")
      {:reply, {:error, :rate_limited}, state}
    else
      # Add current request
      new_requests = [now | recent_requests]
      new_state = put_in(state.requests[provider], new_requests)
      {:reply, :ok, new_state}
    end
  end
  
  @impl true
  def handle_call({:get_count, provider}, _from, state) do
    now = System.monotonic_time(:millisecond)
    window = get_rate_limit_window()
    
    count = state.requests
    |> Map.get(provider, [])
    |> Enum.count(fn timestamp -> now - timestamp < window end)
    
    {:reply, count, state}
  end
  
  @impl true
  def handle_cast({:reset, provider}, state) do
    new_state = Map.update!(state, :requests, &Map.delete(&1, provider))
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info(:cleanup, state) do
    now = System.monotonic_time(:millisecond)
    window = get_rate_limit_window()
    
    # Remove old requests from all providers
    new_requests = state.requests
    |> Enum.map(fn {provider, timestamps} ->
      recent = Enum.filter(timestamps, fn ts -> now - ts < window end)
      {provider, recent}
    end)
    |> Enum.into(%{})
    
    schedule_cleanup()
    {:noreply, %{state | requests: new_requests}}
  end
  
  # Private Functions
  
  defp get_max_requests do
    Application.get_env(:collab_canvas, [:ai, :max_requests_per_minute], 60)
  end
  
  defp get_rate_limit_window do
    Application.get_env(:collab_canvas, [:ai, :rate_limit_window_ms], 60_000)
  end
  
  defp schedule_cleanup do
    # Cleanup every minute
    Process.send_after(self(), :cleanup, 60_000)
  end
end
