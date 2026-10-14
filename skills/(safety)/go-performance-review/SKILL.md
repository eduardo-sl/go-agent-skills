---
name: go-performance-review
description: >
  Detect performance anti-patterns and apply optimization techniques in Go.
  Covers allocations, benchmarks and benchstat, pprof and traces, GC and
  GOMEMLIMIT tuning, PGO, and HTTP client reuse. Use when checking performance,
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
  version: "1.6.0"
---

# Go Performance Review

Profile first, optimize second. Never optimize without a benchmark proving the problem.

Detailed reference material, loaded on demand:

- `references/benchmarking.md` — benchmark shape, running, reading
  benchstat, comparing variants, commit format, CI regression checks.
- `references/memory-and-io.md` — allocation, hot-path and map examples,
  retention, struct layout, false sharing, HTTP clients, streaming, batching.
- `references/profiling.md` — which profile for which symptom, capture
  commands, reading pprof, compiler diagnostics, traces, flight recorder.
- `references/runtime-tuning.md` — GOGC/GOMEMLIMIT, reading `gctrace`,
  GOMAXPROCS in containers, PGO.
- `references/logging.md` — slog vs zap/zerolog decision table, slog with a
  zap backend, logging anti-patterns in hot paths.

Read a reference file only when the summary below is not enough.

## Operating Modes

- **Architecture review** (a package or service): look for structural
  costs — no connection reuse, unbounded goroutines, N+1 queries, the wrong
  data structure, per-request work that could be done once. Run separate
  passes for allocation and layout, I/O and concurrency, and algorithms and
  caching; give each to a parallel sub-agent if the environment supports it.
- **Hot-path review** (one function the caller names): read it alongside
  its profile, sequentially.
- **Optimize** (a bottleneck is known): follow the cycle below, one change
  at a time.

## The Optimization Cycle

1. **Name the metric and the target** — p99 latency, throughput,
   `allocs/op`, RSS. Without a target, optimization never ends.
2. **Rule out external time first.** Goroutines parked in
   `net.(*conn).Read` or `database/sql`, or a trace dominated by one
   upstream span, mean the fix is elsewhere (go-database, go-observability).
3. **Benchmark the isolated path** and save the baseline:
   `go test -run '^$' -bench Name -benchmem -count=10 | tee old.txt`.
4. **Profile to find the cause** — see Profiling below.
5. **Change one thing**, with a comment saying why it is faster.
6. **Re-measure on the same machine and toolchain**; keep the change only
   if `benchstat old.txt new.txt` shows a significant difference.
7. **Put the benchstat table in the commit body** (`perf(scope): ...`).

## 1. Allocation Reduction

- `strconv` instead of `fmt.Sprintf` for single values.
- `strings.Builder` (with `Grow` when the size is known) instead of `+=`
  in loops.
- Preallocate slices and maps when the size is known or bounded:
  `make([]T, 0, n)`, `make(map[K]V, n)`.
- Reuse buffers on a proven hot path with `sync.Pool` — reset on get,
  size-cap on put (the concurrency skill has the pattern).
- Watch for hidden allocations: values stored in interfaces, closures
  capturing variables, `[]byte(s)`/`string(b)` conversions, and anything
  `go build -gcflags=-m` reports as `escapes to heap`.

## 2. Hot Path Optimizations

- Concrete types in tight loops — interface method calls block inlining
  and boxing allocates.
- No `reflect` on hot paths; generate code instead (`stringer`, protobuf).
- Contiguous data beats pointer chasing: `[]Point` over `[]*Point`, and a
  struct of slices when a loop touches one field of many records.

## 3. Map Performance

- Capacity hints when the size is known.
- `sync.Map` only for its two documented workloads; otherwise a map
  guarded by a mutex.
- A small fixed key set (enum-indexed) is faster as an array or slice.

Examples for sections 1-3: `references/memory-and-io.md`.

## 4. Benchmarking

```go
func BenchmarkParse(b *testing.B) {
    input := makeInput(4 << 10) // setup runs once, outside the timed loop
    b.ReportAllocs()
    for b.Loop() {              // Go 1.24+: no ResetTimer, no sink variable
        Parse(input)
    }
}
```

