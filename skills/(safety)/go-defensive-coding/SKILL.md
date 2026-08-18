---
name: go-defensive-coding
description: >
  Prevent panics, silent corruption, and subtle runtime bugs in Go:
  typed-nil interfaces, slice aliasing, integer overflow on conversion,
  float comparison, defer in loops, defensive copying at API boundaries, and
  zero-value design. Use when hardening code against crashes, reviewing for
  nil-safety, converting between numeric types, or deciding what to copy at
  a package boundary. Trigger examples: "nil pointer panic", "why is my
  error not nil", "slice aliasing", "integer overflow", "compare floats",
  "defer in a loop", "defensive copy", "make this crash-proof".
  Not for: data races and goroutine lifecycle (go-concurrency-review),
  injection and auth (go-security-audit), a panic that already happened
  (go-troubleshooting).
user-invocable: true
license: MIT
compatibility: Designed for Claude Code or similar AI coding agents working on Go projects. Requires the Go toolchain. golangci-lint and gosec are optional, for enforcing the rules below.
allowed-tools: Read Edit Write Glob Grep Bash(go:*) Bash(gofmt:*) Bash(golangci-lint:*) Bash(gosec:*)
metadata:
  author: eduardo-sl
  version: "1.1.1"
---

# Go Defensive Coding

Go has no exceptions and no null-safety in the type system. Every trap below
compiles cleanly, passes review, and fails in production.

Detailed reference material, loaded on demand:

- `references/nil-and-aliasing.md` — the full typed-nil rules, slice
  aliasing scenarios, and memory retention.
- `references/numeric-safety.md` — conversion range checks, overflow
  detection, float and time comparison.

Read a reference file only when the section below is not enough.

## Operating Modes

- **Harden** — you are writing or changing code. Apply every rule as you go.
- **Review** — you are auditing existing code. Report findings with severity
  (🔴 panic or corruption, 🟡 latent bug, 🟢 style) and cite file:line.

## 1. The Typed-Nil Interface Trap

A non-nil interface can hold a nil pointer. This is the single most common
source of "impossible" nil checks in Go.

```go
type NotFoundError struct{ ID string }

func (e *NotFoundError) Error() string { return "not found: " + e.ID }

// ❌ Bad — returns a non-nil error even on success
func find(id string) error {
    var err *NotFoundError // typed nil
    if id == "" {
        err = &NotFoundError{ID: id}
    }
    return err // interface is (type=*NotFoundError, value=nil) — NOT nil
}

// ✅ Good — return the untyped nil literal
func find(id string) error {
    if id == "" {
        return &NotFoundError{ID: id}
    }
    return nil
}
```

Rules:

- Never declare a concrete error/pointer variable and return it as an
  interface. Return `nil` explicitly on the success path.
- Never store a possibly-nil concrete pointer in an `error`, `io.Reader`, or
  any interface-typed struct field.
- `go vet`'s `nilness` analyzer catches some of these. It does not catch all.

## 2. Nil Map, Slice, and Channel Behaviour

Memorise this table — half of these are safe and half panic or hang.

| Operation | nil map | nil slice | nil channel |
|---|---|---|---|
| Read / receive | zero value | index panics | blocks forever |
| Write / send | **panics** | `append` works | blocks forever |
| `len` / `cap` | `0` | `0` | `0` |
| `range` | zero iterations | zero iterations | blocks forever |
| `close` | n/a | n/a | **panics** |

```go
// ✅ A nil slice is a valid empty slice — do not guard append
var out []string
out = append(out, "a")

// ❌ A nil map is read-only
var m map[string]int
m["k"] = 1 // panic: assignment to entry in nil map

// ✅ Initialise every map before writing
m := make(map[string]int)
```

Return nil slices, not `[]T{}`. They marshal identically in JSON for
`encoding/json` when the field is `omitempty`, and cost no allocation.
Return an empty non-nil map only when the caller is documented to write to it.

## 3. Slice Aliasing

A slice is a view. `append` writes through that view whenever capacity
allows, mutating data the caller still owns.

