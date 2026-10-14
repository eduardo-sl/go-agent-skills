# Copies and Resource Lifecycle

Worked examples for SKILL.md sections 4, 6 and 7.

## Preventing accidental copies

A struct containing a `sync.Mutex`, `sync.WaitGroup`, or `atomic.Int64` must
never be copied — the copy gets its own independent lock, and both halves
believe they are synchronised.

```go
// ❌ Bad — the receiver is a copy, so the mutex protects nothing
func (c Counter) Value() int { ... }

// ❌ Bad — passing by value copies the mutex
func report(c Counter) { ... }
```

`go vet`'s `copylocks` analyzer catches these. For types that must not be
copied but hold no lock, embed a `noCopy` marker so `vet` catches them too:

```go
type noCopy struct{}

func (*noCopy) Lock()   {}
func (*noCopy) Unlock() {}

type Tracker struct {
    noCopy noCopy
    // ...
}
```

## Resource lifecycle

`defer` runs at **function** return, not at the end of the block.

```go
// ❌ Bad — all files stay open until the loop finishes
for _, name := range names {
    f, err := os.Open(name)
    if err != nil {
        return err
    }
    defer f.Close()
    process(f)
}

// ✅ Good — a function scope per iteration
for _, name := range names {
    if err := func() error {
        f, err := os.Open(name)
        if err != nil {
            return err
        }
        defer f.Close()
        return process(f)
    }(); err != nil {
        return err
    }
}
```

The same rule applies to `resp.Body.Close`, `rows.Close`, `mu.Unlock`, and
`tx.Rollback` inside loops or long-lived functions.

Check the error from a deferred `Close` on anything you wrote to — a failed
flush on close is a silent data loss otherwise:

```go
defer func() {
    if cerr := f.Close(); cerr != nil && err == nil {
        err = fmt.Errorf("close %s: %w", name, cerr)
    }
}()
```

## Usable zero value

Design types so the zero value works, then no constructor can be forgotten.

```go
// ✅ Usable zero value — sync.Mutex and the nil map read are both fine
type Counter struct {
    mu sync.Mutex
    n  map[string]int
}

func (c *Counter) Inc(k string) {
    c.mu.Lock()
    defer c.mu.Unlock()
    if c.n == nil { // lazily initialise on first write
        c.n = make(map[string]int)
    }
    c.n[k]++
}
```
