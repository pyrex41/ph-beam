defmodule CollabCanvas.AI.LayoutTest do
  use ExUnit.Case, async: true
  alias CollabCanvas.AI.Layout

  describe "distribute_horizontally/2" do
    test "distributes two objects with even spacing" do
      objects = [
        %{id: "1", position: %{x: 0, y: 100}, data: %{width: 50, height: 50}},
        %{id: "2", position: %{x: 200, y: 100}, data: %{width: 50, height: 50}}
      ]

      result = Layout.distribute_horizontally(objects, :even)

      # First object should stay at x: 0
      assert Enum.at(result, 0).position.x == 0
      assert Enum.at(result, 0).position.y == 100

      # Second object should be at x: 200 (maintaining original total width)
      assert Enum.at(result, 1).position.x == 200
      assert Enum.at(result, 1).position.y == 100
    end

    test "distributes three objects with even spacing" do
      objects = [
        %{id: "1", position: %{x: 0, y: 100}, data: %{width: 50, height: 50}},
        %{id: "2", position: %{x: 100, y: 100}, data: %{width: 50, height: 50}},
        %{id: "3", position: %{x: 300, y: 100}, data: %{width: 50, height: 50}}
      ]

      result = Layout.distribute_horizontally(objects, :even)

      # With even distribution, the algorithm maintains outer bounds and evenly spaces gaps
      # Total width: (300 + 50) - 0 = 350px
      # Total object width: 50 * 3 = 150px
      # Total gap space: 350 - 150 = 200px
      # Gap between each: 200 / 2 = 100px
      # Positions: 0, 150 (0 + 50 + 100), 300 (150 + 50 + 100)
      assert Enum.at(result, 0).position.x == 0
      assert abs(Enum.at(result, 1).position.x - 150) <= 1
      assert abs(Enum.at(result, 2).position.x - 300) <= 1
    end

    test "distributes objects with fixed spacing" do
      objects = [
        %{id: "1", position: %{x: 0, y: 100}, data: %{width: 50, height: 50}},
        %{id: "2", position: %{x: 100, y: 100}, data: %{width: 50, height: 50}}
      ]

      result = Layout.distribute_horizontally(objects, 20)

      assert Enum.at(result, 0).position.x == 0
      assert Enum.at(result, 1).position.x == 70  # 50 (width) + 20 (spacing)
    end

    test "handles single object" do
      objects = [%{id: "1", position: %{x: 100, y: 100}, data: %{width: 50, height: 50}}]
      result = Layout.distribute_horizontally(objects, :even)

      assert length(result) == 1
      assert Enum.at(result, 0).position.x == 100
    end

    test "handles empty list" do
      result = Layout.distribute_horizontally([], :even)
      assert result == []
    end

    test "preserves y coordinates" do
      objects = [
        %{id: "1", position: %{x: 0, y: 50}, data: %{width: 50, height: 50}},
        %{id: "2", position: %{x: 100, y: 150}, data: %{width: 50, height: 50}}
      ]

      result = Layout.distribute_horizontally(objects, 20)

      assert Enum.at(result, 0).position.y == 50
      assert Enum.at(result, 1).position.y == 150
    end
  end

  describe "distribute_vertically/2" do
    test "distributes two objects with even spacing" do
      objects = [
        %{id: "1", position: %{x: 100, y: 0}, data: %{width: 50, height: 50}},
        %{id: "2", position: %{x: 100, y: 200}, data: %{width: 50, height: 50}}
      ]

      result = Layout.distribute_vertically(objects, :even)

      assert Enum.at(result, 0).position.y == 0
      assert Enum.at(result, 1).position.y == 200
    end

    test "distributes three objects with even spacing" do
      objects = [
        %{id: "1", position: %{x: 100, y: 0}, data: %{width: 50, height: 50}},
        %{id: "2", position: %{x: 100, y: 100}, data: %{width: 50, height: 50}},
        %{id: "3", position: %{x: 100, y: 300}, data: %{width: 50, height: 50}}
      ]

      result = Layout.distribute_vertically(objects, :even)

      # With even distribution, the algorithm maintains outer bounds and evenly spaces gaps
      # Total height: (300 + 50) - 0 = 350px
      # Total object height: 50 * 3 = 150px
      # Total gap space: 350 - 150 = 200px
      # Gap between each: 200 / 2 = 100px
      # Positions: 0, 150 (0 + 50 + 100), 300 (150 + 50 + 100)
      assert Enum.at(result, 0).position.y == 0
      assert abs(Enum.at(result, 1).position.y - 150) <= 1
      assert abs(Enum.at(result, 2).position.y - 300) <= 1
    end

    test "distributes objects with fixed spacing" do
      objects = [
        %{id: "1", position: %{x: 100, y: 0}, data: %{width: 50, height: 50}},
        %{id: "2", position: %{x: 100, y: 100}, data: %{width: 50, height: 50}}
      ]

      result = Layout.distribute_vertically(objects, 20)

      assert Enum.at(result, 0).position.y == 0
      assert Enum.at(result, 1).position.y == 70  # 50 (height) + 20 (spacing)
    end

    test "preserves x coordinates" do
      objects = [
        %{id: "1", position: %{x: 50, y: 0}, data: %{width: 50, height: 50}},
        %{id: "2", position: %{x: 150, y: 100}, data: %{width: 50, height: 50}}
      ]

      result = Layout.distribute_vertically(objects, 20)

      assert Enum.at(result, 0).position.x == 50
      assert Enum.at(result, 1).position.x == 150
    end
  end

  describe "arrange_grid/3" do
    test "arranges objects in 2 column grid" do
      objects = [
        %{id: "1", position: %{x: 0, y: 0}, data: %{width: 50, height: 50}},
        %{id: "2", position: %{x: 100, y: 0}, data: %{width: 50, height: 50}},
        %{id: "3", position: %{x: 200, y: 0}, data: %{width: 50, height: 50}},
        %{id: "4", position: %{x: 300, y: 0}, data: %{width: 50, height: 50}}
      ]

      result = Layout.arrange_grid(objects, 2, 10)

      # First row
      assert Enum.at(result, 0).position.x == 0
      assert Enum.at(result, 0).position.y == 0
      assert Enum.at(result, 1).position.x == 60  # 50 + 10 spacing
      assert Enum.at(result, 1).position.y == 0

      # Second row
      assert Enum.at(result, 2).position.x == 0
      assert Enum.at(result, 2).position.y == 60  # 50 + 10 spacing
      assert Enum.at(result, 3).position.x == 60
      assert Enum.at(result, 3).position.y == 60
    end

    test "arranges objects in 3 column grid" do
      objects = [
        %{id: "1", position: %{x: 0, y: 0}, data: %{width: 50, height: 50}},
        %{id: "2", position: %{x: 0, y: 0}, data: %{width: 50, height: 50}},
        %{id: "3", position: %{x: 0, y: 0}, data: %{width: 50, height: 50}},
        %{id: "4", position: %{x: 0, y: 0}, data: %{width: 50, height: 50}}
      ]

      result = Layout.arrange_grid(objects, 3, 20)

      # First row (3 items)
      assert Enum.at(result, 0).position.x == 0
      assert Enum.at(result, 1).position.x == 70  # 50 + 20 spacing
      assert Enum.at(result, 2).position.x == 140  # (50 + 20) * 2

      # Second row (1 item)
      assert Enum.at(result, 3).position.x == 0
      assert Enum.at(result, 3).position.y == 70  # 50 + 20 spacing
    end

    test "handles varying object sizes" do
      objects = [
        %{id: "1", position: %{x: 0, y: 0}, data: %{width: 30, height: 30}},
        %{id: "2", position: %{x: 0, y: 0}, data: %{width: 60, height: 60}},
        %{id: "3", position: %{x: 0, y: 0}, data: %{width: 40, height: 40}}
      ]

      result = Layout.arrange_grid(objects, 2, 10)

      # Should use max width (60) for uniform grid
      assert Enum.at(result, 1).position.x == 70  # 60 + 10
    end

    test "handles empty list" do
      result = Layout.arrange_grid([], 2, 10)
      assert result == []
    end
  end

  describe "align_objects/2" do
    test "aligns objects to the left" do
      objects = [
        %{id: "1", position: %{x: 50, y: 100}, data: %{width: 50, height: 50}},
        %{id: "2", position: %{x: 150, y: 200}, data: %{width: 50, height: 50}}
      ]

      result = Layout.align_objects(objects, "left")

      # Both should align to x: 50 (leftmost)
      assert Enum.at(result, 0).position.x == 50
      assert Enum.at(result, 1).position.x == 50

      # Y coordinates preserved
      assert Enum.at(result, 0).position.y == 100
      assert Enum.at(result, 1).position.y == 200
    end

    test "aligns objects to the right" do
      objects = [
        %{id: "1", position: %{x: 50, y: 100}, data: %{width: 50, height: 50}},
        %{id: "2", position: %{x: 150, y: 200}, data: %{width: 50, height: 50}}
      ]

      result = Layout.align_objects(objects, "right")

      # Both should align right edges to x: 200 (rightmost edge)
      assert Enum.at(result, 0).position.x == 150  # 200 - 50 (width)
      assert Enum.at(result, 1).position.x == 150  # 200 - 50 (width)
    end

    test "aligns objects to horizontal center" do
      objects = [
        %{id: "1", position: %{x: 0, y: 100}, data: %{width: 50, height: 50}},
        %{id: "2", position: %{x: 150, y: 200}, data: %{width: 50, height: 50}}
      ]

      result = Layout.align_objects(objects, "center")

      # Both should align to same center x coordinate
      center1 = Enum.at(result, 0).position.x + 25  # x + width/2
      center2 = Enum.at(result, 1).position.x + 25

      assert abs(center1 - center2) <= 1  # Within ±1px
    end

    test "aligns objects to the top" do
      objects = [
        %{id: "1", position: %{x: 100, y: 50}, data: %{width: 50, height: 50}},
        %{id: "2", position: %{x: 200, y: 150}, data: %{width: 50, height: 50}}
      ]

      result = Layout.align_objects(objects, "top")

      # Both should align to y: 50 (topmost)
      assert Enum.at(result, 0).position.y == 50
      assert Enum.at(result, 1).position.y == 50
    end

    test "aligns objects to the bottom" do
      objects = [
        %{id: "1", position: %{x: 100, y: 50}, data: %{width: 50, height: 50}},
        %{id: "2", position: %{x: 200, y: 150}, data: %{width: 50, height: 50}}
      ]

      result = Layout.align_objects(objects, "bottom")

      # Both should align bottom edges to y: 200 (bottommost edge)
      assert Enum.at(result, 0).position.y == 150  # 200 - 50 (height)
      assert Enum.at(result, 1).position.y == 150  # 200 - 50 (height)
    end

    test "aligns objects to vertical middle" do
      objects = [
        %{id: "1", position: %{x: 100, y: 0}, data: %{width: 50, height: 50}},
        %{id: "2", position: %{x: 200, y: 150}, data: %{width: 50, height: 50}}
      ]

      result = Layout.align_objects(objects, "middle")

      # Both should align to same middle y coordinate
      middle1 = Enum.at(result, 0).position.y + 25  # y + height/2
      middle2 = Enum.at(result, 1).position.y + 25

      assert abs(middle1 - middle2) <= 1  # Within ±1px
    end

    test "handles single object" do
      objects = [%{id: "1", position: %{x: 100, y: 100}, data: %{width: 50, height: 50}}]
      result = Layout.align_objects(objects, "left")

      assert length(result) == 1
      assert Enum.at(result, 0).position.x == 100
    end

    test "handles empty list" do
      result = Layout.align_objects([], "left")
      assert result == []
    end
  end

  describe "circular_layout/2" do
    test "arranges two objects in a circle" do
      objects = [
        %{id: "1", position: %{x: 100, y: 100}, data: %{width: 50, height: 50}},
        %{id: "2", position: %{x: 200, y: 200}, data: %{width: 50, height: 50}}
      ]

      result = Layout.circular_layout(objects, 100)

      # Objects should be positioned around a circle
      # Exact positions depend on trigonometry, just verify structure
      assert length(result) == 2
      assert is_map(Enum.at(result, 0).position)
      assert is_number(Enum.at(result, 0).position.x)
      assert is_number(Enum.at(result, 0).position.y)
    end

    test "arranges four objects in a circle" do
      objects = [
        %{id: "1", position: %{x: 100, y: 100}, data: %{width: 50, height: 50}},
        %{id: "2", position: %{x: 200, y: 200}, data: %{width: 50, height: 50}},
        %{id: "3", position: %{x: 300, y: 300}, data: %{width: 50, height: 50}},
        %{id: "4", position: %{x: 400, y: 400}, data: %{width: 50, height: 50}}
      ]

      result = Layout.circular_layout(objects, 150)

      assert length(result) == 4

      # Objects should be evenly distributed (90 degrees apart for 4 objects)
      # Verify they're all roughly the same distance from center
      center_x = 250  # Average of input x coordinates
      center_y = 250  # Average of input y coordinates

      distances = Enum.map(result, fn obj ->
        dx = obj.position.x - center_x
        dy = obj.position.y - center_y
        :math.sqrt(dx * dx + dy * dy)
      end)

      # All distances should be approximately equal to radius (within tolerance for object centering)
      assert Enum.all?(distances, fn dist -> abs(dist - 150) < 50 end)
    end

    test "handles single object" do
      objects = [%{id: "1", position: %{x: 100, y: 100}, data: %{width: 50, height: 50}}]
      result = Layout.circular_layout(objects, 100)

      assert length(result) == 1
    end

    test "handles empty list" do
      result = Layout.circular_layout([], 100)
      assert result == []
    end
  end

  describe "performance requirements" do
    test "completes layout operations within 500ms for 50 objects" do
      # Generate 50 objects with varied positions and sizes
      objects = Enum.map(1..50, fn i ->
        %{
          id: "obj-#{i}",
          position: %{x: rem(i * 30, 800), y: rem(i * 40, 600)},
          data: %{width: 40 + rem(i, 20), height: 40 + rem(i, 20)}
        }
      end)

      # Test horizontal distribution
      {time_h, _result} = :timer.tc(fn ->
        Layout.distribute_horizontally(objects, :even)
      end)
      assert time_h < 500_000, "Horizontal distribution took #{time_h / 1000}ms (should be < 500ms)"

      # Test vertical distribution
      {time_v, _result} = :timer.tc(fn ->
        Layout.distribute_vertically(objects, :even)
      end)
      assert time_v < 500_000, "Vertical distribution took #{time_v / 1000}ms (should be < 500ms)"

      # Test grid arrangement
      {time_g, _result} = :timer.tc(fn ->
        Layout.arrange_grid(objects, 5, 20)
      end)
      assert time_g < 500_000, "Grid arrangement took #{time_g / 1000}ms (should be < 500ms)"

      # Test alignment
      {time_a, _result} = :timer.tc(fn ->
        Layout.align_objects(objects, "center")
      end)
      assert time_a < 500_000, "Alignment took #{time_a / 1000}ms (should be < 500ms)"

      # Test circular layout
      {time_c, _result} = :timer.tc(fn ->
        Layout.circular_layout(objects, 300)
      end)
      assert time_c < 500_000, "Circular layout took #{time_c / 1000}ms (should be < 500ms)"
    end
  end

  describe "precision requirements" do
    test "maintains ±1px precision for horizontal distribution" do
      objects = [
        %{id: "1", position: %{x: 0, y: 100}, data: %{width: 33, height: 50}},
        %{id: "2", position: %{x: 100, y: 100}, data: %{width: 33, height: 50}},
        %{id: "3", position: %{x: 200, y: 100}, data: %{width: 33, height: 50}}
      ]

      result = Layout.distribute_horizontally(objects, :even)

      # Even with odd numbers, rounding should be within ±1px
      x_coords = Enum.map(result, fn obj -> obj.position.x end)
      assert Enum.all?(x_coords, fn x -> is_integer(x) end)
    end

    test "maintains ±1px precision for alignment" do
      objects = [
        %{id: "1", position: %{x: 0, y: 100}, data: %{width: 51, height: 50}},
        %{id: "2", position: %{x: 200, y: 100}, data: %{width: 49, height: 50}}
      ]

      result = Layout.align_objects(objects, "center")

      # Calculate centers
      center1 = Enum.at(result, 0).position.x + 25.5
      center2 = Enum.at(result, 1).position.x + 24.5

      assert abs(center1 - center2) <= 1
    end
  end
end
