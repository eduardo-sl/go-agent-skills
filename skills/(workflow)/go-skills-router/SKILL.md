---
name: go-skills-router
description: >
  Index and routing table for this repository's Go skills: maps a task to
  the skill that owns it, names the secondary skills worth loading
  alongside, and draws the boundary between skills whose triggers overlap.
  Use when it is unclear which Go skill applies, when a task spans several
  concerns at once, when two skills seem to cover the same ground, or when
  the user asks what Go skills are available. Trigger examples: "which skill
  should I use", "what Go skills do you have", "is this concurrency or
  performance", "go-performance-review or go-troubleshooting".
  Not for: a task that already maps cleanly to one skill — load that skill
  directly.
user-invocable: true
license: MIT
compatibility: Designed for Claude Code or similar AI coding agents working on Go projects. Indexes the skills published in eduardo-sl/go-agent-skills; it names them, it does not require them.
allowed-tools: Read Glob Grep
metadata:
  author: eduardo-sl
  version: "1.0.1"
---

# Go Skills Router

This repository publishes 33 Go skills. Their triggers necessarily overlap —
"this is slow" could be performance, concurrency, database, or a leak. Use the
tables below to pick the owner, then load the secondary skills in the same
pass rather than discovering them one at a time.

This is an index. Every skill it names stands alone and can be read without
this one.

## Routing Table

| Task | Primary | Also load |
|---|---|---|
| Format, name, or lay out code | `go-coding-standards` | `go-documentation` |
| Review a diff or a PR | `go-code-review` | the skill owning the domain under review |
| Return, wrap, or inspect errors | `go-error-handling` | `go-defensive-coding` for nil-heavy code |
| Pass deadlines, cancel work | `go-context` | `go-concurrency-review` if goroutines are involved |
| Adopt newer Go features | `go-modernize` | `go-ci` to raise the toolchain in CI |
| Slices, maps, sets, preallocation | `go-data-structures` | `go-performance-review` |
| Write godoc, examples, deprecations | `go-documentation` | `go-coding-standards` |
| Guard against panics and silent corruption | `go-defensive-coding` | `go-error-handling` |
| Review package layout and dependency direction | `go-architecture-review` | `go-interface-design` |
| Start a new project or service | `go-project-layout` | `go-dependency-injection`, `go-ci` |
| Design an interface or a type | `go-interface-design` | `go-design-patterns` |
| Apply a known pattern | `go-design-patterns` | `go-interface-design` |
| Wire dependencies, remove globals | `go-dependency-injection` | `go-project-layout` |
| Build an HTTP API | `go-api-design` | `go-openapi`, `go-observability` |
| Work from an OpenAPI spec | `go-openapi` | `go-api-design`, `go-test-quality` |
| Build a GraphQL API | `go-graphql` | `go-database`, `go-api-design` |
| Build a gRPC service | `go-grpc` | `go-api-design`, `go-observability` |
| Build a CLI | `go-cli` | `go-project-layout`, `go-binary-size` |
| Query a database, manage transactions | `go-database` | `go-error-handling`, `go-security-audit` |
| Write goroutines, channels, sync | `go-concurrency-review` | `go-context`, `go-test-quality` |
| Audit for vulnerabilities | `go-security-audit` | `go-dependency-audit`, `go-defensive-coding` |
| Reduce allocations, optimise a hot path | `go-performance-review` | `go-data-structures` |
| Shrink a binary or image | `go-binary-size` | `go-ci` |
| Add logs, metrics, traces | `go-observability` | `go-context` |
| Debug a panic, leak, or deadlock | `go-troubleshooting` | `go-concurrency-review`, `go-performance-review` |
| Write or improve tests | `go-test-quality` | `go-test-table-driven` |
| Structure a test matrix | `go-test-table-driven` | `go-test-quality` |
| Audit go.mod, check CVEs | `go-dependency-audit` | `go-security-audit` |
| Set up CI, linting, coverage gates | `go-ci` | `go-dependency-audit` |
| Restructure existing code safely | `go-refactoring` | `go-semantic-tools`, plus the skill owning the target shape |
| Find callers, implementers, rename | `go-semantic-tools` | `go-refactoring` |
| Write a commit message | `git-commit` | — |

