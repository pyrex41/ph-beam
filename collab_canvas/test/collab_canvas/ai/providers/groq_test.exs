defmodule CollabCanvas.AI.Providers.GroqTest do
  use ExUnit.Case, async: true
  
  alias CollabCanvas.AI.Providers.Groq
  alias CollabCanvas.AI.Tools
  
  describe "model_name/0" do
    test "returns the correct model" do
      assert "llama-3.3-70b-versatile" == Groq.model_name()
    end
  end
  
  describe "avg_latency/0" do
    test "returns expected latency" do
      assert 400 == Groq.avg_latency()
    end
  end
  
  describe "max_tokens/0" do
    test "returns max tokens" do
      assert 1024 == Groq.max_tokens()
    end
  end
  
  describe "call/3" do
    test "returns error when API key missing" do
      # Store original key
      original_key = System.get_env("GROQ_API_KEY")
      
      # Remove key
      System.delete_env("GROQ_API_KEY")
      
      assert {:error, :missing_api_key} = 
        Groq.call("create shape", Tools.get_tool_definitions(), [])
      
      # Restore key if it existed
      if original_key, do: System.put_env("GROQ_API_KEY", original_key)
    end
    
    @tag :external_api
    @tag :skip
    test "creates a shape with valid command" do
      # This test requires GROQ_API_KEY to be set
      # Skip by default, run with: mix test --include external_api
      command = "create a red circle at 100,100 with width 50"
      tools = Tools.get_tool_definitions()
      
      assert {:ok, tool_calls} = Groq.call(command, tools, [])
      assert is_list(tool_calls)
      assert length(tool_calls) > 0
      
      [call | _] = tool_calls
      assert is_map(call)
      assert Map.has_key?(call, :name)
      assert Map.has_key?(call, :input)
    end
  end
end
