defmodule CollabCanvas.AI.CommandClassifier do
  @moduledoc """
  Classifies commands to route them to the optimal execution path.
  
  Routes commands to the appropriate LLM provider based on complexity:
  - **Fast Path:** Simple, single-operation commands → Groq (300-500ms)
  - **Complex Path:** Multi-step, ambiguous commands → Groq with Claude fallback
  
  ## Classification Strategy
  
  Uses pattern matching and heuristics to classify commands:
  
  1. **Pattern Matching:** Regex patterns for common simple commands
  2. **Operation Counting:** Multiple verbs = complex
  3. **Context Detection:** References to "this", "these" = complex
  4. **Component Detection:** UI component requests = complex
  5. **Layout Detection:** Arrangement commands = complex
  
  ## Examples
  
      iex> CommandClassifier.classify("create a red circle at 100,100")
      :fast_path
      
      iex> CommandClassifier.classify("create a login form with email and password")
      :complex_path
      
      iex> CommandClassifier.classify("arrange these objects in a grid")
      :complex_path
  """
  
  require Logger
  
  @type classification :: :fast_path | :complex_path
  
  # Pattern-based classification for simple commands
  @simple_patterns [
    # Single shape creation
    ~r/^create (a|an) \w+ (circle|rectangle|square|triangle)/i,
    ~r/^make (a|an) \w+ (circle|rectangle|square|triangle)/i,
    ~r/^add (a|an) (circle|rectangle|square|triangle)/i,
    ~r/^draw (a|an) (circle|rectangle|square|triangle)/i,
    
    # Simple text
    ~r/^(create|add|make|write) (a|an)? ?\w* text/i,
    
    # Move operations
    ~r/^move .+ to \d+,\s*\d+/i,
    ~r/^move .+ by \d+,\s*\d+/i,
    
    # Resize operations
    ~r/^resize .+ to \d+x\d+/i,
    ~r/^make .+ \d+x\d+ (pixels|px)?/i,
    ~r/^scale .+ to \d+/i,
    
    # Delete operations
    ~r/^delete (object|shape|item|element) \w+/i,
    ~r/^remove (object|shape|item|element) \w+/i
  ]
  
  @doc """
  Classifies a command as :fast_path or :complex_path.
  
  ## Parameters
    * `command` - Natural language command string
  
  ## Returns
    * `:fast_path` - Route to Groq for fast execution
    * `:complex_path` - Route to Groq with Claude fallback if needed
  
  ## Examples
  
      iex> classify("create a blue square")
      :fast_path
      
      iex> classify("create a navbar with 5 menu items")
      :complex_path
  """
  @spec classify(String.t()) :: classification()
  def classify(command) when is_binary(command) do
    classification = do_classify(command)
    log_classification(command, classification)
    classification
  end
  
  defp do_classify(command) do
    cond do
      simple_pattern_match?(command) ->
        :fast_path
      
      contains_multiple_operations?(command) ->
        :complex_path
      
      requires_context?(command) ->
        :complex_path
      
      is_component_request?(command) ->
        :complex_path
      
      is_layout_request?(command) ->
        :complex_path
      
      true ->
        # Default to fast path for unknown patterns
        # Groq can handle most things, Claude is fallback
        :fast_path
    end
  end
  
  # Check if command matches simple patterns
  defp simple_pattern_match?(command) do
    Enum.any?(@simple_patterns, &Regex.match?(&1, command))
  end
  
  # Detect multiple operations in a single command
  defp contains_multiple_operations?(command) do
    command_lower = String.downcase(command)
    
    # Count action verbs
    verbs = ["create", "move", "delete", "resize", "add", "make", "remove", "draw"]
    verb_count = Enum.count(verbs, &String.contains?(command_lower, &1))
    
    # Count conjunctions that indicate multiple operations
    has_conjunction = 
      String.contains?(command_lower, " and ") ||
      String.contains?(command_lower, " then ") ||
      String.contains?(command_lower, ", and ")
    
    # Multiple verbs OR single verb with conjunction
    verb_count > 1 || (verb_count >= 1 && has_conjunction)
  end
  
  # Check if command references context (selected objects, "this", "that")
  defp requires_context?(command) do
    command_lower = String.downcase(command)
    
    context_words = [
      "this", "that", "these", "those", 
      "selected", "selection", "them", "it"
    ]
    
    Enum.any?(context_words, fn word ->
      # Use word boundaries to avoid false positives
      Regex.match?(~r/\b#{word}\b/, command_lower)
    end)
  end
  
  # Detect component creation requests
  defp is_component_request?(command) do
    command_lower = String.downcase(command)
    
    components = [
      "login form", "signup form", "registration form", "form",
      "navbar", "nav bar", "navigation bar", "navigation",
      "sidebar", "side bar", "menu",
      "card", "button group", "buttons",
      "dashboard", "layout", "panel",
      "header", "footer"
    ]
    
    Enum.any?(components, &String.contains?(command_lower, &1))
  end
  
  # Detect layout/arrangement requests
  defp is_layout_request?(command) do
    command_lower = String.downcase(command)
    
    layout_keywords = [
      "arrange", "align", "distribute", "space",
      "grid", "row", "column", "stack",
      "center", "organize", "layout",
      "horizontal", "vertical", "evenly"
    ]
    
    Enum.any?(layout_keywords, &String.contains?(command_lower, &1))
  end
  
  # Log classification for monitoring and tuning
  defp log_classification(command, classification) do
    # Determine reason for classification
    reason = cond do
      simple_pattern_match?(command) -> "pattern_match"
      contains_multiple_operations?(command) -> "multiple_operations"
      requires_context?(command) -> "requires_context"
      is_component_request?(command) -> "component_request"
      is_layout_request?(command) -> "layout_request"
      true -> "default"
    end
    
    Logger.info("""
    [CommandClassifier] Classification complete
    Command: #{String.slice(command, 0..60)}#{if String.length(command) > 60, do: "...", else: ""}
    Classification: #{classification}
    Reason: #{reason}
    """)
  end
end
