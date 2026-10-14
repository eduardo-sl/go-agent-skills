---
name: go-troubleshooting
description: >
  Diagnose runtime problems in Go programs: panics and stack traces,
  deadlocks, goroutine leaks, memory leaks, OOM kills, race reports, and
  debugging with delve and pprof. Use when: "debug this panic", "read this
  stack trace", "deadlock", "memory leak", "goroutine count growing", "OOM",
  "program hangs", "race detector output", "use delve".
  Not for: optimizing code that works (go-performance-review), writing new
  concurrent code (go-concurrency-review), failing test design
  (go-test-quality).
user-invocable: true
license: MIT
compatibility: Designed for Claude Code or similar AI coding agents working on Go projects. Requires the Go toolchain. delve is optional, for interactive debugging.
allowed-tools: Read Edit Write Glob Grep Bash(go:*) Bash(gofmt:*) Bash(dlv:*)
metadata:
  author: eduardo-sl
  version: "1.5.0"
---

# Go Troubleshooting

Diagnosis before fixes. Reproduce, observe, localize, then change code.
Never "fix" a symptom you haven't explained — the bug will move.

Detailed reference material, loaded on demand:

- `references/methodology.md` — the debugging loop, tracing callers before
  blaming code, `git bisect`, red flags in your own reasoning.
- `references/flaky-and-build.md` — reproducing flaky tests and their usual
  causes; build, module and toolchain errors with their fixes.
- `references/common-bugs.md` — symptom → bug → fix tables for the Go bugs
  that compile cleanly and misbehave.

Read a reference file only when the summary below is not enough.

## 0. Method

1. State expected vs actual, and collect the full evidence (whole stack,
   exact input, trace ID).
2. Reproduce it in a failing test, then shrink the reproduction.
3. One hypothesis, one change, one observation — never stacked changes.
4. Fix the cause, not the trigger: keep asking why the bad value existed.
5. Three failed fixes means the mental model is wrong — start over from
   the evidence. If the cause predates you, `git bisect run` finds the
   commit.

## 1. Pick the Procedure by Symptom

| Symptom | Procedure |
|---|---|
| Wrong result, no crash | §0 Method, then `references/common-bugs.md` |
| Crash with stack trace | §2 Read the panic |
| Program hangs / requests stall | §3 Dump goroutines, find the block |
| `fatal error: all goroutines are asleep` | §3 — Go detected total deadlock |
| Memory grows until OOM | §4 Heap profile diff |
| Goroutine count grows | §5 Goroutine profile diff |
| Intermittent corrupt data / weird values | §6 Race detector |
| Need to inspect state interactively | §7 Delve |
| Incident in production right now | §11 Capture before restart |
| Test fails intermittently | §9 Flaky tests |
| Build, module or toolchain error | §10 Build failures |

## 2. Reading a Panic

```text
panic: runtime error: invalid memory address or nil pointer dereference
[signal SIGSEGV: segmentation violation code=0x1 addr=0x0 pc=0x6bb0e4]

goroutine 43 [running]:
myapp/internal/service.(*UserService).Notify(0x0, {0xc000123456?, ...})
        /app/internal/service/user.go:87 +0x24
myapp/internal/handler.(*Handler).Create(0xc0001a2000, ...)
        /app/internal/handler/user.go:41 +0x1c5
```

Read it mechanically:

1. First line: what kind of panic. `nil pointer dereference` + `addr=0x0`
   means a nil receiver, nil field, or nil map/pointer argument.
