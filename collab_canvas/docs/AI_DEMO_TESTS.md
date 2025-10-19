# AI Canvas Agent - Demo Test Commands

This document provides a comprehensive list of AI commands to demonstrate the full capabilities of the CollabCanvas AI agent for evaluation.

## Test Strategy for Maximum Points (25 total)

### Command Breadth & Capability (10 points - need 9-10)
**Goal**: Demonstrate 8+ distinct command types across all categories

### Complex Command Execution (8 points - need 7-8)
**Goal**: Show complex commands producing 3+ properly arranged elements with smart positioning

### AI Performance & Reliability (7 points - need 6-7)
**Goal**: Sub-2 second responses, 90%+ accuracy, natural UX, shared state

---

## Category 1: Creation Commands (Need at least 2, recommend 4)

### Basic Shape Creation
```
Create a red circle at position 100, 200
```
**Expected**: Single red circle at specified coordinates

```
Make a 200x300 blue rectangle
```
**Expected**: Blue rectangle with exact dimensions at default position

```
Add 5 green circles in a row
```
**Expected**: 5 green circles arranged horizontally with automatic spacing

### Text Creation
```
Add a text layer that says 'Hello World'
```
**Expected**: Text object with "Hello World" content

```
Create a title that says 'CollabCanvas Demo' at the top center
```
**Expected**: Text positioned at top-center using semantic positioning

---

## Category 2: Manipulation Commands (Need at least 2, recommend 5)

### Movement
```
Move the blue rectangle to the center
```
**Expected**: Selected/identified blue rectangle moves to canvas center

```
Move all the green squares down 100 pixels
```
**Expected**: All green square objects shift down by 100px

### Resizing
```
Resize the circle to be twice as big
```
**Expected**: Circle dimensions doubled

```
Make all rectangles 150 pixels wide
```
**Expected**: All rectangle objects resized to width=150

### Rotation
```
Rotate the text 45 degrees
```
**Expected**: Text rotated 45° clockwise

### Style Changes
```
Change the red circles to blue
```
**Expected**: All red circle objects change color to blue

### Layer Ordering
```
Put the red circle behind the blue rectangle
```
**Expected**: Red circle's z-index adjusted to appear behind blue rectangle

```
Bring the text to the front
```
**Expected**: Text object moved to top of stacking order

---

## Category 3: Layout Commands (Need at least 1, recommend 4)

### Linear Arrangements
```
Arrange selected objects in a horizontal row
```
**Expected**: Selected objects arranged horizontally with even spacing

```
Arrange these shapes in a vertical column with 30px spacing
```
**Expected**: Vertical arrangement with exact 30px gaps

### Grid Layouts
```
Create a grid of 3x3 blue squares
```
**Expected**: 9 blue squares in a 3-row, 3-column grid

```
Arrange all objects in 2 rows
```
**Expected**: All objects distributed into 2 rows, auto-calculating columns

### Circular & Pattern Layouts
```
Arrange selected objects in a circle
```
**Expected**: Objects positioned in circular formation

```
Arrange all the circles in a star pattern
```
**Expected**: Circle objects arranged in 5-pointed star (or specified points)

---

## Category 4: Complex Commands (Need at least 1, recommend 3)

### UI Component Creation
```
Create a login form with username and password fields
```
**Expected Output**:
- 3+ elements (labels, input fields, button)
- Vertically stacked layout
- Proper spacing and alignment
- Professional styling

```
Build a navigation bar with 4 menu items
```
**Expected Output**:
- Container rectangle
- 4 text elements (Home, About, Services, Contact)
- Horizontally arranged
- Proper spacing

```
Make a card layout with title, image, and description
```
**Expected Output**:
- Card container
- Title text at top
- Image placeholder rectangle
- Description text below
- Properly arranged vertically

---

## Category 5: Selection Commands (Bonus - shows advanced capability)

### Semantic Selection
```
Select all the green squares
```
**Expected**: All square-shaped green rectangles selected (where width ≈ height)

```
Select all circles
```
**Expected**: All circle-type objects selected

```
Select the objects on the left half of the canvas
```
**Expected**: All objects with x < viewport_center selected

```
Select all large blue objects
```
**Expected**: Blue objects above size threshold selected

---

## Category 6: Combined Operations (Advanced - shows intelligence)

### Selection + Manipulation
```
Select all red objects and move them to the top
```
**Expected**:
1. Selects all red objects
2. Moves them to top of canvas
3. Both operations execute in sequence

```
Select the green squares and arrange them in a circle
```
**Expected**:
1. Selects green square objects
2. Arranges them in circular pattern

### Multi-Step Complex Commands
```
Create 6 blue circles and arrange them in 2 rows
```
**Expected**:
1. Creates 6 blue circles
2. Automatically arranges them in 2x3 grid

