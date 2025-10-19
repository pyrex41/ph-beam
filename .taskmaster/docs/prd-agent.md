PRD 1: AI Agent Performance & Parsing Engine
Document Status: Draft
Author: Gemini AI
Date: October 18, 2025
1. Introduction & Problem Statement
The AI Assistant is a key differentiator for CollabCanvas, enabling users to generate complex designs from natural language. However, its current architecture leads to performance bottlenecks and inconsistent behavior. Users experience noticeable latency, especially for commands that generate multiple objects, as each operation is processed sequentially. Furthermore, every command, no matter how simple, requires an expensive and time-consuming round-trip to an external LLM, and the system lacks resilience against inconsistent or failed API responses.
This PRD outlines the necessary architectural enhancements to the AI toolchain to make it dramatically faster, more reliable, and more efficient, transforming the AI Assistant into a production-grade, highly-performant feature.
2. Goals & Objectives
Goal 1: Achieve Sub-Second Performance for Simple Commands. Drastically reduce the latency for deterministic commands that do not require complex language interpretation.
Goal 2: Optimize Bulk Object Generation. Significantly speed up the creation and arrangement of multiple objects resulting from a single AI command.
Goal 3: Improve AI Parsing Consistency. Increase the reliability of the AI's tool selection and parameter generation, reducing the rate of failed or nonsensical operations.
3. Success Metrics
P95 Latency for "Short-Circuited" Commands: Commands like "delete selected" or "group" must complete in < 300ms.
Bulk Generation Speed: An AI command that creates 10 objects (e.g., "create 10 red squares") must be fully rendered on the canvas in < 2 seconds.
AI Command Success Rate: The rate of commands that execute without error should increase to >95%.
API Cost Reduction: Achieve a >20% reduction in calls to the external LLM API for common user sessions through caching and short-circuiting.
4. Target User Persona
Power User / Designer: A user who relies on the AI Assistant for rapid prototyping and complex layout generation. They are sensitive to latency and expect the tool to be fast and reliable.
5. Detailed Feature Requirements
User Story: As a user, when I ask the AI to "create a login form," I want all its constituent parts (labels, inputs, button) to appear almost instantly, rather than waiting for each piece to be created one-by-one.
Functional Requirements:
The AI Agent must be refactored to process tool calls in parallel when they are independent (e.g., multiple create_shape calls).
The Canvases context must support batched database operations (e.g., a create_objects_batch function) that use a single transaction.
Batched operations must trigger a single PubSub broadcast containing all the created/updated objects to reduce network chatter. CanvasLive must be updated to handle this new event.
Technical Implementation Guidance:
In lib/collab_canvas/ai/agent.ex, update process_tool_calls to group all create_* calls and execute them in one go using a new batch function.
Use Task.async_stream for parallelizing independent network-bound or CPU-bound tasks within the agent.
In lib/collab_canvas/canvases.ex, implement create_objects_batch(canvas_id, list_of_attrs) using Ecto.Multi to ensure atomicity.
User Story: As a user, when I issue a simple, direct command like "group these objects," I expect it to execute instantly, just like clicking a UI button.
Functional Requirements:
Before making an LLM API call, the Agent must check the incoming command against a predefined list of simple, deterministic actions.
If a command is matched (e.g., "delete selected", "show labels", "group"), the Agent must bypass the LLM and directly construct the appropriate tool call(s) for execution.
Technical Implementation Guidance:
In lib/collab_canvas/ai/agent.ex, create a short_circuit_command/2 private function that is called at the beginning of execute_command.
Use pattern matching on the command string to identify and handle these simple cases.
This function should return {:ok, tool_calls} on a match, or :next to proceed with the standard LLM flow.
User Story: As a developer, I want the AI agent to be more resilient to inconsistent LLM outputs and to avoid re-processing identical commands repeatedly.
Functional Requirements:
The AI Agent must cache the tool call responses from the LLM for identical commands, with a short TTL (e.g., 5 minutes).
The tool definitions in lib/collab_canvas/ai/tools.ex should be enhanced with few-shot examples in their descriptions to guide the LLM toward generating more consistent and valid parameters.
Technical Implementation Guidance:
Use an ETS table, managed by the Application supervisor, to store the cache (command -> tool_calls). Check ETS before making an API call.
Update the description fields in tools.ex with examples, e.g., "Example: User says 'make a red square', you call create_shape(type: 'rectangle', fill: '#FF0000', ...)".
6. Out of Scope
This PRD does not cover adding new AI tools, only improving the performance and reliability of the existing toolchain.
UI-side streaming of AI results (showing progress as objects are created) is not in scope for this iteration.

