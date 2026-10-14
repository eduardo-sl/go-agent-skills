---
name: go-performance-review
description: >
  Detect performance anti-patterns and apply optimization techniques in Go.
  Covers allocations, string handling, slice/map preallocation, sync.Pool,
  benchmarking, and profiling with pprof. Use when checking performance,
  finding slow code, reducing allocations, profiling, or reviewing hot
  paths. Trigger examples: "check performance", "find slow code", "reduce
  allocations", "benchmark this", "profile", "optimize Go code".
  Not for: concurrency correctness (go-concurrency-review), general style
  (go-coding-standards).
user-invocable: true
license: MIT
compatibility: Designed for Claude Code or similar AI coding agents working on Go projects. Requires the Go toolchain. benchstat is optional, for comparing benchmark runs.
allowed-tools: Read Edit Write Glob Grep Bash(go:*) Bash(gofmt:*) Bash(benchstat:*)
metadata:
  author: eduardo-sl
  version: "1.2.3"
---

# Go Performance Review

Profile first, optimize second. Never optimize without a benchmark proving the problem.

Detailed reference material, loaded on demand:

- `references/logging.md` — slog vs zap/zerolog decision table, slog with a
  zap backend, logging anti-patterns in hot paths.

Read a reference file only when the summary below is not enough.

## 1. Allocation Reduction

### Prefer `strconv` over `fmt` for primitive conversions:

```go
// ✅ Good — zero allocations for simple conversions
s := strconv.Itoa(42)
s := strconv.FormatFloat(3.14, 'f', 2, 64)

// ❌ Bad — fmt.Sprintf allocates
s := fmt.Sprintf("%d", 42)
```

### Avoid unnecessary string-to-byte conversions:

```go
// ✅ Good — use strings.Builder for concatenation
var b strings.Builder
for _, s := range parts {
    b.WriteString(s)
}
result := b.String()

// ❌ Bad — repeated concatenation allocates on every +
result := ""
for _, s := range parts {
    result += s
}
```

### Preallocate slices and maps when size is known:

```go
// ✅ Good — single allocation
users := make([]User, 0, len(ids))
for _, id := range ids {
    users = append(users, getUser(id))
}

// ✅ Good — map with capacity hint
lookup := make(map[string]User, len(users))

// ❌ Bad — repeated growing
var users []User // starts at 0, grows via doubling
```

### Use `sync.Pool` for frequently allocated, short-lived objects:

```go
var bufPool = sync.Pool{
    New: func() any {
        return new(bytes.Buffer)
    },
}

func process(data []byte) string {
    buf := bufPool.Get().(*bytes.Buffer)
    defer func() {
        buf.Reset()
        bufPool.Put(buf)
    }()

    buf.Write(data)
    return buf.String()
}
```

## 2. Hot Path Optimizations

### Avoid interface conversions in tight loops:

```go
// ✅ Good — concrete type in loop
func sum(vals []int64) int64 {
    var total int64
    for _, v := range vals {
        total += v
    }
    return total
}

// ❌ Bad — interface{} causes boxing/unboxing
func sum(vals []interface{}) int64 { ... }
```

### Avoid `reflect` in performance-critical paths:

If you need reflection-like behavior at scale, use code generation
(`go generate`, `stringer`, protocol buffers).

### Reduce pointer chasing:

```go
// ✅ Good — contiguous memory, cache-friendly
type Points struct {
    X []float64
    Y []float64
}

// ❌ Slower — pointer chasing per element
type Points []*Point
```

## 3. Map Performance

```go
// ✅ Use capacity hints
m := make(map[string]int, expectedSize)

// ✅ For read-heavy concurrent access, use sync.Map
// But ONLY when keys are stable — sync.Map has higher overhead
// for writes than a mutex-protected map.

// ✅ For fixed key sets, consider using a slice with index mapping
// instead of a map.
```

## 4. Benchmarking

ALWAYS write benchmarks before and after optimization:

```go
func BenchmarkFoo(b *testing.B) {
    input := generateInput() // setup runs once, outside the timed loop
    b.ReportAllocs()
    for b.Loop() {           // Go 1.24+: no ResetTimer, no sink variable
        Foo(input)
    }
}
```

`b.Loop()` times only the loop body and keeps arguments and results alive,
so the compiler cannot eliminate the call. Below Go 1.24, use
`for range b.N` with `b.ResetTimer()` after setup and assign results to a
package-level sink.

Run benchmarks with memory profiling:

```bash
go test -bench=BenchmarkFoo -benchmem -count=10 ./...
```

Compare before/after with `benchstat`:

```bash
go test -bench=. -count=10 > old.txt
# make changes
go test -bench=. -count=10 > new.txt
benchstat old.txt new.txt
```

## 5. Profiling

### CPU profiling:

```bash
go test -cpuprofile=cpu.prof -bench=BenchmarkFoo .
go tool pprof cpu.prof
```

### Memory profiling:

```bash
go test -memprofile=mem.prof -bench=BenchmarkFoo .
go tool pprof -alloc_space mem.prof
```

### HTTP server profiling (import net/http/pprof):

```go
import _ "net/http/pprof"

// Access at http://localhost:6060/debug/pprof/
go func() {
    // Bind to loopback only — never the public listener.
    log.Println(http.ListenAndServe("localhost:6060", nil))
}()
```

Importing `net/http/pprof` registers its handlers on `http.DefaultServeMux`.
If the service also serves public traffic from `DefaultServeMux`, profiles,
command line and goroutine stacks become world-readable. Always give pprof
its own loopback or internal-network listener.

## 6. High-Throughput Logging

`log/slog` is the default. Switch only when a benchmark shows logging in
the profile, and then keep the slog API with a faster backend (zap's
`zapslog` handler) so callers never change. In hot loops, log progress
every N items or a summary after the loop — never once per item.
Decision table and examples: `references/logging.md`.

## 7. Common Anti-Patterns

| Anti-Pattern | Fix |
|---|---|
| `fmt.Sprintf` for simple int→string | `strconv.Itoa` |
| String concatenation in loop | `strings.Builder` |
| Slice without preallocation | `make([]T, 0, n)` |
| Map without capacity hint | `make(map[K]V, n)` |
| `regexp.Compile` inside function | Compile once at package level |
| `json.Marshal` in hot path | Profile first: since Go 1.27 `encoding/json` runs on the faster v2 engine; code-gen (`easyjson`) only if JSON still dominates |
| Logging in tight loop | Batch or sample |
| `defer` in very tight inner loop | Manual cleanup (rare, benchmark first) |

## Important Caveat

Most Go code is not performance-critical. Readability and correctness ALWAYS
take priority over micro-optimizations. Only apply these patterns when:

1. A benchmark proves this code path is a bottleneck
2. The optimization is significant (>10% improvement)
3. The resulting code remains readable and maintainable

Premature optimization is still the root of all evil, even in Go.
