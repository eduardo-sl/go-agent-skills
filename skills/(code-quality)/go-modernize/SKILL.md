---
name: go-modernize
description: >
  Modernize Go code to use current language features and standard library
  additions. Covers generics, log/slog, errors.Join, slices/maps packages,
  range-over-func, and iterators introduced in Go 1.21-1.23+. Use when:
  "modernize", "update to modern Go", "use generics", "replace interface{}",
  "upgrade Go version", "slog", "errors.Join", "range over func",
  "iterators".
  Not for: general style (go-coding-standards), error philosophy
  (go-error-handling), logging architecture (go-observability).
user-invocable: true
license: MIT
compatibility: Designed for Claude Code or similar AI coding agents working on Go projects. Requires the Go toolchain. gopls is optional, for the modernize analyzer.
allowed-tools: Read Edit Write Glob Grep Bash(go:*) Bash(gofmt:*) Bash(golangci-lint:*) Bash(gopls:*)
metadata:
  author: eduardo-sl
  version: "1.4.1"
---

# Go Modernize

Go evolves. Code written for Go 1.16 should not look the same as code targeting
Go 1.25+. Modernize incrementally — update `go.mod`, then adopt new patterns.

Never adopt a feature above the `go` directive in `go.mod`. Raise the
directive deliberately, in its own commit, and only to a version the project's
CI and deployment images actually run.

Detailed reference material, loaded on demand:

- `references/generics.md` — replacing `interface{}` with type parameters,
  constraints, generic containers, when NOT to use generics.
- `references/stdlib-migrations.md` — before/after examples for slog,
  errors.Join, slices/maps helpers, range-over-int, and iterators.

Read a reference file only when the summary below is not enough.

## Modernization Procedure

1. Check the `go` directive in `go.mod` — it caps which features you can use.
2. Run the official modernizers first — they find and fix the mechanical
   migrations automatically:

   ```bash
   # Go 1.26+ — the modernizers now live in go fix
   go fix ./...

   # Go 1.25 and earlier
   go run golang.org/x/tools/gopls/internal/analysis/modernize/cmd/modernize@latest -fix -test ./...
   ```

   Both rewrite source in place. Commit before running, and review the diff.
   If neither command is available, apply the table below manually.
3. Scan the table below for the judgment-based migrations the analyzer
   does not cover (generics, iterators, logger replacement) and apply
   them case by case.
4. Run `go build ./...` and the test suite after each group of changes.

## Feature Table by Go Version

| Go Version | Feature | Action |
|---|---|---|
| 1.13+ | `errors.Is`, `errors.As` | Replace `==` error comparisons |
| 1.13+ | `http.NewRequestWithContext` | Replace `http.NewRequest` |
| 1.16+ | `embed` | Replace `go-bindata` / `packr` |
| 1.18+ | Generics | Replace `interface{}` utility functions |
| 1.20+ | `errors.Join` | Replace manual error accumulation |
| 1.21+ | `log/slog` | Replace `log` for structured logging |
| 1.21+ | `slices`, `maps` | Replace hand-written slice/map utilities |
| 1.21+ | `min`, `max` builtins | Replace `math.Min`/`math.Max` (float64-only) |
| 1.22+ | Range over int | Replace `for i := 0; i < n; i++` |
| 1.23+ | Range over func | Replace callback-based iteration |
| 1.23+ | `unique.Make` | Replace hand-rolled string interning |
| 1.24+ | `for b.Loop()` | Replace `for range b.N` in benchmarks |
| 1.24+ | `t.Context()` | Replace `context.Background()` in tests |
| 1.24+ | `os.Root` | Replace manual path-traversal checks |
| 1.24+ | `go.mod` tool directive | Replace the `tools.go` blank-import file |
| 1.24+ | `runtime.AddCleanup` | Replace `runtime.SetFinalizer` |
| 1.25+ | `testing/synctest` | Replace `time.Sleep` in concurrency tests |
| 1.25+ | `sync.WaitGroup.Go` | Replace `wg.Add(1)` + `go func(){defer wg.Done()}` |
| 1.26+ | `errors.AsType` | Replace `errors.As` with a declared target variable |
| 1.26+ | `slog.NewMultiHandler` | Replace hand-written fan-out handlers |
| 1.26+ | `new(expr)` | Replace a temp variable taken by address |

## Key Migrations at a Glance

### Generics — type-safe utilities (Go 1.18+)

```go
// ❌ Before — loses type safety
func Contains(slice []interface{}, target interface{}) bool { /* ... */ }

// ✅ After — type-safe generic
func Contains[T comparable](slice []T, target T) bool { /* ... */ }
```

Use generics for container types (`Set[T]`, `Result[T]`) and utility
functions. Do NOT use them where a single concrete type works, or as a
substitute for interfaces in runtime polymorphism.
Details and constraint patterns: `references/generics.md`.

