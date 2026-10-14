# Concurrency, Context and Benchmarks in Tests

Worked examples for SKILL.md sections 7 and 8.

## Contents

- Testing concurrent code
  - Detect goroutine leaks
- Test context, benchmarks, and artifacts

## Testing concurrent code

Never synchronize a test with `time.Sleep`. It is slow when it works and
flaky when it does not.

`testing/synctest` (Go 1.25+) runs a test inside a bubble with a fake clock.
Time advances instantly whenever every goroutine in the bubble is blocked, so
a one-hour timeout test finishes in microseconds and is deterministic.

```go
import "testing/synctest"

func TestCacheExpiry(t *testing.T) {
    synctest.Test(t, func(t *testing.T) {
        c := NewCache(time.Hour)
        c.Set("k", "v")

        time.Sleep(59 * time.Minute) // instant: fake clock
        if _, ok := c.Get("k"); !ok {
            t.Fatal("entry expired early")
        }

        time.Sleep(2 * time.Minute)
        if _, ok := c.Get("k"); ok {
            t.Fatal("entry outlived its TTL")
        }
    })
}
```

`synctest.Wait()` blocks until every other goroutine in the bubble is durably
blocked — use it instead of sleeping to let a background goroutine reach a
known point.

On Go 1.24 the package is behind `GOEXPERIMENT=synctest` and the entry point
is `synctest.Run`. Below 1.24, poll with a deadline instead of sleeping.

### Detect goroutine leaks

A test that leaks a goroutine passes locally and destabilises the suite.

```go
import "go.uber.org/goleak"

// Whole package, in TestMain:
func TestMain(m *testing.M) { goleak.VerifyTestMain(m) }

// Or per test:
func TestWorker(t *testing.T) {
    defer goleak.VerifyNone(t)
    // ... every goroutine started here must exit before the test returns
}
```

Add it to any package that starts goroutines. `go test -race` finds data
races; it does not find a goroutine that never exits.

## Test context, benchmarks, and artifacts

Use `t.Context()` (Go 1.24+) instead of `context.Background()`. It is
cancelled before `t.Cleanup` functions run, so anything blocking on it
unwinds when the test ends — including on timeout or failure.

```go
func TestFetch(t *testing.T) {
    ctx := t.Context()
    got, err := client.Fetch(ctx, "id-1") // cancelled automatically at test end
    // ...
}
```

Write benchmarks with `for b.Loop()` (Go 1.24+), not `for range b.N`. It runs
setup exactly once, keeps arguments and results alive without a sink
variable, and cannot be optimised away.

```go
// ✅ Go 1.24+
func BenchmarkEncode(b *testing.B) {
    in := makeInput()
    for b.Loop() {
        Encode(in)
    }
}

// ❌ Pre-1.24 form — needs a package-level sink to defeat dead-code elimination
func BenchmarkEncode(b *testing.B) {
    in := makeInput()
    for range b.N {
        sink = Encode(in)
    }
}
```

Report allocations with `b.ReportAllocs()` and compare runs with `benchstat`.

Two newer reporting hooks, when the toolchain supports them:

- `t.Attr("build", sha)` (Go 1.25+) emits a key/value pair into the test log
  for CI to parse.
- `t.ArtifactDir()` with `go test -artifacts` (Go 1.26+) gives the test a
  directory that survives the run — write failing golden output, captured
  HTTP bodies, or profiles there instead of into the repository.
