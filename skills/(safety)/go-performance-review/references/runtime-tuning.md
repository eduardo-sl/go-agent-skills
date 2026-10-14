# Runtime Tuning

GC, memory limit, GOMAXPROCS and profile-guided optimization. The
SKILL.md Runtime Tuning section states the rules; this file has the detail.

## GOGC and GOMEMLIMIT

- `GOGC=100` (the default) lets the heap grow to roughly twice the live
  heap before the next collection. Raising it trades memory for fewer
  collections; lowering it does the opposite.
- `GOMEMLIMIT` (Go 1.19+) is a soft ceiling on total Go memory. In a
  container, set it to about 80-90% of the memory limit: the GC works
  harder as the ceiling approaches instead of letting the kernel OOM-kill
  the process.
- Keep both. `GOGC=off` with only a memory limit collects nothing until
  the limit, and a live heap near the limit then spends most of its CPU
  in GC.
- The heap "ballast" trick (a large unused allocation) is obsolete since
  `GOMEMLIMIT`; remove it.

```go
debug.SetMemoryLimit(int64(0.85 * float64(containerLimitBytes)))
```

## Observing the GC

```bash
GODEBUG=gctrace=1 ./service 2>&1 | head
# gc 42 @12.3s 2%: 0.02+3.1+0.01 ms clock, ... 48->52->25 MB, 50 MB goal, 8 P
#                ^ share of CPU spent in GC since start   ^ heap before->after->live
```

In code, read `runtime/metrics` (`/gc/heap/goal:bytes`,
`/gc/cycles/total:gc-cycles`, `/memory/classes/heap/objects:bytes`)
rather than `runtime.ReadMemStats`, which stops the world.

## GOMAXPROCS

From Go 1.25 the runtime sets `GOMAXPROCS` from the cgroup CPU limit and
updates it when the limit changes. Delete `go.uber.org/automaxprocs`.
Setting `GOMAXPROCS` explicitly turns the automatic behavior off — only do
it with a measurement that justifies it.

## Profile-guided optimization (Go 1.21+)

1. Capture a CPU profile from production under representative load
   (`/debug/pprof/profile?seconds=30`, or merge several with
   `go tool pprof -proto a.pb.gz b.pb.gz > merged.pgo`).
2. Commit it as `default.pgo` in the main package's directory.
3. `go build` picks it up automatically (`-pgo=auto`); the compiler
   inlines and devirtualizes the hot calls more aggressively.

Gains are typically a few percent of CPU. Refresh the profile after large
changes; a stale profile costs nothing but a missed opportunity.

## Toolchain-driven changes

- **Go 1.26 — Green Tea GC is the default.** It changes GC cost
  characteristics; re-measure before keeping old `GOGC` tuning.
- **Go 1.27 — size-specialized allocation.** Allocations under 80 bytes
  are up to 30% cheaper. Re-run baselines on the new toolchain before
  comparing.
