# Performance test for batch object creation
# Run with: mix run test_batch_performance.exs

alias CollabCanvas.Accounts
alias CollabCanvas.Canvases
alias CollabCanvas.Repo

# Create test user and canvas
user_attrs = %{
  email: "batch_test@example.com",
  name: "Batch Test",
  provider: "auth0",
  provider_id: "auth0|batch_test"
}

user =
  case Repo.get_by(Accounts.User, email: user_attrs.email) do
    nil ->
      %Accounts.User{}
      |> Accounts.User.changeset(user_attrs)
      |> Repo.insert!()

    existing ->
      existing
  end

{:ok, canvas} = Canvases.create_canvas(user.id, "Performance Test Canvas")

IO.puts("\n=== Batch Creation Performance Test ===\n")

# Test 1: 10 objects (target: <2s)
IO.puts("Test 1: Creating 10 objects...")

attrs_list_10 =
  Enum.map(0..9, fn i ->
    %{
      type: "rectangle",
      position: %{x: i * 60, y: 100},
      data: Jason.encode!(%{width: 50, height: 50, color: "#FF0000"})
    }
  end)

{time_10, {:ok, objects_10}} =
  :timer.tc(fn ->
    Canvases.create_objects_batch(canvas.id, attrs_list_10)
  end)

time_10_ms = time_10 / 1000
IO.puts("✓ Created #{length(objects_10)} objects in #{Float.round(time_10_ms, 2)}ms")

if time_10_ms < 2000 do
  IO.puts("✅ PASS: Performance target met (<2s)")
else
  IO.puts("⚠️  WARNING: Exceeded 2s target (#{Float.round(time_10_ms, 2)}ms)")
end

# Test 2: 50 objects
IO.puts("\nTest 2: Creating 50 objects...")

attrs_list_50 =
  Enum.map(0..49, fn i ->
    %{
      type: "circle",
      position: %{x: rem(i, 10) * 60, y: div(i, 10) * 60 + 300},
      data: Jason.encode!(%{width: 40, height: 40, color: "#00FF00"})
    }
  end)

{time_50, {:ok, objects_50}} =
  :timer.tc(fn ->
    Canvases.create_objects_batch(canvas.id, attrs_list_50)
  end)

time_50_ms = time_50 / 1000
IO.puts("✓ Created #{length(objects_50)} objects in #{Float.round(time_50_ms, 2)}ms")

# Test 3: 100 objects
IO.puts("\nTest 3: Creating 100 objects...")

attrs_list_100 =
  Enum.map(0..99, fn i ->
    %{
      type: "rectangle",
      position: %{x: rem(i, 10) * 60, y: div(i, 10) * 60 + 700},
      data: Jason.encode!(%{width: 50, height: 50, color: "#0000FF"})
    }
  end)

{time_100, {:ok, objects_100}} =
  :timer.tc(fn ->
    Canvases.create_objects_batch(canvas.id, attrs_list_100)
  end)

time_100_ms = time_100 / 1000
IO.puts("✓ Created #{length(objects_100)} objects in #{Float.round(time_100_ms, 2)}ms")

# Calculate throughput
IO.puts("\n=== Performance Summary ===")

IO.puts(
  "10 objects:  #{Float.round(time_10_ms, 2)}ms (#{Float.round(10000 / time_10_ms, 2)} obj/sec)"
)

IO.puts(
  "50 objects:  #{Float.round(time_50_ms, 2)}ms (#{Float.round(50000 / time_50_ms, 2)} obj/sec)"
)

IO.puts(
  "100 objects: #{Float.round(time_100_ms, 2)}ms (#{Float.round(100_000 / time_100_ms, 2)} obj/sec)"
)

# Cleanup
Canvases.delete_canvas(canvas.id)
IO.puts("\n✓ Test cleanup complete")
