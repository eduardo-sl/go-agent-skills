# Goroutine Patterns

Recovery boundaries, pipelines, bounded fan-out and timers. The SKILL.md
sections state the rules; this file has the code.

## Contents

- Recover at the goroutine boundary
- Pipelines
- Bounded fan-out
- Timers

## Recover at the goroutine boundary

A `recover` only catches panics in its own goroutine. HTTP middleware that
recovers does nothing for a goroutine the handler starts.

```go
// Run starts fn in its own goroutine and turns a panic into an error,
// so one bad input cannot crash every request the process is serving.
func Run(ctx context.Context, logger *slog.Logger, fn func(context.Context) error) <-chan error {
    errc := make(chan error, 1)
    go func() {
        defer func() {
            if r := recover(); r != nil {
                logger.ErrorContext(ctx, "goroutine panicked",
                    slog.Any("panic", r),
                    slog.String("stack", string(debug.Stack())))
                errc <- fmt.Errorf("panic: %v", r)
            }
        }()
        errc <- fn(ctx)
    }()
    return errc
}
```

The buffer of 1 lets the goroutine exit even if nobody reads the result.

## Pipelines

Each stage owns its output channel, closes it when done, and selects on
`ctx.Done()` around every send, so cancelling the context drains the whole
chain instead of leaking blocked senders.

```go
func square(ctx context.Context, in <-chan int) <-chan int {
    out := make(chan int)
    go func() {
        defer close(out)
        for n := range in {
            select {
            case out <- n * n:
            case <-ctx.Done():
                return
            }
        }
    }()
    return out
}

// merge fans several channels into one; out closes after every input does.
func merge(ctx context.Context, ins ...<-chan int) <-chan int {
    out := make(chan int)
    var wg sync.WaitGroup
    for _, in := range ins {
        wg.Go(func() { // Go 1.25+
            for v := range in {
                select {
                case out <- v:
                case <-ctx.Done():
                    return
                }
            }
        })
    }
    go func() { wg.Wait(); close(out) }()
    return out
}
```

If the stages do not actually run concurrently, use an `iter.Seq` chain
instead: no goroutines, nothing to leak, and the same composition.

## Bounded fan-out

```go
g, ctx := errgroup.WithContext(ctx)
g.SetLimit(runtime.GOMAXPROCS(0)) // CPU-bound; use the backend's capacity for I/O
for _, f := range files {
    g.Go(func() error { return process(ctx, f) })
}
return g.Wait() // first error cancels ctx for the rest
```

One goroutine per input with no limit is a self-inflicted denial of
service against whatever the goroutines call.

## Timers

- `time.After` in a loop allocates a timer every iteration. Since Go 1.23
  an unreferenced timer is collected, so this is churn rather than a leak;
  in a hot loop, reuse one `time.NewTimer` and call `Reset`.
- With `go 1.23` or later in `go.mod` (and always from Go 1.27), `Stop`
  and `Reset` guarantee no stale value is received afterwards. The old
  `if !t.Stop() { <-t.C }` drain is unnecessary.
- `time.Tick` is fine for a ticker that lives as long as the program; any
  ticker with a shorter life is a `time.NewTicker` with `defer t.Stop()`.
