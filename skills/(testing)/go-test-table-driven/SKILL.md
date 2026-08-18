---
name: go-test-table-driven
description: >
  Deep dive on table-driven tests in Go: when to use them, when to avoid them,
  struct design, subtest naming, advanced patterns like test matrices and
  shared setup, and refactoring bloated tables into clean ones.
  Use when writing table-driven tests, refactoring test tables, reviewing
  table test structure, or deciding whether table-driven is the right approach.
  Trigger examples: "table-driven test", "table test", "test cases struct",
  "test matrix", "parametrize tests", "data-driven test", "refactor test table".
  Do NOT use for general test strategy, mocking, golden files, or fuzz testing
  (use go-test-quality). Do NOT use for benchmarks (use go-performance-review).
user-invocable: true
license: MIT
compatibility: Designed for Claude Code or similar AI coding agents working on Go projects. Requires the Go toolchain.
allowed-tools: Read Edit Write Glob Grep Bash(go:*) Bash(gofmt:*)
metadata:
  author: eduardo-sl
  version: "1.2.0"
---

# Go Table-Driven Tests

Table-driven tests are a powerful Go idiom — when used correctly. Most
codebases either underuse them (10 copy-paste tests) or overuse them
(complex branching logic in a 200-line struct). This skill covers the
sweet spot.

Detailed reference material, loaded on demand:

- `references/patterns.md` — full worked examples: canonical tables,
  `wantErr`/`wantErrIs`, parallel tables, map-based tables, error-only
  tables, struct alignment for readability.
- `references/refactoring.md` — recognizing bloated tables and rewriting
  them as explicit subtests, with before/after examples.

Read a reference file only when the summary below is not enough for the
task at hand.

## 1. When Table-Driven Tests Shine

Use a table only when ALL of these are true:

- **Same function** under test across all cases
- **Same assertion pattern** — input in, output out, compare
- **Cases differ only in data**, not in setup or verification logic
- **3+ cases** — fewer than 3, explicit tests are clearer

Canonical use case: pure functions, parsers, validators, formatters.

```go
func TestParseSize(t *testing.T) {
    tests := []struct {
        name    string
        input   string
        want    int64
        wantErr bool
    }{
        {name: "plain bytes", input: "1024", want: 1024},
        {name: "kilobytes suffix", input: "4KB", want: 4096},
        {name: "empty string", input: "", wantErr: true},
        {name: "negative size", input: "-1", wantErr: true},
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            got, err := ParseSize(tt.input)
            if tt.wantErr {
                require.Error(t, err)
                return
            }
            require.NoError(t, err)
            assert.Equal(t, tt.want, got)
        })
    }
}
```

Every case has the same shape, the loop body is a few lines, and adding
a case is one struct literal. No branching, no conditionals.

## 2. When NOT to Use Table-Driven Tests

- **Complex per-case setup** — `setupMock`/`setupFunc` function fields in
  the struct mean the table is hiding complexity. Write explicit subtests.
- **Fewer than 3 cases** — the struct definition is more code than two
  plain test functions.
- **Multiple branching paths** — `if tt.shouldError` / `if tt.wantRedirect`
  in the loop body means each branch is a different test pretending to
  share a structure. Split it.

See `references/refactoring.md` for before/after rewrites of each smell.

## 3. Struct Design Rules

1. **Every field must vary between at least 2 cases.** A field with the
   same value everywhere is setup — move it outside the table.
2. **Name the `name` field as a short sentence** describing the scenario:
   `"returns error for negative amount"`, not `"case1"` or `"success"`.
3. **`wantErr bool` for "should it error?"** — check it first and `return`
   early in the loop body.
4. **`wantErrIs error` with a sentinel** when the caller must detect a
   specific error; assert with `require.ErrorIs`.
5. **≤5 fields.** More means the scenario is too complex for a table —
   split into separate test functions.

Full field-pattern examples are in `references/patterns.md`.

## 4. The Loop Body Must Be Trivial

The point of a table test is identical execution logic for every case.
Keep the loop body under ~10 lines: call, error check, comparison.
If it accumulates conditionals or per-case setup, the table has outgrown
its usefulness — refactor into explicit subtests.

## 5. Parallel Table Tests

```go
for _, tt := range tests {
    t.Run(tt.name, func(t *testing.T) {
        t.Parallel()
        got := Transform(tt.input)
        assert.Equal(t, tt.want, got)
    })
}
```

- Go 1.22+ scopes the loop variable per iteration — `tt := tt` capture is
  unnecessary. For Go <1.22 the capture is still required.
- Only use `t.Parallel()` when the function under test has no side
  effects and no shared mutable state.

## 6. Refactoring Bloated Tables

| Symptom | Fix |
|---|---|
| Struct has 8+ fields | Split into multiple test functions by scenario |
| `setupFunc` field in struct | Extract to separate subtests with explicit setup |
| `if tt.shouldX` in loop body | Each branch is a different test — split it |
| Same 3 fields identical in every case | Move to shared setup outside the table |
| Adding a case requires understanding all others | Table has grown beyond its useful life |

## Decision Flowchart

1. **Is the function pure (input → output, no side effects)?**
   Yes → table test is probably ideal. Go to 2.
   No → consider explicit subtests first.

2. **Do all cases share the exact same assertion pattern?**
   Yes → table test. Go to 3.
   No → explicit subtests.

3. **Can each case be expressed in ≤5 struct fields?**
   Yes → table test.
   No → split by scenario into separate test functions.

4. **Is the loop body ≤10 lines?**
   Yes → you're golden.
   No → the table is hiding complexity. Refactor.

## Verification Checklist

1. Table struct has only fields that vary between cases
2. Every case has a descriptive `name` field
3. Loop body is ≤10 lines with no branching
4. No `setupFunc` or `mockFunc` fields in the struct
5. `wantErr` is a simple bool or sentinel, not a string match
6. Cases cover: happy path, error path, edge cases (empty, nil, zero, max)
7. `t.Run` wraps each case for named subtests
8. `t.Parallel()` used only when function is side-effect-free
