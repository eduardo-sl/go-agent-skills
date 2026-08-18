---
name: go-troubleshooting
description: >
  Diagnose runtime problems in Go programs: panics and stack traces, deadlocks,
  goroutine leaks, memory leaks, OOM kills, race reports, and debugging with
  delve and pprof.
  Use when: "debug this panic", "read this stack trace", "deadlock", "memory
  leak", "goroutine count growing", "OOM", "program hangs", "race detector
  output", "use delve".
  Do NOT use for: optimizing code that works (use go-performance-review),
  writing new concurrent code (use go-concurrency-review), or
  failing test design (use go-test-quality).
user-invocable: true
license: MIT
compatibility: Designed for Claude Code or similar AI coding agents working on Go projects. Requires the Go toolchain. delve is optional, for interactive debugging.
allowed-tools: Read Edit Write Glob Grep Bash(go:*) Bash(gofmt:*) Bash(dlv:*)
metadata:
  author: eduardo-sl
  version: "1.1.0"
---

# Go Troubleshooting

Diagnosis before fixes. Reproduce, observe, localize, then change code.
Never "fix" a symptom you haven't explained — the bug will move.

## 1. Pick the Procedure by Symptom

| Symptom | Procedure |
|---|---|
| Crash with stack trace | §2 Read the panic |
| Program hangs / requests stall | §3 Dump goroutines, find the block |
| `fatal error: all goroutines are asleep` | §3 — Go detected total deadlock |
| Memory grows until OOM | §4 Heap profile diff |
| Goroutine count grows | §5 Goroutine profile diff |
| Intermittent corrupt data / weird values | §6 Race detector |
| Need to inspect state interactively | §7 Delve |

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
# or, if net/http/pprof is mounted (see §4):
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

## 4. Memory Leaks

Mount pprof in long-running services (private port only, never public):

```go
import _ "net/http/pprof"

go func() {
    log.Println(http.ListenAndServe("localhost:6060", nil))
}()
```

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
```

## Verification Checklist

1. Symptom reproduced (or captured via dump/profile) before any code change
2. Root cause explained: you can say WHY the failure happened at that site
3. Panic fixes address the nil/bounds source, not a wrapper `recover`
4. Deadlock fixes establish a single lock order or remove the shared lock
5. Leak fixes verified: goroutine/heap profile flat after the fix
6. `go test -race ./...` passes after concurrency-related fixes
7. A regression test now fails without the fix
8. pprof endpoints bound to localhost/private interfaces only
