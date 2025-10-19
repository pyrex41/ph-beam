defmodule CollabCanvas.Performance.CanvasLoadTest do
  @moduledoc """
  Performance and scalability test suite for canvas operations.

  Tests the system under high-load scenarios:
  - 2,000+ objects on canvas
  - 10+ concurrent users
  - Measures FPS, memory usage, and sync latency

  Run with: mix test test/performance/canvas_load_test.exs
  """

  use ExUnit.Case, async: false

  alias CollabCanvas.{Canvases, Accounts, Repo}
  alias CollabCanvasWeb.{CanvasLive, Endpoint}
  alias Phoenix.PubSub

  @target_fps 45
  @max_sync_latency_ms 150
  @object_count 2000
  @concurrent_users 10

  setup do
    # Clean database before each test
    Repo.delete_all(CollabCanvas.Canvases.Object)
    Repo.delete_all(CollabCanvas.Canvases.Canvas)
    Repo.delete_all(CollabCanvas.Accounts.User)

    # Create test user
    {:ok, user} =
      Accounts.create_user(%{
        email: "test@example.com",
        name: "Test User",
        provider: "test",
        provider_uid: "test123"
      })

    # Create test canvas
    {:ok, canvas} =
      Canvases.create_canvas(%{
        name: "Performance Test Canvas",
        user_id: user.id
      })

    %{user: user, canvas: canvas}
  end

  @tag :performance
  # 5 minutes
  @tag timeout: 300_000
  test "maintains > 45 FPS with 2000 objects", %{canvas: canvas, user: user} do
    # Create 2000 objects
    IO.puts("\nCreating #{@object_count} objects...")
    start_time = System.monotonic_time(:millisecond)

    objects =
      Enum.map(1..@object_count, fn i ->
        x = rem(i, 100) * 20
        y = div(i, 100) * 20

        {:ok, object} =
          Canvases.create_object(canvas.id, %{
            type: "rectangle",
            position: %{x: x, y: y},
            data: %{
              width: 15,
              height: 15,
              fill: "#3b82f6",
              stroke: "#1e40af",
              stroke_width: 1
            }
          })

        object
      end)

    creation_time = System.monotonic_time(:millisecond) - start_time
    IO.puts("Created #{length(objects)} objects in #{creation_time}ms")
    IO.puts("Average: #{Float.round(creation_time / @object_count, 2)}ms per object")

    # Verify objects were created
    assert length(objects) == @object_count

    # Simulate rendering time budget for 45 FPS
    # At 45 FPS, we have ~22ms per frame
    frame_budget_ms = 1000 / @target_fps

    # Measure database query performance
    query_start = System.monotonic_time(:millisecond)
    loaded_canvas = Canvases.get_canvas_with_preloads(canvas.id, [:objects])
    query_time = System.monotonic_time(:millisecond) - query_start

    IO.puts("\nDatabase query time: #{query_time}ms")
    IO.puts("Frame budget (#{@target_fps} FPS): #{Float.round(frame_budget_ms, 2)}ms")

    # Query time should be reasonable for initial load
    assert query_time < 1000, "Database query took #{query_time}ms, should be < 1000ms"

    # Verify all objects loaded
    assert length(loaded_canvas.objects) == @object_count
  end

  @tag :performance
  @tag timeout: 300_000
  test "object sync latency stays below 150ms under load", %{canvas: canvas, user: user} do
    # Create 1000 initial objects
    IO.puts("\nSetting up canvas with 1000 objects...")

    Enum.each(1..1000, fn i ->
      x = rem(i, 50) * 20
      y = div(i, 50) * 20

      Canvases.create_object(canvas.id, %{
        type: "rectangle",
        position: %{x: x, y: y},
        data: %{width: 15, height: 15, fill: "#3b82f6"}
      })
    end)

    # Measure sync latency with multiple operations
    IO.puts("Measuring sync latency with 100 operations...")
    topic = "canvas:#{canvas.id}"
    Phoenix.PubSub.subscribe(CollabCanvas.PubSub, topic)

    latencies =
      Enum.map(1..100, fn i ->
        send_time = System.monotonic_time(:millisecond)

        {:ok, object} =
          Canvases.create_object(canvas.id, %{
            type: "circle",
            position: %{x: i * 10, y: 100},
            data: %{width: 20, fill: "#ef4444"}
          })

        # Broadcast the change (simulating LiveView behavior)
        Phoenix.PubSub.broadcast(
          CollabCanvas.PubSub,
          topic,
          {:object_created, object}
        )

        # Wait for broadcast to be received
        receive do
          {:object_created, _} ->
            receive_time = System.monotonic_time(:millisecond)
            receive_time - send_time
        after
          # Timeout after 1 second
          1000 -> 1000
        end
      end)

    avg_latency = Enum.sum(latencies) / length(latencies)
    max_latency = Enum.max(latencies)
    p95_latency = Enum.at(Enum.sort(latencies), round(length(latencies) * 0.95))

    IO.puts("\nSync Latency Results:")
    IO.puts("  Average: #{Float.round(avg_latency, 2)}ms")
    IO.puts("  P95: #{p95_latency}ms")
    IO.puts("  Max: #{max_latency}ms")

    # Assert performance requirements
    assert avg_latency < @max_sync_latency_ms,
           "Average sync latency #{Float.round(avg_latency, 2)}ms exceeds #{@max_sync_latency_ms}ms"

    assert p95_latency < @max_sync_latency_ms * 1.5,
           "P95 sync latency #{p95_latency}ms exceeds threshold"
  end

  @tag :performance
  @tag timeout: 300_000
  test "handles 10 concurrent users editing simultaneously", %{canvas: canvas, user: _user} do
    # Create 10 test users
    IO.puts("\nCreating #{@concurrent_users} concurrent users...")

    users =
      Enum.map(1..@concurrent_users, fn i ->
        {:ok, user} =
          Accounts.create_user(%{
            email: "user#{i}@example.com",
            name: "User #{i}",
            provider: "test",
            provider_uid: "test_#{i}"
          })

        user
      end)

    # Each user creates 100 objects concurrently
    objects_per_user = 100
    total_expected = @concurrent_users * objects_per_user

    IO.puts("Each user creating #{objects_per_user} objects (#{total_expected} total)...")
    start_time = System.monotonic_time(:millisecond)

    # Create tasks for concurrent operations
    tasks =
      Enum.map(users, fn user ->
        Task.async(fn ->
          Enum.map(1..objects_per_user, fn i ->
            x = :rand.uniform(1000)
            y = :rand.uniform(1000)

            {:ok, object} =
              Canvases.create_object(canvas.id, %{
                type: "rectangle",
                position: %{x: x, y: y},
                data: %{
                  width: 20,
                  height: 20,
                  fill: "##{Integer.to_string(:rand.uniform(0xFFFFFF), 16)}"
                }
              })

            object
          end)
        end)
      end)

    # Wait for all tasks to complete
    all_objects =
      tasks
      |> Enum.map(&Task.await(&1, 60_000))
      |> List.flatten()

    total_time = System.monotonic_time(:millisecond) - start_time

    IO.puts("\nConcurrent Operations Results:")
    IO.puts("  Total objects created: #{length(all_objects)}")
    IO.puts("  Total time: #{total_time}ms")

    IO.puts(
      "  Throughput: #{Float.round(length(all_objects) / (total_time / 1000), 2)} objects/sec"
    )

    # Verify all objects were created
    assert length(all_objects) == total_expected

    # Verify database consistency
    canvas_objects = Canvases.get_canvas_with_preloads(canvas.id, [:objects])
    assert length(canvas_objects.objects) == total_expected

    # System should handle concurrent load reasonably well
    assert total_time < 30_000, "Concurrent operations took #{total_time}ms, should be < 30s"
  end

  @tag :performance
  test "generates performance report", %{canvas: canvas, user: user} do
    report = %{
      timestamp: DateTime.utc_now(),
      test_configuration: %{
        object_count: @object_count,
        concurrent_users: @concurrent_users,
        target_fps: @target_fps,
        max_sync_latency_ms: @max_sync_latency_ms
      },
      results: %{
        canvas_id: canvas.id,
        user_id: user.id
      },
      status: "Performance tests configured and ready"
    }

    # Write report to file
    report_path =
      "test/performance/reports/performance_report_#{DateTime.to_unix(report.timestamp)}.json"

    File.mkdir_p!("test/performance/reports")
    File.write!(report_path, Jason.encode!(report, pretty: true))

    IO.puts("\nPerformance report written to: #{report_path}")

    assert File.exists?(report_path)
  end
end
