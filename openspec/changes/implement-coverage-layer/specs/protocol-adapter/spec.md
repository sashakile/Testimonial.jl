## ADDED Requirements

### Requirement: [PROTO-001] Adapter protocol entry point
The system SHALL provide `Testimonial.run_adapter_protocol()` as a thin entry
point that reads one JSON command per line from stdin and writes one JSON
response per line to stdout, per testaruda's `TIA-ADAPT-001` protocol.

The entry point SHALL be wrapped in a shell script at `bin/testaruda_adapter.jl`
that testaruda's `testaruda.toml` can reference:

```toml
[adapters]
".jl" = "julia --project=. bin/testaruda_adapter.jl"
```

(The exact path depends on how Testimonial.jl is installed — local clone vs.
system package. The example assumes a local project clone.)

The adapter SHALL reuse core functions and SHALL NOT depend on `Persistence.jl`
or `GitDiff.jl` — testaruda's SQLite store is the system of record, and
testaruda's core handles diff parsing.

The adapter SHALL detect EOF on stdin (Julia's `readline(stdin)` returns
`nothing`) and exit cleanly, avoiding hanging when testaruda closes the pipe.

Each adapter instance uses a unique temporary directory for its coverage
recording, preventing `.jl.cov` path contention across concurrent adapter
instances spawned by testaruda for different file extensions.

Error responses SHALL follow testaruda's protocol format:
`{ "error": { "message": "..." } }`.

#### Scenario: Protocol main loop
- **WHEN** `run_adapter_protocol()` is called
- **THEN** it reads lines from stdin until EOF
- **AND** each line is parsed as a JSON command object
- **AND** a JSON response object is written to stdout for each command
- **AND** malformed JSON lines produce an error response without crashing
- **AND** EOF on stdin causes clean exit

#### Scenario: Unknown command
- **WHEN** a JSON command with an unknown `cmd` field is received
- **THEN** the response contains an error field indicating the unsupported command

### Requirement: [PROTO-002] handshake handler
The system SHALL respond to the `handshake` command with a static capability
declaration.

Response fields:
- `languages: ["julia"]`
- `granularity: "file"` (not `"symbol"` — no source-code symbol resolution)
- `capabilities: { symbol_model_complete: false, fingerprinting: true, runtime_edges: true }`

#### Scenario: Handshake response
- **WHEN** a `handshake` command is received
- **THEN** the response contains the static capability declaration above

### Requirement: [PROTO-003] discover handler
The system SHALL respond to the `discover` command by calling
`ASTParser.discover_testitems` and returning the discovered `@testitem` nodes.

Each node SHALL include:
- A unique node ID in the format `test_file:item_name`
- The test file path (absolute, normalized)
- The item name

#### Scenario: Discover test items
- **WHEN** a `discover` command is received
- **THEN** `ASTParser.discover_testitems` is called with the configured
  `test_directories`
- **AND** the response contains all discovered `@testitem` nodes

### Requirement: [PROTO-004] ingest handler
The system SHALL respond to the `ingest` command by recording the specified
test items via `CoverageLayer.record_item` and returning the resulting
file→line→test edges as runtime edges.

The handler SHALL:
1. Parse the item IDs from the `ingest` request.
2. Call `record_item` for each item.
3. Convert each `ItemCoverage` to edge data: for each (file, line) pair in
   the coverage, create a runtime edge.
4. Accumulate the results into an in-memory `session_coverage::Dict{NodeID, ItemCoverage}`
   map, keyed by node ID (`test_file:item_name`). This map is built incrementally
   across `ingest` calls in the same session and is queried by the `static-deps`
   handler (PROTO-005).
5. Return the edges inline in the `ingest` response, keyed by absolute path
   (normalized via `realpath`).
6. **Not persist anything locally** — testaruda's SQLite store is the system
   of record.

#### Scenario: Ingest items
- **WHEN** an `ingest` command is received with valid item IDs
- **THEN** each item is recorded in a subprocess
- **AND** the results are accumulated into `session_coverage`
- **AND** the response contains the resulting file→line→test edges
- **AND** no local index persistence is performed

#### Scenario: Ingest with recording failure
- **WHEN** an item's subprocess recording fails (timeout, infrastructure error)
- **THEN** the response includes an error entry for that item
- **AND** recording continues for the remaining items

### Requirement: [PROTO-005] static-deps handler
The system SHALL respond to the `static-deps` command by returning dependency
edges for changed files.

Behavior:
- **First invocation (no coverage recorded yet in this session):** every changed
  file → `unresolved`. This triggers testaruda's existing `TIA-SAFE-004` fallback
  (schedules a full run).
- **Subsequent invocations:** look up changed files in the `session_coverage` map
  (built by `ingest` calls — see PROTO-004) and return those edges.

The `session_coverage` map is ephemeral — it is lost when the adapter process
ends. A new adapter process starts with an empty map, so the first `static-deps`
in any new session always returns `unresolved`. This is correct behavior: the
adapter does not persist coverage data across sessions (testaruda's SQLite
store is the system of record).

#### Scenario: Static deps with no coverage
- **WHEN** `static-deps` is called before any `ingest` in this session
- **THEN** every changed file maps to `unresolved`

#### Scenario: Static deps with prior ingest
- **WHEN** `static-deps` is called after one or more `ingest` commands
- **THEN** changed files that have coverage in `session_coverage` return their
  recorded edges

### Requirement: [PROTO-006] fingerprint handler
The system SHALL respond to the `fingerprint` command by computing a SHA-256
hash of the specified file's contents. (SHA-256 is used instead of BLAKE3 to
avoid adding a non-standard-library dependency. This is a deviation from
testaruda's own BLAKE3 choice, but fingerprints are only compared within the
same adapter's scope.)

#### Scenario: File fingerprint
- **WHEN** a `fingerprint` command is received with a file path
- **THEN** the response contains the SHA-256 hash of the file contents

### Requirement: [PROTO-007] run-args handler
The system SHALL respond to the `run-args` command by emitting
`ReTestItems.runtests` invocation arguments filtered by `(test_file, item_name)`
pairs.

#### Scenario: Run args for selected items
- **WHEN** a `run-args` command is received with a set of item IDs
- **THEN** the response contains the `ReTestItems.runtests` invocation args
  that would run only those specific items
- **AND** when multiple items share the same name across different test files,
  both are included (minor over-selection, acceptable in Phase 1)