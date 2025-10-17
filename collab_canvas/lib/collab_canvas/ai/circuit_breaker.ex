defmodule CollabCanvas.AI.CircuitBreaker do
  @moduledoc """
  Circuit breaker implementation for AI provider fault tolerance.
  
  Prevents cascading failures by temporarily disabling a provider after
  repeated failures, then allowing test requests to check if it has recovered.
  
  ## States
  
  - **Closed:** Normal operation, requests pass through
  - **Open:** Provider is failing, requests are rejected
  - **Half-Open:** Testing if provider has recovered
  
  ## Configuration
  
  - `threshold`: Number of failures before opening circuit (default: 5)
  - `timeout`: Time before attempting recovery (default: 60s)
  
  ## Usage
  
      # Before calling provider
      if CircuitBreaker.open?(:groq) do
        # Use fallback provider
      else
        case provider.call(...) do
          {:ok, result} -> 
            CircuitBreaker.record_success(:groq)
            {:ok, result}
          {:error, reason} ->
            CircuitBreaker.record_failure(:groq)
            {:error, reason}
        end
      end
  """
  
  use GenServer
  require Logger
  
  @type provider_name :: atom()
  @type state :: :closed | :open | :half_open
  
  defmodule State do
    @moduledoc false
    defstruct failures: %{},
              state: %{},
              opened_at: %{}
  end
  
  # Client API
  
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %State{}, name: __MODULE__)
  end
  
  @doc """
  Check if circuit is open for a provider.
  
  Returns true if the circuit is open (provider should not be called).
  """
  @spec open?(provider_name()) :: boolean()
  def open?(provider) do
    if enabled?() do
      GenServer.call(__MODULE__, {:is_open, provider})
    else
      false
    end
  end
  
  @doc """
  Record a successful provider call.
  """
  @spec record_success(provider_name()) :: :ok
  def record_success(provider) do
    if enabled?() do
      GenServer.cast(__MODULE__, {:success, provider})
    end
    :ok
  end
  
  @doc """
  Record a failed provider call.
  """
  @spec record_failure(provider_name()) :: :ok
  def record_failure(provider) do
    if enabled?() do
      GenServer.cast(__MODULE__, {:failure, provider})
    end
    :ok
  end
  
  @doc """
  Reset circuit breaker for a provider.
  """
  @spec reset(provider_name()) :: :ok
  def reset(provider) do
    GenServer.cast(__MODULE__, {:reset, provider})
  end
  
  @doc """
  Get current state for a provider.
  """
  @spec get_state(provider_name()) :: state()
  def get_state(provider) do
    GenServer.call(__MODULE__, {:get_state, provider})
  end
  
  # Server Callbacks
  
  @impl true
  def init(state) do
    {:ok, state}
  end
  
  @impl true
  def handle_call({:is_open, provider}, _from, state) do
    provider_state = Map.get(state.state, provider, :closed)
    
    case provider_state do
      :open ->
        # Check if timeout has elapsed
        opened_at = Map.get(state.opened_at, provider)
        if timeout_elapsed?(opened_at) do
          # Transition to half-open
          new_state = put_in(state.state[provider], :half_open)
          {:reply, false, new_state}
        else
          {:reply, true, state}
        end
      
      :half_open ->
        {:reply, false, state}
      
      :closed ->
        {:reply, false, state}
    end
  end
  
  @impl true
  def handle_call({:get_state, provider}, _from, state) do
    provider_state = Map.get(state.state, provider, :closed)
    {:reply, provider_state, state}
  end
  
  @impl true
  def handle_cast({:success, provider}, state) do
    current_state = Map.get(state.state, provider, :closed)
    
    new_state = case current_state do
      :half_open ->
        # Success in half-open -> close circuit
        Logger.info("[CircuitBreaker] #{provider} recovered, closing circuit")
        state
        |> put_in([Access.key(:state), provider], :closed)
        |> put_in([Access.key(:failures), provider], 0)
        |> Map.update!(:opened_at, &Map.delete(&1, provider))
      
      _ ->
        # Reset failure count
        put_in(state.failures[provider], 0)
    end
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_cast({:failure, provider}, state) do
    failures = Map.get(state.failures, provider, 0) + 1
    threshold = get_threshold()
    
    new_state = put_in(state.failures[provider], failures)
    
    if failures >= threshold do
      Logger.warning("[CircuitBreaker] #{provider} failed #{failures} times, opening circuit")
      
      new_state = new_state
      |> put_in([Access.key(:state), provider], :open)
      |> put_in([Access.key(:opened_at), provider], System.monotonic_time(:millisecond))
      
      {:noreply, new_state}
    else
      {:noreply, new_state}
    end
  end
  
  @impl true
  def handle_cast({:reset, provider}, state) do
    Logger.info("[CircuitBreaker] Manually resetting circuit for #{provider}")
    
    new_state = state
    |> put_in([Access.key(:failures), provider], 0)
    |> put_in([Access.key(:state), provider], :closed)
    |> Map.update!(:opened_at, &Map.delete(&1, provider))
    
    {:noreply, new_state}
  end
  
  # Private Functions
  
  defp enabled? do
    Application.get_env(:collab_canvas, [:ai, :circuit_breaker_enabled], true)
  end
  
  defp get_threshold do
    Application.get_env(:collab_canvas, [:ai, :circuit_breaker_threshold], 5)
  end
  
  defp get_timeout do
    Application.get_env(:collab_canvas, [:ai, :circuit_breaker_timeout], 60_000)
  end
  
  defp timeout_elapsed?(nil), do: true
  defp timeout_elapsed?(opened_at) do
    elapsed = System.monotonic_time(:millisecond) - opened_at
    elapsed >= get_timeout()
  end
end
