defmodule CollabCanvas.Performance.BatchInsertBenchmark do
  @moduledoc """
  Performance benchmarks for create_objects_batch/2 function.

  Run with:
      mix run test/performance/batch_insert_benchmark.exs

  This script validates the key demo feature performance targets:
  - 100 objects in < 1 second
  - 500 objects in < 2 seconds
  - 600 objects for demo scenarios (instantaneous feel)
  """

  alias CollabCanvas.Canvases
  alias CollabCanvas.Accounts
  alias CollabCanvas.Repo

  require Logger

  def run do
    # Start the application if not already started
    {:ok, _} = Application.ensure_all_started(:collab_canvas)

    # Create test data
    {:ok, user} = Accounts.create_user(%{email: "bench@example.com", name: "Benchmark User"})
    {:ok, canvas} = Canvases.create_canvas(user.id, "Benchmark Canvas")

    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("BATCH INSERT PERFORMANCE BENCHMARK")
    IO.puts("Testing create_objects_batch/2 performance")
    IO.puts(String.duplicate("=", 80) <> "\n")

    # Run benchmarks
    benchmark_100_objects(canvas.id)
    benchmark_500_objects(canvas.id)
    benchmark_600_objects(canvas.id)
    benchmark_scaling(canvas.id)

    # Cleanup
    Canvases.delete_canvas(canvas.id)

    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("BENCHMARK COMPLETE")
    IO.puts(String.duplicate("=", 80) <> "\n")
  end

  defp benchmark_100_objects(canvas_id) do
    IO.puts("TEST: Create 100 objects (target: < 1 second)")
    IO.puts(String.duplicate("-", 80))

    attrs_list =
      Enum.map(1..100, fn i ->
        %{
          type: "rectangle",
          position: %{x: rem(i, 10) * 100, y: div(i, 10) * 100},
          data: Jason.encode!(%{width: 50, height: 50, color: "#FF0000"}),
          z_index: i * 1.0
        }
      end)

    {time_us, {:ok, objects}} =
      :timer.tc(fn -> Canvases.create_objects_batch(canvas_id, attrs_list) end)

    time_s = time_us / 1_000_000
    avg_us = time_us / length(objects)

    IO.puts("  Created: #{length(objects)} objects")
    IO.puts("  Time: #{format_time(time_s)} seconds")
    IO.puts("  Average: #{Float.round(avg_us, 2)} μs per object")
    IO.puts("  Status: #{if time_s < 1.0, do: "✓ PASS", else: "✗ FAIL"}")

    # Cleanup
    Canvases.delete_canvas_objects(canvas_id)

    IO.puts("")
  end

  defp benchmark_500_objects(canvas_id) do
    IO.puts("TEST: Create 500 objects (target: < 2 seconds)")
    IO.puts(String.duplicate("-", 80))

    attrs_list =
      Enum.map(1..500, fn i ->
        %{
          type: Enum.random(["rectangle", "circle", "ellipse", "text"]),
          position: %{x: rem(i, 20) * 50, y: div(i, 20) * 50},
          data:
            Jason.encode!(%{
              width: 40,
              height: 40,
              color: Enum.random(["#FF0000", "#00FF00", "#0000FF"])
            }),
          z_index: i * 1.0
        }
      end)

    {time_us, {:ok, objects}} =
      :timer.tc(fn -> Canvases.create_objects_batch(canvas_id, attrs_list) end)

    time_s = time_us / 1_000_000
    avg_us = time_us / length(objects)

    IO.puts("  Created: #{length(objects)} objects")
    IO.puts("  Time: #{format_time(time_s)} seconds")
    IO.puts("  Average: #{Float.round(avg_us, 2)} μs per object")
    IO.puts("  Status: #{if time_s < 2.0, do: "✓ PASS", else: "✗ FAIL"}")

    # Cleanup
    Canvases.delete_canvas_objects(canvas_id)

    IO.puts("")
  end

  defp benchmark_600_objects(canvas_id) do
    IO.puts("TEST: Create 600 objects - DEMO FEATURE (target: instantaneous feel)")
    IO.puts(String.duplicate("-", 80))

    attrs_list =
      Enum.map(1..600, fn i ->
        %{
          type: Enum.random(["rectangle", "circle", "star", "triangle", "ellipse"]),
          position: %{x: rem(i, 30) * 50, y: div(i, 30) * 50},
          data:
            Jason.encode!(%{
              width: 30 + :rand.uniform(20),
              height: 30 + :rand.uniform(20),
              color: Enum.random(["#FF0000", "#00FF00", "#0000FF", "#FFFF00", "#FF00FF"])
            }),
          z_index: i * 1.0
        }
      end)

    {time_us, {:ok, objects}} =
      :timer.tc(fn -> Canvases.create_objects_batch(canvas_id, attrs_list) end)

    time_s = time_us / 1_000_000
    avg_us = time_us / length(objects)
    objects_per_second = length(objects) / time_s

    IO.puts("  Created: #{length(objects)} objects")
    IO.puts("  Time: #{format_time(time_s)} seconds")
    IO.puts("  Average: #{Float.round(avg_us, 2)} μs per object")
    IO.puts("  Throughput: #{Float.round(objects_per_second, 0)} objects/second")
    IO.puts("  Status: #{if time_s < 3.0, do: "✓ PASS (Demo ready!)", else: "✗ FAIL"}")

    # Cleanup
    Canvases.delete_canvas_objects(canvas_id)

    IO.puts("")
  end

  defp benchmark_scaling(canvas_id) do
    IO.puts("TEST: Scaling characteristics (10, 50, 100, 200, 400)")
    IO.puts(String.duplicate("-", 80))

    sizes = [10, 50, 100, 200, 400]

    results =
      Enum.map(sizes, fn size ->
        attrs_list =
          Enum.map(1..size, fn i ->
            %{
              type: "rectangle",
              position: %{x: rem(i, 10) * 50, y: div(i, 10) * 50},
              data: Jason.encode!(%{width: 40, height: 40}),
              z_index: i * 1.0
            }
          end)

        {time_us, {:ok, _objects}} =
          :timer.tc(fn -> Canvases.create_objects_batch(canvas_id, attrs_list) end)

        time_s = time_us / 1_000_000

        # Cleanup after each test
        Canvases.delete_canvas_objects(canvas_id)

        {size, time_s, time_us / size}
      end)

    IO.puts("\n  Size | Time (s) | Avg (μs/obj) | Objects/sec")
    IO.puts("  " <> String.duplicate("-", 60))

    Enum.each(results, fn {size, time_s, avg_us} ->
      objects_per_sec = size / time_s

      IO.puts(
        "  #{String.pad_leading(to_string(size), 4)} | " <>
          "#{String.pad_leading(format_time(time_s), 8)} | " <>
          "#{String.pad_leading(Float.to_string(Float.round(avg_us, 2)), 12)} | " <>
          "#{Float.round(objects_per_sec, 0)}"
      )
    end)

    IO.puts("")

    # Calculate scaling factor (should be roughly linear)
    [{size1, time1, _}, {size2, time2, _} | _] = results
    scaling_factor = time2 / time1 / (size2 / size1)
    linearity_score = 1.0 - abs(1.0 - scaling_factor)

    IO.puts(
      "  Linearity score: #{Float.round(linearity_score * 100, 1)}% (1.0 = perfectly linear)"
    )

    IO.puts("")
  end

  defp format_time(seconds) when seconds < 0.001, do: "#{Float.round(seconds * 1_000_000, 0)}μs"
  defp format_time(seconds) when seconds < 1.0, do: "#{Float.round(seconds * 1000, 2)}ms"
  defp format_time(seconds), do: "#{Float.round(seconds, 3)}s"
end

# Run the benchmark when script is executed
CollabCanvas.Performance.BatchInsertBenchmark.run()
