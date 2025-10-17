# AI Performance Optimization - Task Breakdown

This document provides task breakdown for parsing into Task Master.

---

## Task 1: Implement Command Classifier Module

**Priority:** High
**Estimated Time:** 4 hours

Create a command classification system that routes commands to the optimal LLM provider based on complexity analysis.

### Requirements

- Pattern-based classification using regex
- Classify commands as :fast_path or :complex_path
- Analyze command for multiple operations
- Detect contextual references (this, that, these)
- Detect component creation requests
- Detect layout operations
- Default to :fast_path for unknown patterns
- Add debug logging for classification decisions

### Implementation Details

Create `lib/collab_canvas/ai/command_classifier.ex` with:
- Module with `classify/1` function returning atom
- List of @simple_patterns for regex matching
- Helper functions for operation counting
- Helper functions for context detection
- Helper functions for component detection
- Helper functions for layout detection
- Logging for monitoring and tuning

### Test Strategy

- Unit tests for each classification type
- Test all simple patterns match correctly
- Test multi-operation detection
- Test context detection
- Test component detection
- Test layout detection
- Test default behavior

### Acceptance Criteria

- Module compiles without errors
- All tests pass
- Simple commands classified as :fast_path
- Complex commands classified as :complex_path
- Logging shows classification reasoning
- Documentation complete

---

## Task 2: Create Provider Behaviour and Groq Implementation

**Priority:** High
**Estimated Time:** 6 hours

Implement LLM provider abstraction layer with Groq as primary provider.

### Requirements

- Define Provider behaviour with callbacks
- Implement Groq provider using OpenAI-compatible API
- Convert tool definitions to OpenAI format
- Parse Groq responses to standard format
- Handle API errors gracefully
- Add latency tracking
- Support environment variable configuration

### Implementation Details

Create `lib/collab_canvas/ai/provider.ex`:
- @callback call/3 for API calls
- @callback model_name/0 for model identification
- @callback avg_latency/0 for performance tracking

Create `lib/collab_canvas/ai/providers/groq.ex`:
- Implement Provider behaviour
- Use llama-3.3-70b-versatile model
- Build request with proper format
- Convert tools to OpenAI function calling format
- Parse tool calls from response
- Handle errors with detailed logging

### Test Strategy

- Unit tests for tool format conversion
- Mock API tests for request/response
- Integration tests with real Groq API (tagged)
- Error handling tests
- Timeout tests

### Acceptance Criteria

- Behaviour defined correctly
- Groq provider implements all callbacks
- Tool conversion works for all tool types
- Response parsing handles all cases
- Error messages are clear
- API key from environment variable works
- All tests pass

---

## Task 3: Integrate Command Routing in Agent Module

**Priority:** High
**Estimated Time:** 4 hours

Update Agent module to route commands through classifier to appropriate provider.

### Requirements

- Use CommandClassifier to classify all commands
- Route :fast_path to Groq provider
- Route :complex_path to Groq (with fallback)
- Implement fallback to Claude if Groq fails
- Add performance logging (latency tracking)
- Preserve all existing functionality
- Maintain backward compatibility

### Implementation Details

Modify `lib/collab_canvas/ai/agent.ex`:
- Add CommandClassifier.classify/1 call
- Add provider selection logic
- Implement fallback mechanism
- Add timing instrumentation
- Add detailed logging
- Keep existing process_tool_calls logic

### Test Strategy

- Test classification integration
- Test Groq provider selection
- Test Claude fallback on Groq failure
- Test performance logging
- Integration tests for end-to-end flow
- Verify existing tests still pass

### Acceptance Criteria

- Classification happens before provider call
- Groq used for :fast_path commands
- Claude fallback works correctly
- Performance logs show provider and latency
- All existing tests pass
- No breaking changes to API

---

## Task 4: Add Parallel Tool Execution

**Priority:** High
**Estimated Time:** 5 hours

Replace sequential tool execution with parallel execution using Task.async_stream.

### Requirements

- Use Task.async_stream for concurrent execution
- Set max_concurrency to 10
- Set timeout to 5 seconds per tool
- Handle task failures gracefully
- Maintain execution order in results
- Add performance metrics
- Preserve error handling

### Implementation Details

Modify `lib/collab_canvas/ai/agent.ex`:
- Create process_tool_calls_parallel/2 function
- Use Task.async_stream with tool_calls
- Configure max_concurrency and timeout
- Map stream results to standard format
- Handle {:ok, result} and {:exit, reason}
- Log execution time for comparison

### Test Strategy