```
Make a triangle shape with 6 orange circles
```
**Expected**:
1. Creates 6 orange circles
2. Arranges them in triangular pattern (1, 2, 3 rows)

---

## Recommended Demo Flow (Optimized for Evaluation)

### Part 1: Basic Commands (Show breadth - 2 minutes)
1. **Create** `Create a red circle at position 100, 200`
2. **Create** `Make a 200x300 blue rectangle`
3. **Text** `Add a text layer that says 'Demo Title'`
4. **Move** `Move the blue rectangle to the center`
5. **Resize** `Make the circle twice as big`
6. **Rotate** `Rotate the text 45 degrees`
7. **Style** `Change the red circle to green`
8. **Layer** `Put the green circle behind the blue rectangle`
9. **Layout** `Arrange these shapes in a horizontal row`

### Part 2: Complex Commands (Show sophistication - 2 minutes)
10. **Complex UI** `Create a login form with username and password fields`
    - Watch for 3+ elements, proper arrangement
11. **Complex UI** `Build a navigation bar with 4 menu items`
    - Watch for horizontal layout, spacing
12. **Complex UI** `Make a card layout with title, image, and description`
    - Watch for vertical stacking, styling

### Part 3: Advanced Features (Show intelligence - 1 minute)
13. **Selection** `Create 5 orange circles in a row`
14. **Selection** `Select all circles`
15. **Combined** `Arrange them in a star pattern`
    - Shows selection + layout combination
16. **Grid** `Create a grid of 3x3 blue squares`
    - Shows complex creation + layout

### Part 4: Multi-User Test (Show shared state - 1 minute)
17. Open two browser windows
18. Window 1: `Create a red square`
19. Window 2: Verify square appears
20. Window 2: `Move the red square to position 300, 300`
21. Window 1: Verify movement
22. Both windows: Issue AI commands simultaneously

---

## Performance Benchmarks

| Command Type | Target Response Time | Expected Accuracy |
|--------------|---------------------|-------------------|
| Simple creation | < 1 second | 100% |
| Simple manipulation | < 1 second | 100% |
| Layout (5-10 objects) | < 1.5 seconds | 95% |
| Complex UI components | < 2 seconds | 90% |
| Selection + operation | < 2 seconds | 90% |

---

## Known Edge Cases & Tips

### For Best Results:
1. **Be specific with colors**: Use "red", "blue", "green" rather than "crimson" or "azure"
2. **Use semantic positions**: "at the top", "in the center", "on the left" work better than arbitrary coordinates
3. **Select before complex layouts**: For better control, select objects first, then apply layout
4. **Squares vs Rectangles**: The AI distinguishes squares (width ≈ height) from rectangles (different dimensions)

### Common Failure Modes to Test:
1. **Ambiguous references**: "Move that square" without selection → AI should ask for clarification
2. **Complex multi-step**: May need to break into 2 commands if very complex
3. **Very large counts**: "Create 100 circles" may be slow but should work

---

## Scoring Strategy

### To Achieve 23-25/25 (Excellent):
- ✅ Demonstrate **10+ distinct commands** (not just 8)
- ✅ Show **all 4 categories** with multiple examples each
- ✅ Execute **3 complex UI commands** flawlessly (login form, navbar, card)
- ✅ Show **sub-2 second** responses with timer visible
- ✅ Demonstrate **multi-user** AI usage working simultaneously
- ✅ Show **selection + manipulation** combinations
- ✅ Display **90%+ success rate** (expect 1-2 retries max in 15+ commands)

### Bonus Demonstrable Features:
- Voice input (push-to-talk microphone button)
- AI interaction history sidebar
- Real-time collaboration (cursor tracking + PubSub)
- Semantic selection (by color, size, type, position)
- Advanced layouts (star, circular, grid, custom patterns)
- Component library (login forms, navbars, cards)

---

## Quick Reference Command List (Copy-Paste Ready)

```bash
# CREATION (4 commands)
Create a red circle at position 100, 200
Make a 200x300 blue rectangle
Add a text layer that says 'Hello World'
Create 5 green circles in a row

# MANIPULATION (7 commands)
Move the blue rectangle to the center
Resize the circle to be twice as big
Rotate the text 45 degrees
Change the red circles to blue
Move all the green squares down 100 pixels
Put the red circle behind the blue rectangle
Bring the text to the front

# LAYOUT (4 commands)
Arrange selected objects in a horizontal row
Create a grid of 3x3 blue squares
Arrange these shapes in a circle
Arrange all the circles in a star pattern

# COMPLEX (3 commands)
Create a login form with username and password fields
Build a navigation bar with 4 menu items
Make a card layout with title, image, and description

# SELECTION (2 commands)
Select all circles
Select all the green squares

# COMBINED (2 commands)
Select all red objects and move them to the top
Create 6 blue circles and arrange them in 2 rows
```

**Total**: 22 distinct commands demonstrating comprehensive AI capabilities
