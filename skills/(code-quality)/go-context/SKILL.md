---
name: go-context
description: >
  Correct usage of context.Context in Go: propagation, cancellation,
  timeouts, deadlines, values, and common anti-patterns. Use when: "context
  usage", "context.Context", "context cancellation", "timeout",
  "context.WithTimeout", "context.WithCancel", "context values", "context
  propagation".
  Not for: concurrency beyond context (go-concurrency-review), HTTP
  middleware (go-api-design), error handling (go-error-handling).
user-invocable: true
license: MIT
compatibility: Designed for Claude Code or similar AI coding agents working on Go projects. Requires the Go toolchain.
allowed-tools: Read Edit Write Glob Grep Bash(go:*) Bash(gofmt:*)
metadata:
  author: eduardo-sl
  version: "1.2.0"
---

# Go Context

`context.Context` controls cancellation, deadlines, and request-scoped values
across API boundaries. Misusing it causes goroutine leaks, orphaned work,
and subtle production bugs.

Detailed reference material, loaded on demand:

- `references/timeout-budgets.md` — dividing a parent's remaining budget,
  reading `ctx.Deadline()`.
- `references/values.md` — context key types, accessors, collision traps.
- `references/http-and-testing.md` — request context in handlers and
  middleware, and cancellation tests.

Read a reference file only when the section below is not enough.

## 1. Core Rules

### Context is always the first parameter:

```go
// ✅ Good — context is first
func GetUser(ctx context.Context, id string) (*User, error)
func (s *Service) Process(ctx context.Context, req Request) error

// ❌ Bad — context buried in the middle or end
func GetUser(id string, ctx context.Context) (*User, error)
func Process(req Request, ctx context.Context) error
```

### NEVER store context in a struct:

```go
// ❌ Bad — context stored in struct
type Server struct {
    ctx    context.Context // NEVER do this
    cancel context.CancelFunc
}

// ✅ Good — pass context through method parameters
func (s *Server) Shutdown(ctx context.Context) error {
    return s.httpServer.Shutdown(ctx)
}
```

Context represents the lifetime of a single operation, not the lifetime of an object.

### NEVER pass nil context:

```go
// ❌ Bad
doSomething(nil, data)

// ✅ Good — use context.TODO() if unsure which context to use
doSomething(context.TODO(), data)

// ✅ Good — use context.Background() for top-level/main
doSomething(context.Background(), data)
```

## 2. Cancellation

### Always defer cancel:

```go
// ✅ Good — cancel called even if operation succeeds
ctx, cancel := context.WithCancel(parentCtx)
defer cancel()

result, err := longOperation(ctx)
```

Failing to call cancel leaks resources (timers, goroutines) until the parent
context is cancelled.

### Use WithCancel for manual cancellation:

```go
func (s *Supervisor) Run(ctx context.Context) error {
    ctx, cancel := context.WithCancel(ctx)
    defer cancel()

    g, ctx := errgroup.WithContext(ctx)

    g.Go(func() error { return s.runWorkerA(ctx) })
    g.Go(func() error { return s.runWorkerB(ctx) })

    // If any worker returns an error, errgroup cancels ctx,
    // which signals all other workers to stop.
    return g.Wait()
}
```

### Check context cancellation in loops:

```go
// ✅ Good — respects cancellation
func processItems(ctx context.Context, items []Item) error {
    for _, item := range items {
        if err := ctx.Err(); err != nil {
            return fmt.Errorf("processing cancelled: %w", err)
        }
        if err := process(ctx, item); err != nil {
            return fmt.Errorf("process item %s: %w", item.ID, err)
        }
    }
    return nil
}

// ❌ Bad — runs to completion even if cancelled
func processItems(ctx context.Context, items []Item) error {
    for _, item := range items {
        process(ctx, item) // ignores ctx cancellation between items
    }
    return nil
}
```

## 3. Timeouts and Deadlines

### WithTimeout for duration-based limits:

```go
func (c *Client) FetchUser(ctx context.Context, id string) (*User, error) {
    ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
    defer cancel()

    req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.url+"/users/"+id, nil)
    if err != nil {
        return nil, fmt.Errorf("create request: %w", err)
    }

    resp, err := c.httpClient.Do(req)
    if err != nil {
        return nil, fmt.Errorf("fetch user %s: %w", id, err)
    }
    defer resp.Body.Close()

    // ...
}
```

### WithDeadline for absolute time limits:

```go
// Use when coordinating with external deadlines (SLAs, cron windows)
deadline := time.Date(2024, 1, 1, 0, 0, 0, 0, time.UTC)
ctx, cancel := context.WithDeadline(ctx, deadline)
defer cancel()
```

### Timeout budgets

A child timeout spends part of the parent's budget; it never extends it. A
5s DB call and a 10s API call inside a 30s request handler are a budget. A
60s child under a parent with 5s left silently fires at the parent's
deadline, which reads as a bug at 3am.

Before starting work that cannot be interrupted, read the remaining budget
with `ctx.Deadline()` and fail fast when it is too short.

Examples in `references/timeout-budgets.md`.

## 4. Context Values

Store only request-scoped metadata: request ID, trace or span ID, the
authenticated user, a request-scoped logger. Never a database connection,
configuration, or anything the function could take as an explicit parameter.

Keys must be an unexported type, never a string — a string key can be
overwritten by any other package in the process. Export accessor functions
so callers never type-assert on `ctx.Value` themselves.

Examples in `references/values.md`.

## 5. Context in HTTP Handlers and Tests

Handlers take `r.Context()` and pass it downstream. A cancelled request means
the client disconnected: return without writing a response. Middleware
attaches values with `r.WithContext(ctx)`.

Tests wrap the call under test in `context.WithTimeout` so a hang fails the
test instead of blocking the suite, and assert `errors.Is(err,
context.Canceled)` to prove cancellation is honoured.

Examples in `references/http-and-testing.md`.

## 6. context.Background() vs context.TODO()

| Function | When to use |
|---|---|
| `context.Background()` | Top-level: `main()`, `init()`, test setup. Intentional root context. |
| `context.TODO()` | Placeholder when you don't know which context to use yet. Signals "this needs to be fixed". |

`context.TODO()` is a code smell in production code — replace it before shipping.

## Verification Checklist

1. `context.Context` is the first parameter in all functions that accept it
2. No context stored in struct fields
3. `defer cancel()` called immediately after `WithCancel`, `WithTimeout`, `WithDeadline`
4. Long loops check `ctx.Err()` between iterations
5. Child timeouts don't exceed parent timeout budget
6. Context values use unexported key types with accessor functions
7. Only request-scoped metadata stored in context values (not configs, connections)
8. HTTP handlers use `r.Context()` and pass it downstream
9. No `nil` context passed — use `context.TODO()` or `context.Background()`
10. Tests use `context.WithTimeout` to prevent hanging
