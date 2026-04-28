# MCP Flow DSL Specification Compliance Tests

This directory contains tests that verify the MCP Flow Runtime implementation complies with the MCP Flow DSL v1.0 Specification.

## Test Organization

Tests are organized by specification sections:

- `action_types/` - Tests for all action types defined in the spec
- `trigger_types/` - Tests for all trigger types 
- `expression_language/` - Tests for expression evaluation
- `resource_types/` - Tests for hardware resource definitions
- `configuration/` - Tests for runtime and system configuration
- `state_management/` - Tests for state variable types and constraints
- `process_model/` - Tests for process lifecycle and execution
- `channel_types/` - Tests for inter-process communication
- `error_handling/` - Tests for error recovery and handling
- `security/` - Tests for sandboxing and access control

## Running Tests

Run all specification compliance tests:
```bash
dart test test/spec_compliance/
```

Run specific category:
```bash
dart test test/spec_compliance/action_types/
```

## Coverage Goals

Each test file should:
1. Reference the specific section of the MCP Flow DSL spec being tested
2. Test both positive cases (spec compliance) and negative cases (spec violations)
3. Verify exact behavior matches specification, not just that code works