defmodule CollabCanvas.PixelDataStore do
  @moduledoc """
  Temporary storage for pixel art data before it's added to canvas.

  Uses ETS for fast in-memory storage with automatic cleanup.
  Data is stored with a TTL of 5 minutes.
  """
  use GenServer

  @cleanup_interval :timer.minutes(1)
  @ttl :timer.minutes(5)

  # Client API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc """
  Store pixel data for a canvas and user.
  Returns a unique key to retrieve the data.
  """
  def store(canvas_id, user_id, pixel_data) do
    key = generate_key(canvas_id, user_id)
    GenServer.call(__MODULE__, {:store, key, pixel_data})
    key
  end

  @doc """
  Retrieve and remove pixel data for a canvas and user.
  Returns nil if not found or expired.
  """
  def pop(canvas_id, user_id) do
    key = generate_key(canvas_id, user_id)
    GenServer.call(__MODULE__, {:pop, key})
  end

  # Server Callbacks

  @impl true
  def init(:ok) do
    table = :ets.new(:pixel_data, [:set, :private])
    schedule_cleanup()
    {:ok, %{table: table}}
  end

  @impl true
  def handle_call({:store, key, pixel_data}, _from, state) do
    timestamp = System.monotonic_time(:millisecond)
    :ets.insert(state.table, {key, pixel_data, timestamp})
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:pop, key}, _from, state) do
    case :ets.lookup(state.table, key) do
      [{^key, pixel_data, timestamp}] ->
        # Check if expired
        now = System.monotonic_time(:millisecond)
        if now - timestamp < @ttl do
          :ets.delete(state.table, key)
          {:reply, {:ok, pixel_data}, state}
        else
          :ets.delete(state.table, key)
          {:reply, {:error, :expired}, state}
        end

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_info(:cleanup, state) do
    now = System.monotonic_time(:millisecond)

    # Delete expired entries
    :ets.select_delete(state.table, [
      {
        {:"$1", :"$2", :"$3"},
        [{:<, {:+, :"$3", @ttl}, now}],
        [true]
      }
    ])

    schedule_cleanup()
    {:noreply, state}
  end

  # Private Functions

  defp generate_key(canvas_id, user_id) do
    "#{canvas_id}_#{user_id}_#{System.unique_integer([:positive])}"
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end
end