```go
a := []int{1, 2, 3, 4}
b := a[:2]
b = append(b, 99) // ❌ overwrites a[2]; a is now [1 2 99 4]
```

```go
// ✅ Full slice expression caps the view — append must reallocate
b := a[:2:2]
b = append(b, 99) // a is untouched
```

Apply this whenever you hand a subslice to code you do not control, and
whenever a struct field holds a subslice of a larger buffer.

A subslice also keeps the entire backing array alive. To release a large
buffer, copy what you need: `head := slices.Clone(buf[:64])`.

## 4. Defensive Copying at Boundaries

Slices and maps are reference types. Storing or returning one without a copy
hands out a mutable handle to your internals.

```go
type Config struct{ hosts []string }

// ❌ Bad — caller can mutate our state, both ways
func NewConfig(hosts []string) *Config { return &Config{hosts: hosts} }
func (c *Config) Hosts() []string      { return c.hosts }

// ✅ Good — copy in, copy out
func NewConfig(hosts []string) *Config {
    return &Config{hosts: slices.Clone(hosts)}
}
func (c *Config) Hosts() []string { return slices.Clone(c.hosts) }
```

Use `maps.Clone` for maps. Both are shallow — a `[]*User` clone still shares
the pointed-to users.

Copy when the value is retained past the call or exposed to a caller. Do not
copy a slice you only read inside the function; that is wasted allocation.

### Preventing accidental copies

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

## 5. Numeric Conversion and Comparison

Go never panics on numeric conversion. It truncates.

```go
// ❌ Silent corruption when the value does not fit
count := int32(int64Total)

// ✅ Range-check before narrowing
if int64Total > math.MaxInt32 || int64Total < math.MinInt32 {
    return fmt.Errorf("total %d out of int32 range", int64Total)
}
count := int32(int64Total)
```

The same applies to `int` → `uint` (negatives wrap to huge values) and to
`len()` results assigned to sized types. `gosec` reports these as G115.

Never compare floats with `==`; never compare `time.Time` with `==`.

```go
// ✅ Floats: compare against a tolerance
if math.Abs(got-want) < 1e-9 { ... }

// ✅ Times: Equal compares the instant, == also compares wall clock and location
if t1.Equal(t2) { ... }
```

Integer division by zero panics; float division by zero yields `±Inf` or
`NaN`, and `NaN != NaN`. Guard divisors that come from input.

## 6. Resource Lifecycle

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

## 7. Zero-Value and Initialisation Safety

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

When lazy init must happen exactly once and may race, use `sync.Once`.

Avoid `init()`. It runs before `main`, cannot fail cleanly, cannot be tested
in isolation, and its cross-file order depends on filenames. Use an explicit
`New...` constructor that returns an error.

## Enforce with Tooling

Run these; do not rely on reading alone. Skip and note any tool that is not
installed.

```bash
go vet ./...                                  # includes the nilness analyzer
golangci-lint run                             # errcheck, bodyclose, makezero, sqlclosecheck
gosec -include=G115,G104,G601 ./...           # integer overflow, unhandled errors
go test -race ./...                           # aliasing bugs often surface as races
```

Relevant golangci-lint linters: `errcheck`, `bodyclose`, `sqlclosecheck`,
`rowserrcheck`, `makezero`, `nilerr`, `exhaustive`, and `govet` with the
`nilness` analyzer enabled.

Go 1.22 and later give each loop iteration its own variable. Do not add the
old `v := v` shadow line; do not remove one from a module still on `go 1.21`.

## Verification Checklist

1. No function returns a concrete pointer type as an interface on a success path
2. Every map is initialised before its first write
3. Subslices handed across a package boundary use a full slice expression `a[:n:n]`
4. Slices and maps stored in or returned from a struct are cloned
5. No type holding a mutex or atomic is passed or received by value
6. Every narrowing numeric conversion is range-checked, or documented as bounded
7. No `==` on floats or on `time.Time`
8. Divisors derived from input are checked against zero
9. No `defer` inside a loop body without an enclosing function scope
10. Deferred `Close` on written resources reports its error
11. `go vet`, `golangci-lint` and `go test -race` are clean
