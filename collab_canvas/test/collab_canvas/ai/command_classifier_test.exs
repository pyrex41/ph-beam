defmodule CollabCanvas.AI.CommandClassifierTest do
  use ExUnit.Case, async: true
  
  alias CollabCanvas.AI.CommandClassifier
  
  describe "classify/1 - fast path" do
    test "simple shape creation commands" do
      assert :fast_path == CommandClassifier.classify("create a red circle")
      assert :fast_path == CommandClassifier.classify("make a blue rectangle")
      assert :fast_path == CommandClassifier.classify("add a green square")
      assert :fast_path == CommandClassifier.classify("draw a yellow triangle")
    end
    
    test "simple text creation commands" do
      assert :fast_path == CommandClassifier.classify("create text saying Hello")
      assert :fast_path == CommandClassifier.classify("add text")
      assert :fast_path == CommandClassifier.classify("make a text label")
    end
    
    test "move operations" do
      assert :fast_path == CommandClassifier.classify("move object 123 to 100,200")
      assert :fast_path == CommandClassifier.classify("move shape abc to 50,50")
    end
    
    test "resize operations" do
      assert :fast_path == CommandClassifier.classify("resize shape to 200x300")
      assert :fast_path == CommandClassifier.classify("make it 150x150 pixels")
    end
    
    test "delete operations" do
      assert :fast_path == CommandClassifier.classify("delete object abc")
      assert :fast_path == CommandClassifier.classify("remove shape 123")
    end
  end
  
  describe "classify/1 - complex path" do
    test "component creation" do
      assert :complex_path == CommandClassifier.classify("create a login form")
      assert :complex_path == CommandClassifier.classify("make a navbar with 5 items")
      assert :complex_path == CommandClassifier.classify("add a sidebar menu")
      assert :complex_path == CommandClassifier.classify("create a card")
    end
    
    test "multiple operations" do
      assert :complex_path == CommandClassifier.classify("create a circle and a square")
      assert :complex_path == CommandClassifier.classify("create a button then move it")
      assert :complex_path == CommandClassifier.classify("add three shapes")
    end
    
    test "layout operations" do
      assert :complex_path == CommandClassifier.classify("arrange these in a grid")
      assert :complex_path == CommandClassifier.classify("align these to the left")
      assert :complex_path == CommandClassifier.classify("distribute evenly")
      assert :complex_path == CommandClassifier.classify("organize in a row")
    end
    
    test "context-dependent commands" do
      assert :complex_path == CommandClassifier.classify("move these objects")
      assert :complex_path == CommandClassifier.classify("delete this shape")
      assert :complex_path == CommandClassifier.classify("resize the selected items")
    end
  end
  
  describe "classify/1 - edge cases" do
    test "unknown commands default to fast path" do
      assert :fast_path == CommandClassifier.classify("do something random")
      assert :fast_path == CommandClassifier.classify("hello world")
    end
    
    test "empty string defaults to fast path" do
      assert :fast_path == CommandClassifier.classify("")
    end
    
    test "case insensitive" do
      assert :fast_path == CommandClassifier.classify("CREATE A CIRCLE")
      assert :complex_path == CommandClassifier.classify("CREATE A LOGIN FORM")
    end
  end
end
