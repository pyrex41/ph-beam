PRD 2: Advanced Design & Snapping Engine
Document Status: Draft
Author: Gemini AI
Date: October 18, 2025
1. Introduction & Problem Statement
CollabCanvas offers a flexible, free-form canvas, but it lacks the precision tools necessary for creating professional, well-aligned designs. Users currently have to align objects manually by sight, which is tedious, error-prone, and inefficient. The absence of snapping and smart distribution tools is a major usability gap compared to industry-standard design software.
This PRD outlines the requirements to build an advanced design engine that provides users with dynamic snapping guides and smart distribution actions, transforming the canvas from a simple drawing board into a powerful design tool.
2. Goals & Objectives
Goal 1: Enable Pixel-Perfect Alignment. Empower users to create perfectly aligned layouts with minimal effort through dynamic visual guides.
Goal 2: Increase Design Workflow Velocity. Drastically reduce the time and effort required to arrange, align, and distribute objects on the canvas.
Goal 3: Bridge the Gap to Professional Design Tools. Introduce foundational design features that users of tools like Figma or Sketch expect.
3. Success Metrics
Task Completion Time: The time required to create a perfectly aligned 3-column card layout should decrease by at least 50%.
Reduction in "Nudging": A 75% reduction in the number of small, corrective update_object events sent per user session, indicating users are achieving alignment on the first try.
User Satisfaction: Achieve a satisfaction score of 4.5/5 or higher in user surveys specifically asking about the new alignment and distribution tools.
4. Target User Persona
Designer / Prototyper: A user creating structured layouts, wireframes, or UI mockups. They require precision and speed and are frustrated by the current lack of alignment tools.
5. Detailed Feature Requirements
User Story: As a designer, when I drag an object near another one, I want to see clear red lines indicating when their edges or centers are aligned, and I want my object to "snap" into that position.
Functional Requirements:
While a user is dragging an object, the system must detect proximity to the edges (top, bottom, left, right) and centers (horizontal, vertical) of other nearby static objects.
When alignment is detected within a given threshold (e.g., 5px), a visual guide line must be rendered on the canvas connecting the aligned parts.
The position of the object being dragged should be automatically adjusted ("snapped") to the detected alignment guide.
Technical Implementation Guidance:
This is a frontend-only feature. All logic should reside within the PixiJS implementation in assets/js/core/canvas_manager.js.
In the onDragMove handler for an object, iterate through all other objects to find potential snap targets.
Calculate the positions of all potential alignment guides (e.g., target.x, target.x + target.width/2, etc.).
If the dragged object is near a guide, adjust its position and render the guide line using PixiJS.Graphics.
The backend is not involved during the drag; it only receives the final snapped position on onDragEnd.
User Story: As a designer, I want the ability to toggle a visual grid on the canvas, and when it's active, all objects I move or create should snap to the nearest grid line for a structured layout.
Functional Requirements:
The UI must provide a button to toggle the visibility of a background grid.
When the grid is active, any object being dragged must snap its top-left corner to the nearest grid intersection point.
Technical Implementation Guidance:
Frontend: In canvas_manager.js, create a TilingSprite or Graphics object to render the grid.
During a drag, if snapping is enabled, round the object's x and y coordinates to the nearest multiple of the grid size (e.g., Math.round(pos.x / gridSize) * gridSize).
User Story: As a user, after selecting three or more objects, I want to click a button in the UI to instantly distribute them evenly, either horizontally or vertically.
Functional Requirements:
When two or more objects are selected, new UI buttons for "Distribute Horizontally" and "Distribute Vertically" must become active.
Clicking these buttons will trigger an event that respositions the selected objects to have equal spacing between them.
Technical Implementation Guidance:
The core logic for this already exists in lib/collab_canvas/ai/layout.ex (distribute_horizontally/2 and distribute_vertically/2).
Add new buttons to the CanvasLive template that are visible when multiple objects are selected.
Create a new handle_event("distribute_objects", ...) in CanvasLive.
This event handler should call the existing layout functions and broadcast the batch of updated objects.
6. Out of Scope
This PRD is focused on 2D positional snapping. Rotational snapping (e.g., snapping to 15-degree increments) is not included.
"Smart Guides" that show the distance between objects are out of scope for this version.
AI-driven arrangement commands are separate from these manual UI-driven tools.
