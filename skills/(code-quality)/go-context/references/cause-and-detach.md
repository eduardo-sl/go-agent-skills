# Cancellation Causes, Detached Work and AfterFunc

Go 1.20-1.21 added four APIs that replace hand-rolled workarounds. The
SKILL.md section states when to use each; this file has the code.

## Record why work was cancelled (Go 1.20+)

```go
ctx, cancel := context.WithCancelCause(ctx)
defer cancel(nil)

// ... workers run with ctx; one of them hits a fatal condition:
cancel(fmt.Errorf("shard %d: checksum mismatch: %w", id, err))

// Later, where the cancellation is observed:
if errors.Is(ctx.Err(), context.Canceled) {
    logger.Warn("aborted", slog.Any("cause", context.Cause(ctx)))
}
```

`ctx.Err()` still reports `context.Canceled`, so existing checks keep
working; `context.Cause` carries the reason.

## Name a timeout (Go 1.21+)

```go
var errUpstreamSlow = errors.New("pricing service exceeded its 300ms budget")

ctx, cancel := context.WithTimeoutCause(ctx, 300*time.Millisecond, errUpstreamSlow)
defer cancel()
```

When this fires, `context.Cause(ctx)` is `errUpstreamSlow` instead of a
bare `DeadlineExceeded` that could have come from any layer.
`WithDeadlineCause` is the absolute-time twin.

## Work that must outlive the request (Go 1.21+)

```go
func (h *Handler) checkout(w http.ResponseWriter, r *http.Request) {
    // ... order placed, response about to be written ...

    // Keeps the request's values (trace ID, user) but not its cancellation.
    // Still bounded: detached work without a timeout is a leak.
    go func() {
        ctx, cancel := context.WithTimeout(context.WithoutCancel(r.Context()), 5*time.Second)
        defer cancel()
        if err := h.audit.Record(ctx, event); err != nil {
            h.logger.ErrorContext(ctx, "audit record", slog.Any("error", err))
        }
    }()
}
```

`context.Background()` here would also survive the request, but it drops
the trace ID and every other request-scoped value.

## Unblock a call that ignores context (Go 1.21+)

```go
// net.Conn.Read takes no context; a deadline in the past unblocks it.
stop := context.AfterFunc(ctx, func() {
    _ = conn.SetReadDeadline(time.Now())
})
defer stop() // deregister if Read returns first

n, err := conn.Read(buf)
```

`AfterFunc` runs its function in its own goroutine once `ctx` is done;
`stop` reports whether it prevented that. It replaces the
`go func() { <-ctx.Done(); ... }()` pattern, which leaks a goroutine
whenever the context is never cancelled.
