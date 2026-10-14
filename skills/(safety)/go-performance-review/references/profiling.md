# Profiling

Finding *why* code is slow. The SKILL.md Profiling section states the
rules; this file has the commands and how to read the output.

## Contents

- Which profile for which symptom
- Capturing profiles
- Reading pprof
- Compiler diagnostics
- Execution traces and the flight recorder
- Off-CPU time and continuous profiling

## Which profile for which symptom

| Symptom | Start with | Look for |
|---|---|---|
| High CPU | CPU profile | Functions with high `flat` |
| High allocation rate, GC in the CPU profile | heap, `-sample_index=alloc_objects` | Who allocates most often |
| Memory grows over time | heap `inuse_space`, two snapshots, `-base` | Growth between snapshots |
| Latency high, CPU idle | goroutine dump, block and mutex profiles, a trace | Goroutines waiting, and on what |
| Goroutine count grows | `goroutineleak` (Go 1.27+), goroutine profile diff | Stacks blocked forever |
| Lock contention | mutex profile | Contended `Unlock` call sites |
| Scheduling delays, GC pauses | execution trace | Runnable goroutines not running |

## Capturing profiles

```bash
# From a benchmark — no server needed
go test -run '^$' -bench '^BenchmarkParse$' -cpuprofile cpu.out -memprofile mem.out ./internal/parser

# From a running service exposing net/http/pprof on a private port
go tool pprof http://localhost:6060/debug/pprof/profile?seconds=30   # CPU
go tool pprof http://localhost:6060/debug/pprof/heap                 # live heap
go tool pprof http://localhost:6060/debug/pprof/allocs               # all allocations
curl -s 'http://localhost:6060/debug/pprof/goroutine?debug=2' > goroutines.txt
curl -o trace.out 'http://localhost:6060/debug/pprof/trace?seconds=5'
```

Block and mutex profiles are empty until the program opts in, because
recording them costs CPU:

```go
runtime.SetMutexProfileFraction(5)                // sample 1 in 5 contention events
runtime.SetBlockProfileRate(int(time.Millisecond)) // ~1 sample per ms spent blocked
```

## Reading pprof

```bash
go tool pprof -http=:0 cpu.out                         # flame graph + source in a browser
go tool pprof -top -cum cpu.out                        # cumulative ranking
go tool pprof -sample_index=alloc_objects mem.out      # count, not bytes
go tool pprof -base heap1.pb.gz heap2.pb.gz            # what grew in between
```

| You see | It usually means |
|---|---|
| High `flat` | The function itself burns the CPU — optimize its body |
| Low `flat`, high `cum` | The cost is in its callees — follow `peek`/`list` down |
| `runtime.mallocgc` near the top | Too many allocations — switch to the alloc profile |
| `runtime.memmove` | Copying: growing slices, string/byte conversions |
| `runtime.scanobject`, `gcBgMarkWorker` | GC work — reduce pointers and allocation rate |
| `runtime.futex`, `sync.(*Mutex).lockSlow` | Contention — take the mutex profile |
| `alloc_objects` high, `inuse_space` low | Short-lived garbage — a pool or reuse helps |
| `inuse_space` keeps growing | A leak: an unbounded cache, retained subslices, leaked goroutines |

## Compiler diagnostics

```bash
go build -gcflags='-m' ./internal/parser 2>&1 | grep -E 'escapes|moved to heap'
go build -gcflags='-m=2' ./internal/parser 2>&1 | grep 'cannot inline'   # and why
go build -gcflags='-d=ssa/check_bce/debug=1' ./internal/parser            # bounds checks left in
```

`moved to heap: x` on a hot path is an allocation per call. Common causes:
storing the value in an interface, returning its address, capturing it in
a closure that outlives the call, or a size unknown at compile time.

## Execution traces and the flight recorder

```bash
go test -run '^$' -bench '^BenchmarkServe$' -trace trace.out ./server
go tool trace trace.out    # Go 1.27+: -http binds to localhost unless told otherwise
```

A trace shows what pprof cannot: goroutines that were runnable but not
running, time blocked on syscalls and channels, and GC stop-the-world
pauses. Annotate business operations with `trace.NewTask`,
`trace.WithRegion` and `trace.Log` so they appear by name.

The flight recorder (Go 1.25+) keeps the last few seconds of trace in
memory and writes them out only when something goes wrong:

```go
fr := trace.NewFlightRecorder(trace.FlightRecorderConfig{
    MinAge:   10 * time.Second, // keep at least this much history
    MaxBytes: 16 << 20,         // and at most this much memory
})
if err := fr.Start(); err != nil {
    return err
}
defer fr.Stop()

// In the slow-request path:
if elapsed > slowThreshold {
    f, _ := os.Create(fmt.Sprintf("slow-%d.trace", time.Now().Unix()))
    defer f.Close()
    _, _ = fr.WriteTo(f) // the seconds that led up to the slow request
}
```

## Off-CPU time and continuous profiling

- The CPU profile only samples running goroutines. When latency is high
  and CPU is low, the time is spent waiting: read the goroutine dump, the
  block profile, and a trace. Wall-clock profilers such as `fgprof`
  combine on- and off-CPU time in one view.
- Continuous profiling (Pyroscope, Parca, Grafana) samples production all
  the time, so a regression can be diffed against yesterday's profile
  instead of reproduced.
- Profiles are also the input to PGO — see `runtime-tuning.md`.
