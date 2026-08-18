---
name: go-code-review
description: >
  Comprehensive code review checklist for Go projects. Evaluates code quality,
  idiomatic patterns, error handling, naming, package structure, and test coverage.
  Use when reviewing Go code, PRs, or before merging changes.
  Trigger examples: "review this code", "check this PR", "code review", "review Go file".
  Do NOT use for security-specific audits (use go-security-audit) or
  performance-specific analysis (use go-performance-review).
user-invocable: true
license: MIT
compatibility: Designed for Claude Code or similar AI coding agents working on Go projects. Requires the Go toolchain. Read-only: this skill reports findings, it does not edit code.
allowed-tools: Read Glob Grep Bash(go:*) Bash(gofmt:*) Bash(golangci-lint:*)
metadata:
  author: eduardo-sl
  version: "1.3.0"
---

# Go Code Review

Structured code review process for Go. Reviews should be constructive, specific,
and cite the relevant principle behind each finding.

## Operating Modes

Pick the mode that matches the request before starting:

- **Diff review** (default) — review only the changed lines plus enough
  surrounding context to judge them. Use for PRs and working-tree changes.
- **File/package review** — review the named files or packages in full,
  including their tests.
- **Full audit** — sweep the entire codebase. Use the strategy in
  "Auditing Large Codebases" below and aggregate everything into one report.

## Review Process

Execute these steps in order. For each finding, classify severity:
- 🔴 **BLOCKER** — Must fix before merge. Correctness, data loss, security.
- 🟡 **WARNING** — Should fix. Maintainability, idiomatic Go, clarity.
- 🟢 **SUGGESTION** — Consider improving. Style, naming, documentation.

## 0. Run the Toolchain First

Before reading code manually, let the tools catch the mechanical issues
(skip any tool that is not installed and note it in the report):

```bash
go build ./...          # it must compile
go vet ./...            # suspicious constructs
golangci-lint run       # if the repo has a config
go test -race ./...     # tests pass, no data races
```

Report tool findings alongside manual findings — a failing `go vet` is
an automatic 🔴 BLOCKER. Never report an issue a tool already proves
absent.

## 1. Correctness & Safety

### Error Handling
- Every error is checked. No blank identifier `_` discarding errors silently.
- Errors are wrapped with context: `fmt.Errorf("fetch user %d: %w", id, err)`.
- Error values compared with `errors.Is()` / `errors.As()`, never `==`.
- No `panic` outside of `init()` or truly unrecoverable situations.
- Errors handled exactly once — no log-and-return patterns.

### Nil Safety
- Pointer receivers checked before dereference when nil is a valid state.
- Map reads guarded or use comma-ok idiom.
- Channel operations consider closed/nil channels.
- Slice operations check bounds where relevant.

### Concurrency
- Shared mutable state protected by `sync.Mutex` or channels.
- No goroutine leaks — every goroutine has a clear termination path.
- Context propagation: all blocking calls accept and respect `context.Context`.
- `sync.WaitGroup` or `errgroup.Group` used for goroutine lifecycle.

## 2. API Design

- Exported functions have doc comments starting with the function name.
- Accept interfaces, return concrete types.
- Use functional options (`WithTimeout(d)`) over config structs for optional params.
- Context is always the first parameter: `func Foo(ctx context.Context, ...)`.
- Return `error` as the last return value.
- Avoid `bool` parameters — prefer named types or options.

## 3. Idiomatic Go

- Uses `:=` for local variables, `var` for zero-value intent.
- No unnecessary `else` after return/continue/break.
- Guard clauses and early returns reduce nesting.
- `defer` used for cleanup, placed right after resource acquisition.
- `range` used over manual index iteration where appropriate.
- Struct literals use field names.
- Interfaces defined at consumer, not producer.

## 4. Package Structure

- Package names are short, lowercase, singular nouns.
- No circular dependencies between packages.
- `internal/` used for non-public packages.
- `cmd/` contains main packages, one per binary.
- Clear separation of concerns — no god packages.

## 5. Testing

- Test functions follow `TestXxx` naming convention.
- Table-driven tests used for multiple input/output combinations.
- Test helpers use `t.Helper()` for clean stack traces.
- No test logic in `init()` — use `TestMain` when needed.
- Tests use `testify/assert` or `testify/require` consistently, or stdlib only.
- Edge cases covered: empty input, nil, zero values, max values.
- `t.Parallel()` used where safe.

## 6. Documentation

- All exported types, functions, and constants have doc comments.
- Doc comments start with the name of the entity.
- Package-level doc comment in `doc.go` for non-trivial packages.
- Complex algorithms or business logic have inline comments explaining *why*.

## 7. Dependencies

- `go.mod` has no replace directives in committed code (except monorepos).
- No unused dependencies.
- Dependencies are from well-maintained, reputable sources.
- Indirect dependencies are understood and acceptable.

## Auditing Large Codebases

When the scope exceeds ~20 files, do not read everything in one linear
pass. Split the audit into independent passes:

1. Enumerate packages (`go list ./...`) and group them by layer
   (handlers, services, stores, shared libraries).
2. Run one focused pass per concern from sections 1-7 (correctness,
   API design, idioms, structure, testing, docs, dependencies).
3. If your environment supports delegating work to parallel sub-agents
   or tasks, assign each pass to one — they are independent by design.
   Otherwise run them sequentially, one concern at a time.
4. Require every finding to cite `file.go:line` and severity so the
   final aggregation is mechanical: merge, deduplicate, sort by severity.

## Review Output Format

```text
## Code Review Summary

**Files reviewed:** <list>
**Overall assessment:** APPROVE | REQUEST CHANGES | COMMENT

### Findings

#### 🔴 BLOCKER: <title>
- **File:** `path/to/file.go:42`
- **Issue:** <what is wrong>
- **Why:** <which principle or guideline>
- **Fix:** <concrete suggestion>

#### 🟡 WARNING: <title>
...

#### 🟢 SUGGESTION: <title>
...

### What's Done Well
<genuine positive observations — always include at least one>
```
