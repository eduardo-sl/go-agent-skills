---
name: go-modernize
description: >
  Modernize Go code to use current language features and standard library additions.
  Covers generics, log/slog, errors.Join, slices/maps packages, range-over-func,
  and iterators introduced in Go 1.21-1.23+.
  Use when: "modernize", "update to modern Go", "use generics", "replace interface{}",
  "upgrade Go version", "slog", "errors.Join", "range over func", "iterators".
  Do NOT use for: general code style (use go-coding-standards),
  error handling philosophy (use go-error-handling), or
  logging architecture (use go-observability).
license: MIT
metadata:
  version: "1.2.0"
---

# Go Modernize

Go evolves. Code written for Go 1.16 should not look the same as code targeting
Go 1.22+. Modernize incrementally — update `go.mod`, then adopt new patterns.

Detailed reference material, loaded on demand:

- `references/generics.md` — replacing `interface{}` with type parameters,
  constraints, generic containers, when NOT to use generics.
- `references/stdlib-migrations.md` — before/after examples for slog,
  errors.Join, slices/maps helpers, range-over-int, and iterators.

Read a reference file only when the summary below is not enough.

## Modernization Procedure

1. Check the `go` directive in `go.mod` — it caps which features you can use.
2. Run the official modernize analyzer first — it finds and fixes the
   mechanical migrations automatically:

   ```bash
   go run golang.org/x/tools/gopls/internal/analysis/modernize/cmd/modernize@latest -fix -test ./...
   ```

   If the command is unavailable in your environment, apply the table
   below manually instead.
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
