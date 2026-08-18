---
name: go-concurrency-review
description: >
  Review and implement safe concurrency patterns in Go: goroutines,
  channels, sync primitives, context propagation, and goroutine lifecycle
  management. Use when writing concurrent code, reviewing async patterns,
  checking thread safety, debugging race conditions, or designing
  producer/consumer pipelines. Trigger examples: "check thread safety",
  "review goroutines", "race condition", "channel patterns", "sync.Mutex",
  "context cancellation", "goroutine leak".
  Not for: general style (go-coding-standards), HTTP handler patterns
  (go-api-design).
user-invocable: true
license: MIT
compatibility: Designed for Claude Code or similar AI coding agents working on Go projects. Requires the Go toolchain. Race detection requires cgo (CGO_ENABLED=1).
allowed-tools: Read Edit Write Glob Grep Bash(go:*) Bash(gofmt:*)
metadata:
  author: eduardo-sl
  version: "1.3.0"
---

# Go Concurrency Review

Concurrency in Go is powerful and deceptively easy to get wrong.
These patterns prevent goroutine leaks, data races, and deadlocks.

Detailed reference material, loaded on demand:

- `references/channels.md` — sizing, signalling, producer shutdown.
- `references/mutex-and-atomics.md` — mutex placement, lock scope, atomics,
  `sync.Once`.

Read a reference file only when the section below is not enough.

## Operating Modes

Pick the mode that matches the request before starting:

- **Implementation** — writing new concurrent code. Follow the patterns
  below as construction rules.
- **Diff review** (default) — check changed code against every section,
  paying extra attention to new `go` statements and shared state.
- **Leak/race hunt** — a symptom is already observed (growing goroutine
  count, `-race` report, deadlock). Start from "Auditing Large Codebases"
  and the Race Detection section to localize it.

## Auditing Large Codebases

For a full concurrency audit, run these independent passes rather than
one linear read:

1. **Goroutine lifecycle:** find every `go` statement
   (`grep -rn "go func\|go [a-zA-Z]" --include="*.go"`) and verify each
   has a termination path (context, closed channel, WaitGroup).
2. **Shared state:** find package-level vars and struct fields accessed
   from multiple goroutines; verify mutex/atomic protection.
3. **Channel topology:** map producers/consumers per channel; verify
   close-exactly-once and no send-on-closed paths.
4. **Context propagation:** verify blocking calls accept and respect
   `context.Context`.

If your environment supports delegating work to parallel sub-agents or
tasks, assign each pass to one; otherwise run them in order. Findings
must cite `file.go:line`. Always finish with `go test -race ./...`.

## 1. Goroutine Lifecycle Management

EVERY goroutine MUST have a clear termination path. No fire-and-forget.

### Use `errgroup` for coordinated goroutines:

```go
g, ctx := errgroup.WithContext(ctx)

g.Go(func() error {
    return fetchUsers(ctx)
})

g.Go(func() error {
    return fetchOrders(ctx)
})

if err := g.Wait(); err != nil {
    return fmt.Errorf("fetch data: %w", err)
}
```

### Long-running goroutines must respect context:

```go
func (w *Worker) Run(ctx context.Context) error {
    for {
        select {
        case <-ctx.Done():
            return ctx.Err()
        case job := <-w.jobs:
            if err := w.process(job); err != nil {
                w.logger.Error("process job", slog.Any("error", err))
            }
        }
    }
}
```

### Start goroutines in the owner, not the callee:

```go
// ✅ Good — caller controls lifecycle
go worker.Run(ctx)

// ❌ Bad — function secretly starts goroutine
func NewWorker() *Worker {
    w := &Worker{}
    go w.run() // hidden goroutine — caller has no control
    return w
}
```

## 2. Channel Patterns

- Size is one or none. Unbuffered is a synchronization point; buffer 1 is a
  handoff. Any larger buffer needs a comment justifying the number — an
  arbitrary `100` is a bug waiting for the day production is slower than
  staging.
- Signal channels carry `struct{}`, and `close(done)` broadcasts to every
  receiver at once.
- The producer owns the channel and is the only one that closes it, with
  `defer close(ch)` in the producing goroutine. Every send sits in a `select`
  against `ctx.Done()`, or a consumer that walks away leaks the producer.

Examples in `references/channels.md`.

## 3. Mutexes and Atomics

- Zero-value `sync.Mutex` and `sync.RWMutex` are ready to use. A
  `*sync.Mutex` field is always wrong.
- Declare the mutex directly above the fields it guards, with a comment
  naming the relationship. A mutex that guards "the struct" guards nothing in
  particular.
- Keep the critical section minimal — never call out to an external service,
  or take a second lock, while holding one.
- 🔴 Never copy a value containing a mutex (`c2 := *c1`): the copy carries the
  original's lock state. `go vet` catches most of these; trust it.
- Use `sync/atomic` types for counters and flags rather than a mutex around
  an `int64`.
- `sync.Once` for lazy initialization that must happen exactly once.

Examples in `references/mutex-and-atomics.md`.

## 4. Context Propagation

Context is always the first parameter, never a struct field, and every
blocking operation selects on `ctx.Done()`:

```go
// ✅ Good
select {
case result := <-ch:
    return result, nil
case <-ctx.Done():
    return nil, ctx.Err()
}

// ❌ Bad — blocks forever if the context is cancelled
result := <-ch
```

Derive a child context with its own timeout for each external call and
`defer cancel()` immediately. Full rules in the `go-context` skill.

## 5. Avoid Mutable Globals

```go
// ❌ Bad — mutable global, not safe for concurrent access
var db *sql.DB

// ✅ Good — pass as dependency
type Server struct {
    db *sql.DB
}
```

## Race Detection

ALWAYS run tests with race detector during CI:

```bash
go test -race ./...
```

This is non-negotiable. A test suite that passes without `-race` proves nothing
about concurrent correctness.

## Red Flags Checklist

- 🔴 Goroutine started without shutdown path
- 🔴 Channel never closed (potential goroutine leak)
- 🔴 Mutex copied by value
- 🔴 Context stored in struct field
- 🔴 `context.Background()` used where parent context was available
- 🔴 `select` without `ctx.Done()` case in blocking operation
- 🔴 Shared map/slice accessed without synchronization
- 🟡 Buffered channel with arbitrary large size
- 🟡 `time.Sleep` used for synchronization instead of proper signaling
- 🟡 Goroutine starting inside `init()` or constructor without lifecycle control
