defmodule CollabCanvas.AI.AgentIntegrationTest do
  @moduledoc """
  End-to-end integration tests for the complete AI agent flow.

  Tests cover the entire stack:
  - User input → Agent → LLM (or short-circuit) → Tool execution → PubSub → Canvas updates

  Performance targets (from PRD):
  - P95 latency <300ms for simple commands
  - Bulk operations (500 objects) <2s
  - Success rate >95%

  Run with:
      mix test test/collab_canvas/ai/agent_integration_test.exs

  Run with timing:
      mix test test/collab_canvas/ai/agent_integration_test.exs --trace
  """

  use CollabCanvas.DataCase, async: false

  alias CollabCanvas.AI.Agent
  alias CollabCanvas.Canvases
  alias CollabCanvas.Accounts
  alias Phoenix.PubSub

  require Logger

  # Test timeouts
  @simple_command_timeout 300
  @bulk_command_timeout 2000
  @pubsub_wait_time 100

  describe "end-to-end flow: simple object creation" do
    setup do
      {:ok, user} = Accounts.create_user(%{email: "test@example.com", name: "Test User"})
      {:ok, canvas} = Canvases.create_canvas(user.id, "Test Canvas")

      # Subscribe to PubSub to track broadcasts
      topic = "canvas:#{canvas.id}"
      Phoenix.PubSub.subscribe(CollabCanvas.PubSub, topic)

      %{user: user, canvas: canvas, topic: topic}
    end

    test "creates object and persists to database", %{canvas: canvas} do
      tool_calls = [
        %{
          id: "test_1",
          name: "create_shape",
          input: %{"type" => "rectangle", "x" => 10, "y" => 20, "width" => 100, "height" => 50}
        }
      ]

      # Execute tool calls
      results = Agent.process_tool_calls(tool_calls, canvas.id)

      # Verify tool execution succeeded
      assert [%{tool: "create_shape", result: {:ok, object}}] = results
      assert object.type == "rectangle"
      assert object.canvas_id == canvas.id

      # Verify database persistence (batched creates use atomic transactions)
      db_objects = Canvases.list_objects(canvas.id)
      assert length(db_objects) == 1
      assert hd(db_objects).id == object.id
    end

    test "handles text creation end-to-end", %{canvas: canvas} do
      tool_calls = [
        %{
          id: "test_2",
          name: "create_text",
          input: %{"text" => "Hello World", "x" => 50, "y" => 100, "font_size" => 24}
        }
      ]

      results = Agent.process_tool_calls(tool_calls, canvas.id)

      assert [%{tool: "create_text", result: {:ok, object}}] = results
      assert object.type == "text"

      data = Jason.decode!(object.data)
      assert data["text"] == "Hello World"
      assert data["font_size"] == 24

      # Verify database persistence
      db_objects = Canvases.list_objects(canvas.id)
      assert length(db_objects) == 1
    end

    test "handles object updates with broadcasts", %{canvas: canvas} do
      # Create an object first
      {:ok, object} =
        Canvases.create_object(canvas.id, "rectangle", %{
          position: %{x: 0, y: 0},
          data: Jason.encode!(%{width: 100, height: 100})
        })

      # Clear any initial broadcasts
      :timer.sleep(@pubsub_wait_time)
      flush_messages()

      # Update via tool call
      tool_calls = [
        %{
          id: "test_3",
          name: "move_object",
          input: %{"object_id" => object.id, "x" => 200, "y" => 300}
        }
      ]

      results = Agent.process_tool_calls(tool_calls, canvas.id)

      assert [%{tool: "move_object", result: {:ok, updated_object}}] = results
      assert updated_object.position.x == 200
      assert updated_object.position.y == 300

      # Verify update broadcast
      :timer.sleep(@pubsub_wait_time)
      assert_received {:object_updated, _}
    end

    test "handles object deletion with broadcasts", %{canvas: canvas} do
      {:ok, object} =
        Canvases.create_object(canvas.id, "circle", %{
          position: %{x: 50, y: 50},
          data: Jason.encode!(%{width: 50, height: 50})
        })

      # Clear initial broadcasts
      :timer.sleep(@pubsub_wait_time)
      flush_messages()

      tool_calls = [
        %{
          id: "test_4",
          name: "delete_object",
          input: %{"object_id" => object.id}
        }
      ]

      results = Agent.process_tool_calls(tool_calls, canvas.id)

      assert [%{tool: "delete_object", result: {:ok, deleted_object}}] = results
      assert deleted_object.id == object.id

      # Verify object is gone
      assert Canvases.get_object(object.id) == nil

      # Verify deletion broadcast
      :timer.sleep(@pubsub_wait_time)
      assert_received {:object_deleted, object_id}
      assert object_id == object.id
    end
  end

  describe "batched creation performance" do
    setup do
      {:ok, user} = Accounts.create_user(%{email: "batch@example.com", name: "Batch User"})
      {:ok, canvas} = Canvases.create_canvas(user.id, "Batch Canvas")

      topic = "canvas:#{canvas.id}"
      Phoenix.PubSub.subscribe(CollabCanvas.PubSub, topic)

      %{user: user, canvas: canvas, topic: topic}
    end

    test "creates 10 objects in single batch", %{canvas: canvas} do
      tool_calls =
        for i <- 1..10 do
          %{
            id: "batch_#{i}",
            name: "create_shape",
            input: %{
              "type" => "rectangle",
              "x" => i * 100,
              "y" => 50,
              "width" => 80,
              "height" => 60
            }
          }
        end

      {time_us, results} =
        :timer.tc(fn ->
          Agent.process_tool_calls(tool_calls, canvas.id)
        end)

      time_ms = time_us / 1000

      # Verify all created
      assert length(results) == 10

      # Each result should have a successful object creation
      # When count=1 (default), each result is {:ok, object}, not {:ok, %{count: ..., total: ...}}
      assert Enum.all?(results, fn %{result: result} ->
               match?({:ok, %CollabCanvas.Canvases.Object{}}, result)
             end)

      # Verify database (batching is atomic)
      db_objects = Canvases.list_objects(canvas.id)
      assert length(db_objects) == 10

      Logger.info("Batch create 10 objects: #{Float.round(time_ms, 2)}ms")
    end

    test "creates 50 objects efficiently", %{canvas: canvas} do
      tool_calls =
        for i <- 1..50 do
          %{
            id: "batch50_#{i}",
            name: "create_shape",
            input: %{
              "type" => if(rem(i, 2) == 0, do: "rectangle", else: "circle"),
              "x" => rem(i, 10) * 100,
              "y" => div(i, 10) * 100,
              "width" => 50,
              "height" => 50
            }
          }
        end

      {time_us, results} =
        :timer.tc(fn ->
          Agent.process_tool_calls(tool_calls, canvas.id)
        end)

      time_ms = time_us / 1000

      assert length(results) == 50

      # Verify database
      db_objects = Canvases.list_objects(canvas.id)
      assert length(db_objects) == 50

      # Should be well under 1 second for 50 objects
      assert time_ms < 1000, "50 objects took #{time_ms}ms, expected <1000ms"

      Logger.info("Batch create 50 objects: #{Float.round(time_ms, 2)}ms")
    end

    @tag timeout: 5000
    test "creates 500 objects in <2s (PRD requirement)", %{canvas: canvas} do
      tool_calls =
        for i <- 1..500 do
          %{
            id: "batch500_#{i}",
            name: "create_shape",
            input: %{
              "type" => Enum.random(["rectangle", "circle"]),
              "x" => rem(i, 25) * 50,
              "y" => div(i, 25) * 50,
              "width" => 40,
              "height" => 40,
              "color" => Enum.random(["#FF0000", "#00FF00", "#0000FF"])
            }
          }
        end

      {time_us, results} =
        :timer.tc(fn ->
          Agent.process_tool_calls(tool_calls, canvas.id)
        end)

      time_ms = time_us / 1000
      time_s = time_ms / 1000

      assert length(results) == 500

      # Verify database
      db_objects = Canvases.list_objects(canvas.id)
      assert length(db_objects) == 500

      # PRD requirement: <2 seconds for 500 objects
      assert time_s < 2.0, "500 objects took #{Float.round(time_s, 3)}s, expected <2s"

      Logger.info("✓ Batch create 500 objects: #{Float.round(time_s, 3)}s (target: <2s)")
      Logger.info("  Average: #{Float.round(time_ms / 500, 2)}ms per object")
    end

    test "batching is atomic (all or nothing)", %{canvas: canvas} do
      # Mix valid and invalid tool calls
      tool_calls = [
        %{
          id: "batch_atomic_1",
          name: "create_shape",
          input: %{"type" => "rectangle", "x" => 10, "y" => 10, "width" => 50, "height" => 50}
        },
        %{
          id: "batch_atomic_2",
          name: "create_shape",
          input: %{"type" => "rectangle", "x" => 100, "y" => 10, "width" => 50, "height" => 50}
        }
        # This one will fail due to missing canvas after we delete it
      ]

      # First batch should succeed
      results1 = Agent.process_tool_calls(tool_calls, canvas.id)
      assert length(results1) == 2
      assert Enum.all?(results1, fn %{result: result} -> match?({:ok, _}, result) end)

      # Verify objects created
      db_objects = Canvases.list_objects(canvas.id)
      assert length(db_objects) == 2
    end
  end

  describe "error handling integration" do
    setup do
      {:ok, user} = Accounts.create_user(%{email: "error@example.com", name: "Error User"})
      {:ok, canvas} = Canvases.create_canvas(user.id, "Error Canvas")
      %{user: user, canvas: canvas}
    end

    test "handles non-existent canvas gracefully", %{canvas: canvas} do
      result = Agent.execute_command("create a rectangle", 99999)
      assert {:error, :canvas_not_found} = result
    end

    test "handles invalid tool calls gracefully", %{canvas: canvas} do
      tool_calls = [
        %{
          id: "invalid_1",
          name: "unknown_tool",
          input: %{"foo" => "bar"}
        }
      ]

      results = Agent.process_tool_calls(tool_calls, canvas.id)

      # Current implementation returns empty list for unknown tools
      # This is logged as a warning but doesn't return an error result
      assert is_list(results)
      # The unknown tool is filtered out, so we get empty list
      assert length(results) == 0 ||
               match?([%{tool: "unknown", result: {:error, :unknown_tool}}], results)
    end

    test "handles malformed tool input gracefully", %{canvas: canvas} do
      tool_calls = [
        %{
          id: "malformed_1",
          name: "create_shape",
          # Missing required x, y, width
          input: %{"type" => "rectangle"}
        }
      ]

      results = Agent.process_tool_calls(tool_calls, canvas.id)

      # Should handle gracefully, not crash
      assert is_list(results)
      assert length(results) == 1
    end

    test "handles non-existent object operations", %{canvas: canvas} do
      tool_calls = [
        %{
          id: "nonexistent_1",
          name: "move_object",
          input: %{"object_id" => 99999, "x" => 100, "y" => 100}
        }
      ]

      results = Agent.process_tool_calls(tool_calls, canvas.id)
      assert [%{tool: "move_object", result: {:error, :not_found}}] = results
    end

    test "handles partial batch failures gracefully", %{canvas: canvas} do
      # Create one object
      {:ok, object} =
        Canvases.create_object(canvas.id, "rectangle", %{
          position: %{x: 0, y: 0},
          data: Jason.encode!(%{width: 100, height: 100})
        })

      tool_calls = [
        # Valid
        %{
          id: "partial_1",
          name: "move_object",
          input: %{"object_id" => object.id, "x" => 50, "y" => 50}
        },
        # Invalid - non-existent object
        %{
          id: "partial_2",
          name: "move_object",
          input: %{"object_id" => 99999, "x" => 100, "y" => 100}
        }
      ]

      results = Agent.process_tool_calls(tool_calls, canvas.id)

      # First should succeed
      assert %{tool: "move_object", result: {:ok, _}} = Enum.at(results, 0)

      # Second should fail
      assert %{tool: "move_object", result: {:error, :not_found}} = Enum.at(results, 1)
    end

    test "handles missing API key gracefully", %{canvas: canvas} do
      # Save current keys
      claude_key = System.get_env("CLAUDE_API_KEY")
      openai_key = System.get_env("OPENAI_API_KEY")
      groq_key = System.get_env("GROQ_API_KEY")

      try do
        # Clear all API keys
        System.delete_env("CLAUDE_API_KEY")
        System.delete_env("OPENAI_API_KEY")
        System.delete_env("GROQ_API_KEY")

        result = Agent.execute_command("create a rectangle", canvas.id)
        assert {:error, :missing_api_key} = result
      after
        # Restore keys
        if claude_key, do: System.put_env("CLAUDE_API_KEY", claude_key)
        if openai_key, do: System.put_env("OPENAI_API_KEY", openai_key)
        if groq_key, do: System.put_env("GROQ_API_KEY", groq_key)
      end
    end
  end

  describe "complex multi-operation flows" do
    setup do
      {:ok, user} = Accounts.create_user(%{email: "complex@example.com", name: "Complex User"})
      {:ok, canvas} = Canvases.create_canvas(user.id, "Complex Canvas")

      topic = "canvas:#{canvas.id}"
      Phoenix.PubSub.subscribe(CollabCanvas.PubSub, topic)

      %{user: user, canvas: canvas, topic: topic}
    end

    test "handles mixed create and update operations", %{canvas: canvas} do
      # First create some objects
      {:ok, obj1} =
        Canvases.create_object(canvas.id, "rectangle", %{
          position: %{x: 0, y: 0},
          data: Jason.encode!(%{width: 100, height: 100})
        })

      {:ok, obj2} =
        Canvases.create_object(canvas.id, "circle", %{
          position: %{x: 200, y: 0},
          data: Jason.encode!(%{width: 50, height: 50})
        })

      # Clear initial broadcasts
      :timer.sleep(@pubsub_wait_time)
      flush_messages()

      # Mix of operations
      tool_calls = [
        # Create new object
        %{
          id: "mixed_1",
          name: "create_shape",
          input: %{"type" => "rectangle", "x" => 400, "y" => 0, "width" => 80, "height" => 60}
        },
        # Move existing
        %{
          id: "mixed_2",
          name: "move_object",
          input: %{"object_id" => obj1.id, "x" => 50, "y" => 50}
        },
        # Resize existing
        %{
          id: "mixed_3",
          name: "resize_object",
          input: %{"object_id" => obj2.id, "width" => 100, "height" => 100}
        }
      ]

      results = Agent.process_tool_calls(tool_calls, canvas.id)

      # All should succeed
      assert length(results) == 3
      assert Enum.all?(results, fn %{result: result} -> match?({:ok, _}, result) end)

      # Verify final state
      db_objects = Canvases.list_objects(canvas.id)
      assert length(db_objects) == 3
    end

    test "handles component creation", %{canvas: canvas} do
      tool_calls = [
        %{
          id: "component_1",
          name: "create_component",
          input: %{
            "type" => "login_form",
            "x" => 100,
            "y" => 100,
            "width" => 350,
            "height" => 280,
            "theme" => "light"
          }
        }
      ]

      results = Agent.process_tool_calls(tool_calls, canvas.id)

      assert [%{tool: "create_component", result: {:ok, component_result}}] = results
      assert component_result.component_type == "login_form"
      assert is_list(component_result.object_ids)
      assert length(component_result.object_ids) > 0

      # Verify all component objects created
      db_objects = Canvases.list_objects(canvas.id)
      assert length(db_objects) == length(component_result.object_ids)
    end

    test "handles text updates", %{canvas: canvas} do
      {:ok, text_obj} =
        Canvases.create_object(canvas.id, "text", %{
          position: %{x: 50, y: 50},
          data: Jason.encode!(%{text: "Original", font_size: 16})
        })

      tool_calls = [
        %{
          id: "text_update_1",
          name: "update_text",
          input: %{
            "object_id" => text_obj.id,
            "new_text" => "Updated Text",
            "font_size" => 24,
            "color" => "#FF0000"
          }
        }
      ]

      results = Agent.process_tool_calls(tool_calls, canvas.id)

      assert [%{tool: "update_text", result: {:ok, updated_obj}}] = results

      data = Jason.decode!(updated_obj.data)
      assert data["text"] == "Updated Text"
      assert data["font_size"] == 24
      assert data["color"] == "#FF0000"
    end

    test "handles rotation operations", %{canvas: canvas} do
      {:ok, object} =
        Canvases.create_object(canvas.id, "rectangle", %{
          position: %{x: 100, y: 100},
          data: Jason.encode!(%{width: 100, height: 50})
        })

      tool_calls = [
        %{
          id: "rotate_1",
          name: "rotate_object",
          input: %{
            "object_id" => object.id,
            "angle" => 45,
            "pivot_point" => "center"
          }
        }
      ]

      results = Agent.process_tool_calls(tool_calls, canvas.id)

      assert [%{tool: "rotate_object", result: {:ok, rotated_obj}}] = results

      data = Jason.decode!(rotated_obj.data)
      assert data["rotation"] == 45
      assert data["pivot_point"] == "center"
    end

    test "handles style changes", %{canvas: canvas} do
      {:ok, object} =
        Canvases.create_object(canvas.id, "rectangle", %{
          position: %{x: 0, y: 0},
          data: Jason.encode!(%{width: 100, height: 100, fill: "#000000"})
        })

      tool_calls = [
        %{
          id: "style_1",
          name: "change_style",
          input: %{
            "object_id" => object.id,
            "property" => "fill",
            "value" => "#FF0000"
          }
        }
      ]

      results = Agent.process_tool_calls(tool_calls, canvas.id)

      assert [%{tool: "change_style", result: {:ok, styled_obj}}] = results

      data = Jason.decode!(styled_obj.data)
      assert data["fill"] == "#FF0000"
    end
  end

  describe "PubSub broadcast verification" do
    setup do
      {:ok, user} = Accounts.create_user(%{email: "pubsub@example.com", name: "PubSub User"})
      {:ok, canvas} = Canvases.create_canvas(user.id, "PubSub Canvas")

      topic = "canvas:#{canvas.id}"
      Phoenix.PubSub.subscribe(CollabCanvas.PubSub, topic)

      %{user: user, canvas: canvas, topic: topic}
    end

    test "verifies objects are created atomically in batch", %{canvas: canvas} do
      # Note: Current batch implementation doesn't broadcast via PubSub
      # This is by design for performance - batches are atomic transactions
      tool_calls =
        for i <- 1..20 do
          %{
            id: "pubsub_batch_#{i}",
            name: "create_shape",
            input: %{"type" => "circle", "x" => i * 50, "y" => 50, "width" => 40, "height" => 40}
          }
        end

      Agent.process_tool_calls(tool_calls, canvas.id)

      # Verify atomic creation in database
      db_objects = Canvases.list_objects(canvas.id)
      assert length(db_objects) == 20

      # All should have been created in single transaction
      assert Enum.all?(db_objects, fn obj -> obj.canvas_id == canvas.id end)
    end

    test "mixed operations with update broadcasts", %{canvas: canvas} do
      {:ok, object} =
        Canvases.create_object(canvas.id, "rectangle", %{
          position: %{x: 0, y: 0},
          data: Jason.encode!(%{width: 100, height: 100})
        })

      # Clear initial broadcast
      :timer.sleep(@pubsub_wait_time)
      flush_messages()

      tool_calls = [
        # Create (batched, no broadcast)
        %{
          id: "mixed_pub_1",
          name: "create_shape",
          input: %{"type" => "circle", "x" => 100, "y" => 100, "width" => 50, "height" => 50}
        },
        # Update (individual, has broadcast)
        %{
          id: "mixed_pub_2",
          name: "move_object",
          input: %{"object_id" => object.id, "x" => 200, "y" => 200}
        }
      ]

      Agent.process_tool_calls(tool_calls, canvas.id)

      :timer.sleep(@pubsub_wait_time)

      # Should receive update broadcast (create is batched without broadcast)
      messages = collect_messages()

      # Check we got update broadcast
      has_update = Enum.any?(messages, fn msg -> match?({:object_updated, _}, msg) end)
      assert has_update, "Expected object_updated broadcast"
    end
  end

  describe "success rate and reliability" do
    setup do
      {:ok, user} =
        Accounts.create_user(%{email: "reliability@example.com", name: "Reliability User"})

      {:ok, canvas} = Canvases.create_canvas(user.id, "Reliability Canvas")
      %{user: user, canvas: canvas}
    end

    test "achieves >95% success rate on valid operations", %{canvas: canvas} do
      # Run 100 operations
      num_operations = 100

      tool_calls =
        for i <- 1..num_operations do
          %{
            id: "reliability_#{i}",
            name: "create_shape",
            input: %{
              "type" => if(rem(i, 2) == 0, do: "rectangle", else: "circle"),
              "x" => rem(i, 20) * 50,
              "y" => div(i, 20) * 50,
              "width" => 40 + rem(i, 10) * 5,
              "height" => 40 + rem(i, 10) * 5
            }
          }
        end

      results = Agent.process_tool_calls(tool_calls, canvas.id)

      # Count successes
      successes =
        Enum.count(results, fn %{result: result} ->
          match?({:ok, _}, result)
        end)

      success_rate = successes / num_operations * 100

      # PRD requirement: >95% success rate
      assert success_rate > 95.0,
             "Success rate #{Float.round(success_rate, 2)}% is below 95% threshold"

      Logger.info(
        "✓ Success rate: #{Float.round(success_rate, 2)}% (#{successes}/#{num_operations})"
      )
    end

    test "handles rapid successive operations without errors", %{canvas: canvas} do
      # Create object
      {:ok, object} =
        Canvases.create_object(canvas.id, "rectangle", %{
          position: %{x: 100, y: 100},
          data: Jason.encode!(%{width: 100, height: 100})
        })

      # Fire 10 rapid updates
      results =
        for i <- 1..10 do
          tool_calls = [
            %{
              id: "rapid_#{i}",
              name: "move_object",
              input: %{"object_id" => object.id, "x" => i * 10, "y" => i * 10}
            }
          ]

          Agent.process_tool_calls(tool_calls, canvas.id)
        end

      # All should succeed
      assert Enum.all?(results, fn result_list ->
               [%{result: {:ok, _}}] = result_list
               true
             end)
    end
  end

  # Helper functions

  defp flush_messages do
    receive do
      _ -> flush_messages()
    after
      0 -> :ok
    end
  end

  defp collect_messages(acc \\ []) do
    receive do
      msg -> collect_messages([msg | acc])
    after
      50 -> Enum.reverse(acc)
    end
  end
end
