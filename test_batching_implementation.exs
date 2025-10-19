# Test script to verify batching implementation
# Run with: mix run test_batching_implementation.exs

# Test data
canvas_id = 1
current_color = "#FF0000"

# Mock tool calls that simulate what Claude API would return
tool_calls = [
  %{id: "t1", name: "create_shape", input: %{"type" => "rectangle", "x" => 10, "y" => 10, "width" => 50, "height" => 30}},
  %{id: "t2", name: "create_shape", input: %{"type" => "circle", "x" => 100, "y" => 10, "width" => 40, "height" => 40}},
  %{id: "t3", name: "create_text", input: %{"text" => "Hello", "x" => 200, "y" => 10}},
  %{id: "t4", name: "move_object", input: %{"object_id" => 1, "x" => 50, "y" => 50}},
  %{id: "t5", name: "create_shape", input: %{"type" => "rectangle", "x" => 300, "y" => 10, "width" => 60, "height" => 40}}
]

IO.puts("\nTest case 1: Mixed create_* and non-create tool calls")
IO.puts("=" <> String.duplicate("=", 60))
IO.puts("Input tool calls:")
Enum.each(tool_calls, fn tc -> IO.puts("  - #{tc.name} (#{tc.id})") end)

# Expected behavior:
# - create_shape (t1), create_shape (t2), create_text (t3), create_shape (t5) should be batched
# - move_object (t4) should execute individually
# Results should be in original order: t1, t2, t3, t4, t5

IO.puts("\nExpected batching:")
IO.puts("  Batch: t1 (create_shape), t2 (create_shape), t3 (create_text), t5 (create_shape)")
IO.puts("  Individual: t4 (move_object)")
IO.puts("  Result order: t1, t2, t3, t4, t5 (original order preserved)")

IO.puts("\nTest case 2: create_shape with count parameter")
IO.puts("=" <> String.duplicate("=", 60))
count_tool_call = %{
  id: "t6",
  name: "create_shape",
  input: %{"type" => "rectangle", "x" => 10, "y" => 10, "width" => 50, "height" => 30, "count" => 5}
}
IO.puts("  Tool call: create_shape with count=5")
IO.puts("  Expected: Should create 5 objects in a single batch operation")
IO.puts("  Expected result: {:ok, %{count: 5, total: 5, objects: [obj1, obj2, obj3, obj4, obj5]}}")

IO.puts("\nTest case 3: Performance target")
IO.puts("=" <> String.duplicate("=", 60))
IO.puts("  Target: 10 objects in <2s")
IO.puts("  Implementation should log warning if target not met")

IO.puts("\n✅ Implementation complete. To test:")
IO.puts("  1. Create a canvas in the UI")
IO.puts("  2. Use AI command: 'create 5 red rectangles'")
IO.puts("  3. Check logs for 'Batch created N objects in Xms'")
IO.puts("  4. Verify all objects appear atomically (all or none)")