- Unit tests for parallel execution
- Test with 1, 5, 10 tools
- Test timeout handling
- Test error isolation (one failure doesn't break others)
- Performance tests comparing parallel vs sequential
- Integration tests with real canvas operations

### Acceptance Criteria

- Parallel execution works correctly
- 5 tools complete in ~250ms (vs 1000ms sequential)
- Timeouts handled without crashing
- Individual tool failures isolated
- Results maintain correct order
- Performance improvement measurable
- All tests pass

---

## Task 5: Create Tool Behaviour System

**Priority:** Medium
**Estimated Time:** 8 hours

Implement modular tool system with behaviours for extensibility and type safety.

### Requirements

- Define ToolBehaviour with callbacks
- Create ToolRegistry with compile-time map
- Support O(1) tool lookup
- Add Ecto.Changeset validation
- Make tools easy to add/extend
- Generate tool definitions automatically

### Implementation Details

Create `lib/collab_canvas/ai/tool_behaviour.ex`:
- @callback schema/0 for tool definition
- @callback validate/1 for input validation
- @callback execute/3 for tool execution
- Optional callbacks for caching

Create `lib/collab_canvas/ai/tool_registry.ex`:
- @tools list of tool modules
- @tool_map compile-time map for O(1) lookup
- get_tool/1 function
- execute_tool/4 function
- get_tool_definitions/0 function

### Test Strategy

- Unit tests for behaviour definition
- Tests for registry lookup
- Tests for tool execution
- Tests for validation
- Performance tests for O(1) lookup
- Tests for extensibility (adding new tools)

### Acceptance Criteria

- Behaviour compiles correctly
- Registry has O(1) lookup
- All tools implement behaviour
- Validation uses Ecto
- Easy to add new tools
- Documentation complete
- All tests pass

---

## Task 6: Refactor Core Tools to Behaviour Pattern

**Priority:** Medium
**Estimated Time:** 6 hours

Refactor existing tools to implement ToolBehaviour.

### Requirements

- CreateShape implements ToolBehaviour
- CreateText implements ToolBehaviour
- MoveObject implements ToolBehaviour
- ResizeObject implements ToolBehaviour
- DeleteObject implements ToolBehaviour
- CreateComponent implements ToolBehaviour
- Each tool has Ecto schema for validation
- Each tool is in separate file

### Implementation Details

For each tool, create `lib/collab_canvas/ai/tools/{tool_name}.ex`:
- @behaviour ToolBehaviour
- use Ecto.Schema
- embedded_schema with fields
- schema/0 implementation
- validate/1 with Ecto.Changeset
- execute/3 with canvas operations

Tools to create:
- create_shape.ex
- create_text.ex
- move_object.ex
- resize_object.ex
- delete_object.ex
- create_component.ex

### Test Strategy

- Unit tests for each tool's validation
- Unit tests for each tool's execution
- Integration tests with canvas
- Test invalid inputs return errors
- Test valid inputs execute correctly

### Acceptance Criteria

- All 6 tools refactored
- Each tool implements ToolBehaviour
- Validation works with Ecto
- All tools registered in ToolRegistry
- Existing functionality preserved
- Tests pass for all tools

---

## Task 7: Add Layout Tools

**Priority:** Low
**Estimated Time:** 8 hours

Implement AI-powered layout and arrangement tools.

### Requirements

- Create Layout module with algorithms
- Implement ArrangeObjects tool
- Implement AlignObjects tool
- Support multiple layout types
- Add layout patterns to classifier

### Implementation Details

Create `lib/collab_canvas/ai/layout.ex`:
- distribute_horizontally/2
- distribute_vertically/2
- arrange_grid/3
- circular_layout/2
- align_objects/2

Create `lib/collab_canvas/ai/tools/arrange_objects.ex`:
- Implements ToolBehaviour
- Uses Layout module
- Supports: horizontal, vertical, grid, circular, stack

Create `lib/collab_canvas/ai/tools/align_objects.ex`:
- Implements ToolBehaviour
- Uses Layout module
- Supports: left, center, right, top, middle, bottom

### Test Strategy

- Unit tests for layout algorithms
- Tests for each layout type
- Tests for alignment types
- Integration tests with canvas
- Test edge cases (1 object, 100 objects)

### Acceptance Criteria

- Layout algorithms work correctly
- ArrangeObjects tool working
- AlignObjects tool working
- Commands like "arrange in grid" work
- Commands like "align left" work
- All tests pass

---

## Task 8: Add Streaming Support (Optional)

**Priority:** Low
**Estimated Time:** 10 hours

Implement streaming responses for improved perceived performance.

### Requirements

- Add streaming to Groq provider
- Create StreamingAgent module
- Update LiveView for incremental updates
- Add progress indicators
- Maintain backward compatibility

### Implementation Details

Modify `lib/collab_canvas/ai/providers/groq.ex`:
- Add call_streaming/3 function
- Parse Server-Sent Events
- Yield tool calls as they arrive

Create `lib/collab_canvas/ai/streaming_agent.ex`:
- execute_command_streaming/3 function
- Stream tool calls to execution
- Broadcast each result immediately

Modify `lib/collab_canvas_web/live/canvas_live.ex`:
- Handle {:ai_tool_result, result} messages
- Update UI incrementally
- Show progress indicators

### Test Strategy

- Unit tests for streaming parser
- Integration tests with LiveView
- Test progress indicators
- Test error handling mid-stream
- Performance tests for time-to-first-result

### Acceptance Criteria

- Streaming works correctly
- First result in < 0.5s
- Progress indicators show
- Errors handled gracefully
- Non-streaming path still works
- All tests pass

---

## Task 9: Add Configuration and Feature Flags

**Priority:** High
**Estimated Time:** 2 hours

Add configuration for providers and feature flags for rollout.

### Requirements

- Environment variables for API keys
- Config for default provider
- Config for fallback provider
- Feature flag for fast_path
- Config for timeouts

### Implementation Details

Update `config/config.exs`:
- Add :ai configuration block
- Set default_provider
- Set fallback_provider
- Add fast_path_enabled flag
- Add timeout configs

Update `config/test.exs`:
- Use deterministic settings for tests
- Disable fast_path in tests if needed

Update `.env.example`:
- Add GROQ_API_KEY
- Add CLAUDE_API_KEY (optional)

### Test Strategy

- Test config loading
- Test feature flag toggling
- Test environment variable reading
- Test defaults

### Acceptance Criteria

- Config file updated
- Environment variables documented
- Feature flags work
- Tests use test config
- Documentation updated

---

## Task 10: Add Performance Monitoring

**Priority:** Medium
**Estimated Time:** 4 hours

Add telemetry and monitoring for AI performance tracking.

### Requirements

- Emit telemetry events
- Track latency by command type
- Track provider usage
- Track error rates
- Log classification decisions

### Implementation Details

Add to `lib/collab_canvas/ai/agent.ex`:
- Emit :command_executed events
- Include duration, provider, classification
- Include success/failure

Add to `lib/collab_canvas/ai/telemetry.ex`:
- Event definitions
- Metric aggregation helpers
- Dashboard data functions

Optional: Add simple dashboard in LiveView

### Test Strategy

- Test event emission
- Test metric collection
- Test dashboard rendering
- Verify no performance impact

### Acceptance Criteria

- Telemetry events emitted
- Events include all metadata
- Metrics trackable
- Documentation for metrics
- No performance degradation

---

## Task 11: Write Comprehensive Tests

**Priority:** High
**Estimated Time:** 6 hours

Create comprehensive test suite for all new functionality.

### Requirements

- Unit tests for all modules
- Integration tests for end-to-end flow
- Performance tests for latency targets
- Error handling tests
- Fallback tests

### Implementation Details

Create test files:
- `test/collab_canvas/ai/command_classifier_test.exs`
- `test/collab_canvas/ai/providers/groq_test.exs`
- `test/collab_canvas/ai/tool_registry_test.exs`
- `test/collab_canvas/ai/tools/*_test.exs`
- `test/collab_canvas/ai/agent_performance_test.exs`

Include:
- @moduletag :external_api for API tests
- Performance benchmarks
- Mock API responses
- Error scenarios

### Test Strategy

- 90%+ code coverage
- All happy paths covered
- All error paths covered
- Performance targets validated
- Integration tests for real usage

### Acceptance Criteria

- All tests pass
- Coverage > 90%
- Performance tests validate < 1s for simple commands
- CI/CD integration working
- Documentation complete

---

## Task 12: Documentation and Migration Guide

**Priority:** Medium
**Estimated Time:** 3 hours

Create documentation for new AI system and migration guide.

### Requirements

- Update AGENTS.md with new architecture
- Document provider system
- Document tool behaviour system
- Create migration guide
- Update API documentation

### Implementation Details

Update `AGENTS.md`:
- Architecture overview
- Provider abstraction
- Command classification
- Tool behaviour system
- Performance characteristics

Create migration guide:
- Breaking changes (none expected)
- Configuration changes
- Environment variable setup
- Rollout strategy

### Test Strategy

- Review docs for accuracy
- Test examples work
- Validate configuration examples

### Acceptance Criteria

- AGENTS.md updated
- Migration guide complete
- Examples tested
- Configuration documented
- Diagrams updated
