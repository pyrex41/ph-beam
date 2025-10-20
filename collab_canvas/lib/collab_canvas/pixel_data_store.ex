defmodule CollabCanvas.PixelDataStore do
  @moduledoc """
  Temporary storage for pixel art data before it's added to canvas.

  Uses ETS for fast in-memory storage with automatic cleanup.
  Data is stored with a TTL of 5 minutes.
  Max entries limit prevents unbounded memory growth.
  """
  use GenServer

  require Logger

  @cleanup_interval :timer.minutes(1)
  @ttl :timer.minutes(5)
  @max_entries 1000

  # Client API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc """
  Store pixel data for a canvas and user.
  Returns :ok on success or {:error, reason} on failure.
  """
  def store(canvas_id, user_id, pixel_data) do
    key = generate_key(canvas_id, user_id)
    GenServer.call(__MODULE__, {:store, key, pixel_data})
  end

  @doc """
  Retrieve and remove pixel data for a canvas and user.
  Returns {:ok, pixel_data} or {:error, reason}.
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
    # Check if table is at max capacity
    table_size = :ets.info(state.table, :size)

    if table_size >= @max_entries do
      Logger.warning("PixelDataStore at max capacity (#{@max_entries} entries). Rejecting new entry.")
      {:reply, {:error, :table_full}, state}
    else
      timestamp = System.monotonic_time(:millisecond)
      :ets.insert(state.table, {key, pixel_data, timestamp})

      # Log memory usage periodically (every 100 entries)
      if rem(table_size + 1, 100) == 0 do
        memory_words = :ets.info(state.table, :memory)
        memory_mb = memory_words * :erlang.system_info(:wordsize) / 1_024 / 1_024

        Logger.info(
          "PixelDataStore stats: #{table_size + 1} entries, #{Float.round(memory_mb, 2)} MB"
        )
      end

      {:reply, :ok, state}
    end
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
    table_size_before = :ets.info(state.table, :size)

    # Delete expired entries
    deleted_count = :ets.select_delete(state.table, [
      {
        {:"$1", :"$2", :"$3"},
        [{:<, {:+, :"$3", @ttl}, now}],
        [true]
      }
    ])

    # Log cleanup results if any entries were removed
    if deleted_count > 0 do
      table_size_after = :ets.info(state.table, :size)
      memory_words = :ets.info(state.table, :memory)
      memory_mb = memory_words * :erlang.system_info(:wordsize) / 1_024 / 1_024

      Logger.info(
        "PixelDataStore cleanup: removed #{deleted_count} expired entries, " <>
        "#{table_size_after} entries remaining, #{Float.round(memory_mb, 2)} MB"
      )
    end

    schedule_cleanup()
    {:noreply, state}
  end

  # Private Functions

  defp generate_key(canvas_id, user_id) do
    # Use tuple key to avoid collisions from underscores in IDs
    {canvas_id, user_id}
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end
end
