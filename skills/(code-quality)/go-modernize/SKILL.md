---
name: go-modernize
description: >
  Modernize Go code to use current language features and standard library
  additions, Go 1.21 through 1.27: generics and generic methods, log/slog,
  errors.Join, slices/maps, iterators, encoding/json/v2, stdlib uuid. Use when:
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
  version: "1.8.0"
---

# Go Modernize

Go evolves. Code written for Go 1.16 should not look the same as code targeting
Go 1.27. Modernize incrementally — update `go.mod`, then adopt new patterns.

Never adopt a feature above the `go` directive in `go.mod`. Raise the
directive deliberately, in its own commit, and only to a version the project's
CI and deployment images actually run.

Detailed reference material, loaded on demand:

- `references/generics.md` — replacing `interface{}` with type parameters,
  constraints, generic containers, when NOT to use generics.
- `references/stdlib-migrations.md` — before/after examples for slog,
  errors.Join, slices/maps helpers, range-over-int, and iterators.
- `references/go1.27.md` — generic methods, `CutLast`, URL/Values
  `Clone`, `big.Int.Divide`, stdlib `uuid`, json/v2 semantics, synctest
  and httptest additions, tooling changes.
- `references/version-bump.md` — procedure and per-release checklist
  (1.25-1.27) for what can break when the `go` directive is raised.

Read a reference file only when the summary below is not enough.

## Operating Modes

- **Inline** (default — the developer is working on something else):
  modernize only the lines you are already changing. Note other
  opportunities once, at the end, each with the gain it brings; do not
  touch unrelated files — an unrequested sweep buries the real change in
  churn. If a suggestion is declined, do not raise it again in the
  session; if the developer wants that remembered, add one line to the
  project's agent-config file (CLAUDE.md, AGENTS.md).
- **Version bump** (raising the `go` directive): a behavior change even
  with no source edits. Follow `references/version-bump.md` — prerequisites,
  then the per-release breakage checklist — before adopting any feature.
- **Sweep** (asked to modernize a package or the module): run the
  procedure below and land one commit per category — `go fix` output,
  deprecated APIs, language features, stdlib helpers, tests — each green
  on build and tests. The categories are independent; if your environment
  supports parallel sub-agents, give each one a category and work on a
  separate branch or worktree.

## Priority Order

Apply in this order when time is limited:

1. **Correctness and security** — `errors.Is`/`As` instead of `==`,
   `http.NewRequestWithContext`, `os.Root` for user-supplied paths,
   `crypto/rand` wherever randomness protects something, deprecated
   `x/crypto` packages replaced by their stdlib versions.
2. **Readability** — `any`, `min`/`max`, range over int, `slices`/`maps`,
   `cmp.Or`, `sync.OnceValue`, `wg.Go`, `errors.AsType`.
3. **Gradual** — iterators, logger migration to `slog`, `go.mod` tool
   directives, dropping dependencies the stdlib now covers.

## Modernization Procedure

1. Check the `go` directive in `go.mod` — it caps which features you can use. Raising
   it is the Version bump mode, never a side effect of a feature change.
2. Run the official modernizers first — they find and fix the mechanical
   migrations automatically:

   ```bash
   # Go 1.26+ — the modernizers now live in go fix
   go fix ./...

   # Go 1.25 and earlier, or a modernizer newer than your toolchain
   go run golang.org/x/tools/go/analysis/passes/modernize/cmd/modernize@latest -fix ./...
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
| 1.21+ | `sync.OnceValue`, `sync.OnceFunc` | Replace `sync.Once` + package var pairs |
| 1.22+ | Range over int | Replace `for i := 0; i < n; i++` |
| 1.22+ | Per-iteration loop variables | Delete `v := v` shadow copies (only once `go.mod` says 1.22+) |
| 1.22+ | `math/rand/v2` | Replace `math/rand`; drop `rand.Seed` |
| 1.22+ | `cmp.Or` | Replace "first non-zero value" if-chains |
| 1.22+ | `ServeMux` method + wildcard patterns | Replace a router dependency used only for `GET /users/{id}` |
| 1.23+ | Range over func | Replace callback-based iteration |
| 1.23+ | `unique.Make` | Replace hand-rolled string interning |
| 1.24+ | `for b.Loop()` | Replace `for range b.N` in benchmarks |
| 1.24+ | `t.Context()` | Replace `context.Background()` in tests |
| 1.24+ | `os.Root` | Replace manual path-traversal checks |
| 1.24+ | `go.mod` tool directive | Replace the `tools.go` blank-import file |
| 1.24+ | `runtime.AddCleanup` | Replace `runtime.SetFinalizer` |
| 1.24+ | `omitzero` struct tag | Replace `omitempty` where Go zero values (e.g. `time.Time{}`) must be omitted |
| 1.24+ | `strings.SplitSeq`, `strings.Lines`, `FieldsSeq` | Replace `Split` when the slice is only ranged over |
| 1.24+ | `crypto/sha3`, `crypto/hkdf`, `crypto/pbkdf2` | Replace the `golang.org/x/crypto` versions |
| 1.24+ | `crypto/rand.Text` | Replace hand-rolled random token encoders |
| 1.25+ | `testing/synctest` | Replace `time.Sleep` in concurrency tests |
| 1.25+ | `sync.WaitGroup.Go` | Replace `wg.Add(1)` + `go func(){defer wg.Done()}` |
| 1.25+ | `reflect.TypeAssert` | Replace `v.Interface().(T)` (no allocation) |
| 1.25+ | Container-aware `GOMAXPROCS` | Remove `go.uber.org/automaxprocs` |
| 1.26+ | `errors.AsType` | Replace `errors.As` with a declared target variable |
| 1.26+ | `slog.NewMultiHandler` | Replace hand-written fan-out handlers |
| 1.26+ | `new(expr)` | Replace a temp variable taken by address |
| 1.26+ | `httputil.ReverseProxy.Rewrite` | Replace the deprecated, unsafe `Director` hook |
| 1.27+ | Generic methods | Replace package-level generic helpers that belong to one type (not when an interface must expose them) |
| 1.27+ | Promoted fields as literal keys | Replace `Outer{Inner: Inner{ID: x}}` nesting |
| 1.27+ | `strings.CutLast`, `bytes.CutLast` | Replace `LastIndex` + slicing |
| 1.27+ | `url.URL.Clone`, `url.Values.Clone` | Replace hand-written deep copies |
| 1.27+ | `big.Int.Divide` | Replace `QuoRem` + sign correction |
| 1.27+ | stdlib `uuid` | Replace `google/uuid` for v4/v7 IDs |
| 1.27+ | `encoding/json/v2` | Adopt per call site — stricter semantics, see reference |
| 1.27+ | `synctest.Sleep`, `httptest.NewTestServer` | Replace `time.Sleep`+`Wait` and socket-bound test servers |
| 1.27+ | `testing/cryptotest.SetGlobalRandom` | Replace `tls.Config.Rand` in tests |

## Worked Migrations

Before/after examples for every row above live in
`references/stdlib-migrations.md` (stdlib and language features) and
`references/generics.md` (type parameters). Test-specific migrations —
`t.Context()`, `b.Loop()`, `synctest` — are owned by the go-test-quality
skill.

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