2. Top frame in YOUR code: `user.go:87` — go there.
3. Receiver value in the frame: `(*UserService).Notify(0x0, ...)` — the
   `0x0` first argument IS the receiver: the service itself was nil.
   Trace where it was constructed (or wasn't).
4. `goroutine 43` — if it's not goroutine 1, find who spawned it and
   whether a recover boundary should exist there.

## 3. Hangs and Deadlocks

Get a goroutine dump from the hanging process:

```bash
kill -QUIT <pid>      # dumps all goroutine stacks to stderr, then exits
# or, if net/http/pprof is mounted:
curl 'localhost:6060/debug/pprof/goroutine?debug=2'
```

Then classify the stacks:

- `[semacquire]` on `sync.(*Mutex).Lock` — find which goroutine HOLDS
  the mutex: look for another stack inside the critical section. Two
  goroutines each holding one of two locks = lock-order inversion.
- `[chan send]` / `[chan receive]` — the other side is gone. Find who
  should be receiving/sending and why it exited (or was never started).
- `[select]` with a `ctx.Done()` case missing — blocked call that
  ignores cancellation.
- Hundreds of identical stacks — that's a leak (§5), not a deadlock.

Slow rather than stuck? Enable `runtime.SetMutexProfileFraction` /
`SetBlockProfileRate` and read the mutex and block profiles, or take a
5-second trace (`/debug/pprof/trace?seconds=5`) to see goroutines that are
runnable but not running. `kill -QUIT` ends the process — in production,
prefer the pprof endpoint.

## 4. Memory Leaks

Mount `net/http/pprof` in long-running services on a private listener
(`localhost:6060`), never on the public mux.

Diff heap profiles over time — a leak is growth that never returns:

```bash
curl -s localhost:6060/debug/pprof/heap > heap1.pb.gz
sleep 300   # let the leak accumulate
curl -s localhost:6060/debug/pprof/heap > heap2.pb.gz
go tool pprof -base heap1.pb.gz heap2.pb.gz
(pprof) top          # biggest positive delta = the leak
(pprof) list FuncName
```

Usual suspects: unbounded caches/maps without eviction, subslices
pinning large arrays, `time.Ticker` never stopped, response bodies not
closed, growing global slices, forgotten goroutines holding buffers.

## 5. Goroutine Leaks

On Go 1.27+, start with the leak profile — goroutines blocked on a channel
or lock that nothing can ever release:

```bash
go tool pprof http://localhost:6060/debug/pprof/goroutineleak
```

It cannot see goroutines kept alive through globals or by goroutines that
are still running; for those, diff two goroutine profiles:

```bash
curl -s localhost:6060/debug/pprof/goroutine > g1.pb.gz
sleep 300
curl -s localhost:6060/debug/pprof/goroutine > g2.pb.gz
go tool pprof -base g1.pb.gz g2.pb.gz
(pprof) top    # the growing stack is your leak site
```

The leaking stack tells you which `go` statement never terminates.
Fix the termination path (context, channel close) — patterns in the
concurrency skill. In tests, `goleak` (uber-go/goleak) fails a test
that leaves goroutines behind.

## 6. Race Detector

```bash
go test -race ./...        # in CI, always
go build -race ./cmd/api   # staging binaries under real traffic
```

A report shows two stacks: the write and the concurrent read/write,
each with the goroutine's creation site. The fix is never "add a
sleep" — protect the state (mutex), transfer ownership (channel), or
make it immutable. `-race` only reports races that actually executed:
a clean run proves nothing about untested paths.

## 7. Delve

```bash
dlv test ./internal/service -- -test.run TestTransfer   # debug a test
dlv attach <pid>                                        # running process
dlv core ./api core.1234                                # post-mortem

(dlv) break user.go:87
(dlv) continue
(dlv) print svc.repo          # inspect exact values
(dlv) goroutines -t           # all goroutines with stacks
(dlv) goroutine 43 bt         # switch and backtrace
```

Use delve when you need actual values or goroutine states, not just
locations. For quick localizations, a focused `t.Logf` or `slog.Debug`
plus one test run is often faster.

## 8. Diagnostic Environment Variables

```bash
GOTRACEBACK=all ./api        # panic dumps ALL goroutines, not just one
GODEBUG=gctrace=1 ./api      # GC cycles: pacing, heap goal, pause times
GOMEMLIMIT=512MiB ./api      # soft memory limit — mitigates OOM while
                             # you find the real leak
GOTRACEBACK=crash ./api      # also write a core dump, for `dlv core`
GODEBUG=schedtrace=1000 ./api  # scheduler state every second
```

Go 1.27+ prints pprof goroutine labels in tracebacks; set
`GODEBUG=tracebacklabels=0` if labels carry anything sensitive.

## 9. Flaky Tests

Make it fail on demand before touching it: `-count=200 -failfast`, then
`-race`, `-shuffle=on` (replay with the printed seed), and `-cpu=1,2,8`.
The usual causes are sleeps used as synchronization, real clocks, shared
package state, map order in assertions, fixed ports, and goroutines leaking
from earlier tests. Retrying in CI hides the bug from you, not from users.

## 10. Build Failures

Read the first error only — later ones are usually consequences. Toolchain
too old (`GOTOOLCHAIN`), missing `go.sum` entries, ambiguous imports from
v1/v2 modules side by side, OS-specific files, missing C compiler, private
modules (`GOPRIVATE`) and the Go 1.27 `stdversion` check each have a fixed
remedy.

Commands and the full cause → fix tables: `references/flaky-and-build.md`.

## 11. Production Incidents

Capture before you restart — a restart destroys the evidence:

1. Goroutine dump (`/debug/pprof/goroutine?debug=2`), heap profile, a
   30-second CPU profile, and a 5-second trace — or a flight recorder
   snapshot (Go 1.25+) if the service runs one.
2. The exact build: `go version -m ./bin/api` shows the Go version, module
   versions and VCS revision.
3. Then restart, and analyze the captures offline with the procedures
   above. Serve pprof on an internal port only — it exposes stacks and
   the command line.

## Verification Checklist

1. Symptom reproduced (or captured via dump/profile) before any code change
2. Root cause explained: you can say WHY the failure happened at that site
3. Panic fixes address the nil/bounds source, not a wrapper `recover`
4. Deadlock fixes establish a single lock order or remove the shared lock
5. Leak fixes verified: goroutine/heap profile flat after the fix
6. `go test -race ./...` passes after concurrency-related fixes
7. A regression test now fails without the fix
8. pprof endpoints bound to localhost/private interfaces only