## Boundaries Between Overlapping Skills

Load the one that owns the **question being asked**, not the one that matches
a keyword in the code.

**"It is slow."**

- `go-performance-review` — the code allocates or copies too much. Owns
  benchmarks, pprof, and optimisation patterns.
- `go-concurrency-review` — the code contends on a lock or serialises work
  that could run in parallel.
- `go-database` — the query is the problem: missing index, N+1, pool
  exhaustion.
- `go-troubleshooting` — you do not yet know which of the three it is. Start
  here to find out, then hand off.

**"It crashed."**

- `go-troubleshooting` — a panic, deadlock, or leak already happened.
  Diagnosis, profiles, delve.
- `go-defensive-coding` — prevention. Nil traps, aliasing, overflow, the
  constructs that make the next crash impossible.
- `go-concurrency-review` — a data race or a goroutine lifecycle bug.

**"Is this secure?"**

- `go-security-audit` — external threats: injection, auth, secrets, TLS.
- `go-dependency-audit` — known CVEs in modules you import.
- `go-defensive-coding` — internal correctness bugs that are not attacks.

**"How should this be structured?"**

- `go-architecture-review` — the shape of an existing codebase.
- `go-project-layout` — the shape of a new one.
- `go-interface-design` — the shape of one type or contract.
- `go-refactoring` — the *process* of getting from the current shape to the
  target shape. Load it alongside whichever skill above owns that target.

**"How do I expose this?"**

- `go-api-design` — HTTP handlers, middleware, shutdown. Protocol-agnostic
  server concerns.
- `go-openapi` — the contract is a spec and code is generated from it.
- `go-graphql` — the client picks the shape of the response.
- `go-grpc` — protobuf contract, interceptors, streaming.

**"Tests."**

- `go-test-quality` — what to test, how to isolate it, what to mock,
  synctest, goleak, benchmarks.
- `go-test-table-driven` — the table pattern specifically: when it helps,
  how to shape the case struct, when to stop using it.

**"Style."**

- `go-coding-standards` — the rules the code should follow.
- `go-code-review` — applying rules to someone else's change, with severity.
- `go-modernize` — rules that changed because the language moved.
- `go-ci` — making a machine enforce them.

## Multi-Concern Tasks

A real task usually crosses three skills. Load them together at the start
rather than sequentially.

| Request | Load |
|---|---|
| "Build a gRPC service with tests" | `go-grpc` + `go-test-quality` + `go-error-handling` |
| "This endpoint is slow under load" | `go-troubleshooting` + `go-performance-review` + `go-database` |
| "Harden this service before launch" | `go-security-audit` + `go-dependency-audit` + `go-defensive-coding` + `go-ci` |
| "Split this monolith" | `go-architecture-review` + `go-refactoring` + `go-semantic-tools` |
| "Scaffold a new CLI" | `go-project-layout` + `go-cli` + `go-ci` + `go-binary-size` |
| "Migrate this to the current Go release" | `go-modernize` + `go-test-quality` + `go-ci` |

## Full Catalogue

| Category | Skills |
|---|---|
| Code Quality | `go-coding-standards` `go-code-review` `go-error-handling` `go-context` `go-modernize` `go-data-structures` `go-documentation` |
| Architecture | `go-architecture-review` `go-project-layout` `go-interface-design` `go-api-design` `go-openapi` `go-graphql` `go-grpc` `go-design-patterns` `go-dependency-injection` `go-cli` |
| Data | `go-database` |
| Safety & Performance | `go-concurrency-review` `go-security-audit` `go-defensive-coding` `go-performance-review` `go-observability` `go-troubleshooting` |
| Testing | `go-test-quality` `go-test-table-driven` |
| Workflow | `go-dependency-audit` `go-ci` `go-refactoring` `go-semantic-tools` `go-binary-size` `git-commit` `go-skills-router` |

## Verification Checklist

1. The primary skill matches the question being asked, not a keyword in the code
2. Secondary skills were loaded in the same pass, not discovered one at a time
3. For a diagnosis task, `go-troubleshooting` ran before an optimisation skill
4. For a restructuring task, `go-refactoring` was paired with the skill owning the target shape
5. If exactly one skill applies, it was loaded directly without routing