### Structured logging (Go 1.21+)

```go
// ❌ Before
log.Printf("processing order %s for user %s", orderID, userID)

// ✅ After
slog.Info("processing order",
    slog.String("order_id", orderID),
    slog.String("user_id", userID),
)
```

Keep zap/zerolog only if you need their performance for high-throughput
logging; for most services slog is sufficient.

### errors.Join (Go 1.20+)

```go
var errs []error
for _, item := range items {
    if err := validate(item); err != nil {
        errs = append(errs, err)
    }
}
if err := errors.Join(errs...); err != nil {
    return fmt.Errorf("validation: %w", err)
}
```

`errors.Join` preserves the chain — `errors.Is`/`errors.As` work on each
joined error. Never accumulate error strings manually.

### slices and maps helpers (Go 1.21+)

```go
found := slices.Contains(items, target)          // not a manual loop
slices.SortFunc(users, func(a, b User) int {     // not sort.Slice
    return cmp.Compare(a.Name, b.Name)
})
keys := slices.Collect(maps.Keys(m))             // not a manual key loop
clone := maps.Clone(m)                           // not a manual copy loop
```

### Range over int (Go 1.22+) and iterators (Go 1.23+)

```go
for i := range n { process(i) }                  // not for i := 0; i < n; i++

for i, v := range slices.Backward(items) {       // stdlib iterators
    fmt.Printf("%d: %v\n", i, v)
}
```

Custom `iter.Seq`/`iter.Seq2` iterators replace callback-based iteration —
full worked example in `references/stdlib-migrations.md`.

### Context-aware HTTP requests (Go 1.13+, often missed)

```go
// ❌ Before — request without context
req, err := http.NewRequest(http.MethodGet, url, nil)

// ✅ After — context propagated
req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
```

### Concurrency and tests (Go 1.24-1.25)

```go
// ❌ Before
var wg sync.WaitGroup
for _, job := range jobs {
    wg.Add(1)
    go func() {
        defer wg.Done()
        process(job)
    }()
}
wg.Wait()

// ✅ After — Go 1.25
var wg sync.WaitGroup
for _, job := range jobs {
    wg.Go(func() { process(job) })
}
wg.Wait()
```

`wg.Go` cannot be called after `wg.Wait` returns, which removes the classic
"Add after Wait" race that the `waitgroup` vet analyzer (Go 1.25+) reports.

In tests, `context.Background()` becomes `t.Context()`, `for range b.N`
becomes `for b.Loop()`, and `time.Sleep`-based concurrency tests become
`synctest.Test`. → See the go-test-quality skill.

### Error inspection (Go 1.26)

```go
// ❌ Before — needs a declared target, and the pointer indirection is easy to get wrong
var pathErr *fs.PathError
if errors.As(err, &pathErr) {
    log.Println(pathErr.Path)
}

// ✅ After — Go 1.26
if pathErr, ok := errors.AsType[*fs.PathError](err); ok {
    log.Println(pathErr.Path)
}
```

`errors.Is` is unchanged. Only the `As` form gains a generic alternative.

### Value interning and cleanup (Go 1.23-1.24)

```go
// ✅ unique.Make deduplicates repeated values; Value() returns the canonical copy
h := unique.Make(hostname)          // unique.Handle[string], comparable, cheap
store[h] = conn                     // one string kept in memory, not one per entry

// ✅ AddCleanup replaces SetFinalizer: multiple cleanups, no resurrection,
//    and it works on objects that are part of a cycle
runtime.AddCleanup(obj, func(fd int) { syscall.Close(fd) }, obj.fd)
```

Reach for `unique` only where profiling shows duplicate values dominating the
heap — a config parser reading millions of rows, not a request handler.

## Verification Checklist

1. `go.mod` version matches the features used in the codebase
2. No `interface{}` where `any` or type parameters would be clearer
3. `log/slog` used instead of `log.Printf` for structured logging
4. `errors.Join` used instead of manual error string concatenation
5. `slices.Contains`, `slices.SortFunc`, `maps.Clone` replace hand-written loops
6. Range over int (`for i := range n`) used where applicable
7. `http.NewRequestWithContext` used instead of `http.NewRequest`
8. No `sort.Slice` — use `slices.SortFunc` with `cmp.Compare`
9. Generics used for type-safe containers and utilities, not overused for trivial cases
10. Third-party dependencies evaluated against stdlib alternatives added in recent Go versions
11. `sync.WaitGroup.Go` used instead of manual `Add`/`Done` pairs (Go 1.25+)
12. Tests use `t.Context()` and `for b.Loop()` (Go 1.24+)
13. `tools.go` replaced by the `go.mod` tool directive (Go 1.24+)
