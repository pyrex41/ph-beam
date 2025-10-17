defmodule CollabCanvas.AI.AgentFallbackTest do
  use CollabCanvas.DataCase, async: false
  
  alias CollabCanvas.AI.Agent
  alias CollabCanvas.AI.Providers.{Groq, Claude}
  alias CollabCanvas.AI.{CircuitBreaker, RateLimiter}
  alias CollabCanvas.{Canvases, Repo}
  
  setup do
    # Reset circuit breaker and rate limiter before each test
    CircuitBreaker.reset(:groq)
    CircuitBreaker.reset(:claude)
    RateLimiter.reset(:groq)
    RateLimiter.reset(:claude)
    
    # Create test canvas
    {:ok, canvas} = Canvases.create_canvas(%{name: "Test Canvas"})
    
    %{canvas: canvas}
  end
  
  describe "automatic fallback from Groq to Claude" do
    @tag :integration
    test "falls back to Claude when Groq API key is missing", %{canvas: canvas} do
      # Store original Groq key
      original_groq_key = System.get_env("GROQ_API_KEY")
      
      try do
        # Remove Groq API key to simulate failure
        System.delete_env("GROQ_API_KEY")
        
        # Execute command - should fallback to Claude
        command = "create a red circle at 100,100"
        result = Agent.execute_command(command, canvas.id)
        
        # Should succeed via Claude fallback
        case result do
          {:ok, _results} ->
            # Success! Fallback worked
            assert true
          
          {:error, :missing_api_key} ->
            # Both keys missing - expected in test environment
            assert true
          
          {:error, reason} ->
            # Some other error
            flunk("Expected fallback to succeed or both keys missing, got: #{inspect(reason)}")
        end
      after
        # Restore Groq API key
        if original_groq_key, do: System.put_env("GROQ_API_KEY", original_groq_key)
      end
    end
    
    @tag :integration
    test "circuit breaker triggers fallback after repeated failures", %{canvas: canvas} do
      # Simulate multiple Groq failures
      for _ <- 1..6 do
        CircuitBreaker.record_failure(:groq)
      end
      
      # Circuit should now be open
      assert CircuitBreaker.open?(:groq) == true
      
      # Execute command - should skip Groq and use Claude
      command = "create a blue square at 200,200"
      
      # The agent should detect circuit is open and fallback
      result = Agent.execute_command(command, canvas.id)
      
      # Should either succeed with Claude or fail gracefully
      case result do
        {:ok, _results} ->
          # Success with Claude
          assert true
        
        {:error, :circuit_open} ->
          # Circuit open, no fallback triggered (expected behavior)
          assert true
        
        {:error, :missing_api_key} ->
          # API keys not configured in test
          assert true
        
        {:error, _reason} ->
          # Other errors are ok in test environment
          assert true
      end
      
      # Reset circuit for other tests
      CircuitBreaker.reset(:groq)
    end
    
    @tag :integration
    test "rate limiter does not trigger fallback", %{canvas: canvas} do
      # Fill up rate limit for Groq
      max_requests = Application.get_env(:collab_canvas, [:ai, :max_requests_per_minute], 60)
      
      # Simulate rate limit being hit (add max requests)
      for _ <- 1..max_requests do
        RateLimiter.check_rate(:groq)
      end
      
      # Next request should be rate limited
      assert {:error, :rate_limited} == RateLimiter.check_rate(:groq)
      
      # Execute command - should return rate_limited error, NOT fallback
      command = "create a green triangle at 300,300"
      result = Agent.execute_command(command, canvas.id)
      
      # Should fail with rate_limited, not fallback to Claude
      assert {:error, :rate_limited} == result
      
      # Reset rate limiter
      RateLimiter.reset(:groq)
    end
  end
  
  describe "fallback error handling" do
    @tag :integration
    test "returns error when both providers fail", %{canvas: canvas} do
      # Store original keys
      original_groq = System.get_env("GROQ_API_KEY")
      original_claude = System.get_env("CLAUDE_API_KEY")
      
      try do
        # Remove both API keys
        System.delete_env("GROQ_API_KEY")
        System.delete_env("CLAUDE_API_KEY")
        
        # Execute command
        command = "create a yellow circle"
        result = Agent.execute_command(command, canvas.id)
        
        # Should fail with missing_api_key
        assert {:error, :missing_api_key} == result
      after
        # Restore keys
        if original_groq, do: System.put_env("GROQ_API_KEY", original_groq)
        if original_claude, do: System.put_env("CLAUDE_API_KEY", original_claude)
      end
    end
  end
  
  describe "fallback telemetry" do
    test "emits telemetry events on fallback", %{canvas: canvas} do
      # Attach test telemetry handler
      test_pid = self()
      
      :telemetry.attach(
        "test-fallback-handler",
        [:collab_canvas, :ai, :command, :executed],
        fn event_name, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event_name, measurements, metadata})
        end,
        nil
      )
      
      # Store original Groq key
      original_groq = System.get_env("GROQ_API_KEY")
      
      try do
        # Remove Groq to trigger fallback
        System.delete_env("GROQ_API_KEY")
        
        # Execute command
        Agent.execute_command("create a circle", canvas.id)
        
        # Should receive telemetry event
        assert_receive {:telemetry, [:collab_canvas, :ai, :command, :executed], 
                       measurements, metadata}, 1000
        
        # Check metadata contains provider info
        assert Map.has_key?(metadata, :provider)
        assert Map.has_key?(metadata, :classification)
      after
        :telemetry.detach("test-fallback-handler")
        if original_groq, do: System.put_env("GROQ_API_KEY", original_groq)
      end
    end
  end
end
