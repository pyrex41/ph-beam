defmodule CollabCanvas.AI.AgentErrorHandlingTest do
  use CollabCanvas.DataCase, async: true

  alias CollabCanvas.AI.Agent
  alias CollabCanvas.Canvases
  alias CollabCanvas.Accounts

  describe "LLM error handling" do
    setup do
      {:ok, user} = Accounts.create_user(%{email: "test@example.com", name: "Test User"})
      {:ok, canvas} = Canvases.create_canvas(user.id, "Test Canvas")
      %{canvas: canvas, user: user}
    end

    test "handles missing API key gracefully", %{canvas: canvas} do
      # Save current key and unset it
      original_key = System.get_env("CLAUDE_API_KEY")
      System.delete_env("CLAUDE_API_KEY")
      System.delete_env("GROQ_API_KEY")
      System.delete_env("OPENAI_API_KEY")

      try do
        result = Agent.execute_command("create a rectangle", canvas.id)

        assert {:error, :missing_api_key} = result
      after
        # Restore key
        if original_key, do: System.put_env("CLAUDE_API_KEY", original_key)
      end
    end

    test "validates tool call structure from LLM" do
      # This would test the validation of tool calls returned by the LLM
      # In a real test, we would mock the LLM response

      malformed_tool_call = %{
        "id" => "test_1",
        # Missing 'name' field
        "input" => %{}
      }

      # Validate tool call structure
      result = Agent.validate_tool_call_structure(malformed_tool_call)
      assert {:error, {:missing_fields, missing}} = result
      assert "name" in missing
    end

    test "handles invalid response format from LLM" do
      # Test parsing invalid Claude response
      invalid_response = %{
        "invalid_field" => "data",
        "no_content" => []
      }

      result = Agent.parse_claude_response(invalid_response)
      assert {:error, {:invalid_response_format, _message}} = result
    end

    test "validates tool calls have required fields" do
      # Valid tool call
      valid_call = %{
        "id" => "tool_1",
        "name" => "create_shape",
        "input" => %{"type" => "rectangle", "x" => 10, "y" => 20, "width" => 100}
      }

      result = Agent.validate_tool_call_structure(valid_call)
      assert {:ok, %{id: "tool_1", name: "create_shape", input: _}} = result

      # Invalid - missing input
      invalid_call = %{
        "id" => "tool_1",
        "name" => "create_shape"
      }

      result = Agent.validate_tool_call_structure(invalid_call)
      assert {:error, {:missing_fields, fields}} = result
      assert "input" in fields
    end

    test "handles empty tool call list" do
      # Claude can return empty list if confused
      response = %{
        "content" => [],
        "stop_reason" => "end_turn"
      }

      result = Agent.parse_claude_response(response)
      assert {:ok, []} = result
    end

    test "handles OpenAI JSON decode errors" do
      # Test invalid JSON in arguments
      invalid_tool_call = %{
        "id" => "test_1",
        "function" => %{
          "name" => "create_shape",
          "arguments" => "{invalid json"
        }
      }

      result = Agent.validate_openai_tool_call(invalid_tool_call)
      assert {:error, {:json_decode_failed, _reason}} = result
    end
  end

  describe "API error codes" do
    test "formats API errors for users" do
      # Test error formatting
      assert "authentication failed" =~ String.downcase(Agent.format_error_for_user({:api_error, 401, %{}}, "test"))
      assert "rate limited" =~ String.downcase(Agent.format_error_for_user({:api_error, 429, %{}}, "test"))
      assert "unavailable" =~ String.downcase(Agent.format_error_for_user({:api_error, 500, %{}}, "test"))
    end

    test "formats validation errors for users" do
      errors = [{"create_shape", "Missing required field: x"}]
      message = Agent.format_error_for_user({:validation_failed, errors}, "test")

      assert message =~ "create_shape"
      assert message =~ "Missing required field"
    end
  end
end
