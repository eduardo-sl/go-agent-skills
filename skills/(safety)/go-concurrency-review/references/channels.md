# Channel Patterns

Sizing, signalling and shutdown for channels. The SKILL.md section states the
rules; this file has the code.

## Channel size is one or none:

```go
// Unbuffered — synchronization point
ch := make(chan Result)

// Buffered with size 1 — single-item handoff
ch := make(chan Result, 1)

// Larger buffers need explicit justification with documented reasoning
ch := make(chan Result, 100) // requires comment explaining why
```

## Signal channels use empty struct:

```go
done := make(chan struct{})
close(done) // broadcast signal to all receivers
```

## Producer/consumer with clean shutdown:

```go
func produce(ctx context.Context) <-chan Item {
    ch := make(chan Item)
    go func() {
        defer close(ch)
        for {
            item, err := fetchNext(ctx)
            if err != nil {
                return
            }
            select {
            case ch <- item:
            case <-ctx.Done():
                return
            }
        }
    }()
    return ch
}
```