- `-count=10` and `benchstat`, never a single run. `~` in its output means
  "no change", whatever the percentage says.
- Sub-benchmarks per input size; inputs sized like production.
- Below Go 1.24, use `for range b.N` with `b.ResetTimer()` after setup and
  a package-level sink.
- Competing variants are built in parallel but benchmarked one at a time —
  concurrent runs contaminate each other.

Commands, reading guide and CI regression checks: `references/benchmarking.md`.

## 5. Profiling

| Symptom | First profile |
|---|---|
| High CPU | CPU profile — high `flat` functions |
| GC busy, high allocation rate | heap with `-sample_index=alloc_objects` |
| Memory grows over time | two heap snapshots, `go tool pprof -base` |
| Latency high, CPU idle | goroutine dump, block/mutex profiles, a trace |
| Lock contention | mutex profile (`runtime.SetMutexProfileFraction`) |
| Scheduling delays, GC pauses | execution trace; flight recorder (Go 1.25+) in production |

```bash
go test -run '^$' -bench Name -cpuprofile cpu.out -memprofile mem.out ./pkg
go tool pprof -http=:0 cpu.out                     # flame graph
go build -gcflags='-m' ./pkg 2>&1 | grep 'escapes'  # what moves to the heap
```

The CPU profile only sees running goroutines: when latency is high and CPU
is low, the time is waiting, and only the goroutine, block and trace views
show it. Commands, reading guide, escape analysis and the flight recorder:
`references/profiling.md`.

Importing `net/http/pprof` registers its handlers on `http.DefaultServeMux`.
If the service also serves public traffic from `DefaultServeMux`, profiles,
command line and goroutine stacks become world-readable. Always give pprof
its own loopback or internal-network listener.

## 6. Runtime Tuning

- In containers, set `GOMEMLIMIT` to ~80-90% of the memory limit and keep
  `GOGC`; the GC then works harder near the ceiling instead of the process
  being OOM-killed. Never `GOGC=off` with only a limit.
- Go 1.25+ derives `GOMAXPROCS` from the cgroup CPU limit — remove
  `automaxprocs` and don't set it by hand without a measurement.
- Commit a production CPU profile as `default.pgo` for PGO (Go 1.21+).
- After a toolchain upgrade (Green Tea GC in 1.26, the 1.27 allocator),
  re-measure before keeping old tuning.

Detail, `gctrace` reading and `runtime/metrics`: `references/runtime-tuning.md`.

## 7. I/O and HTTP Clients

- One `http.Client` per process, with a `Timeout` and a transport cloned
  from `http.DefaultTransport` with `MaxIdleConnsPerHost` raised — the
  default of 2 churns connections under concurrency.
- Close every response body and read it to EOF so the connection returns
  to the pool.
- Stream: decode from `r.Body` with a size cap instead of `io.ReadAll`;
  `io.Copy` for proxying; `bufio` for many small writes.
- Batch round trips — rows, API calls, channel items.
- Subslices and substrings of large buffers keep the whole buffer alive;
  `slices.Clone`/`strings.Clone` what you keep.

Examples, struct layout and false sharing: `references/memory-and-io.md`.

## 8. High-Throughput Logging

`log/slog` is the default. Switch only when a benchmark shows logging in
the profile, and then keep the slog API with a faster backend (zap's
`zapslog` handler) so callers never change. In hot loops, log progress
every N items or a summary after the loop — never once per item.
Decision table and examples: `references/logging.md`.

## 9. Common Anti-Patterns

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
| `http.Get` / default client in production | Shared client with `Timeout` and tuned transport |
| `io.ReadAll` on request or response bodies | Stream with a decoder and a size cap |
| `reflect.DeepEqual` outside tests | `slices.Equal`, `maps.Equal`, `bytes.Equal` |
| `panic`/`recover` as control flow | Return errors — a panic captures a stack trace |

## Important Caveat

Most Go code is not performance-critical. Readability and correctness ALWAYS
take priority over micro-optimizations. Only apply these patterns when:

1. A benchmark proves this code path is a bottleneck
2. The optimization is significant (>10% improvement)
3. The resulting code remains readable and maintainable

Premature optimization is still the root of all evil, even in Go.
