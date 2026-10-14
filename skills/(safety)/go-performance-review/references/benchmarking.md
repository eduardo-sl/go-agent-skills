# Benchmarking

How to produce numbers that survive review. The SKILL.md Benchmarking
section states the rules; this file has the commands and the reading guide.

## Contents

- Benchmark shape
- Running
- Reading benchstat
- Comparing several variants
- Documenting a result
- Regression detection in CI

## Benchmark shape

```go
// parser_bench_test.go — named after the source file, like parser_test.go
func BenchmarkParse(b *testing.B) {
    for _, size := range []int{64, 4 << 10, 1 << 20} {
        input := makeInput(size) // setup: outside the timed loop
        b.Run(fmt.Sprintf("size=%d", size), func(b *testing.B) {
            b.ReportAllocs()
            b.SetBytes(int64(size)) // adds MB/s to the output
            for b.Loop() {          // Go 1.24+
                Parse(input)
            }
        })
    }
}
```

- One benchmark per function under study; sub-benchmarks for each input
  size, so a change that helps small inputs and hurts large ones shows up.
- Inputs sized like production. A 10-element benchmark of an O(n²)
  algorithm looks fine.
- `b.Loop()` keeps the call alive; with the pre-1.24 `b.N` loop, assign
  the result to a package-level sink and call `b.ResetTimer()` after setup.

## Running

```bash
# -run '^$' skips unit tests; -count=10 gives benchstat enough samples
go test -run '^$' -bench '^BenchmarkParse$' -benchmem -count=10 ./internal/parser | tee old.txt

# profile the same benchmark
go test -run '^$' -bench '^BenchmarkParse$' -cpuprofile cpu.out -memprofile mem.out ./internal/parser

# scaling with cores
go test -run '^$' -bench . -cpu 1,2,4,8 ./internal/cache
```

Close other heavy processes, keep the laptop on power, and run before and
after on the **same machine and the same Go toolchain**. Go 1.27's
allocator alone shifts allocation-heavy baselines.

## Reading benchstat

```text
goos: linux
goarch: amd64
                 │   old.txt    │               new.txt               │
                 │    sec/op    │   sec/op     vs base                │
Parse/size=4096    18.42µ ± 2%   11.07µ ± 1%  -39.90% (p=0.000 n=10)
Parse/size=64      402.1n ± 3%   405.8n ± 4%       ~ (p=0.481 n=10)
```

- `± 2%` is the spread across runs. Spread above ~5% means the machine
  was noisy; fix that before trusting any delta.
- `~` means no statistically significant difference. Report it as
  "no change", never as the small percentage you hoped for.
- `p` below 0.05 with `n=10` is the bar for claiming an improvement.
- `-benchmem` adds `B/op` and `allocs/op` tables; an allocation drop with
  no `sec/op` change is still worth keeping on a hot path under GC
  pressure.

## Comparing several variants

When several candidate optimizations compete, build each one on its own
branch or worktree, but **run the benchmarks one at a time**. Concurrent
runs share CPUs and caches and reintroduce exactly the noise `-count` and
benchstat exist to remove. Compare every variant against the same
baseline file:

```bash
benchstat base=old.txt pool=pool.txt arena=arena.txt
```

## Documenting a result

Put the benchstat table in the commit body, so reviewers can verify the
claim and future readers do not revert an "unnecessary" optimization:

```text
perf(parser): reuse the token buffer across Parse calls

Parse allocated a fresh []Token per call; the buffer now comes from a
sync.Pool, capped at 64 KiB so one huge document cannot pin memory.

Parse/size=4096   18.42µ ± 2%   11.07µ ± 1%  -39.90% (p=0.000 n=10)
Parse/size=4096   4.12Ki ± 0%   0.06Ki ± 0%  -98.54% (p=0.000 n=10)  B/op
```

## Regression detection in CI

- Run the benchmark subset on the base commit and the PR head in the
  same job, on the same runner, then `benchstat base.txt head.txt`.
- Hosted CI runners are noisy. Gate only on large regressions (for
  example >10% with p < 0.05), or use a dedicated, pinned runner.
- Store results per commit (as artifacts or in a results branch) to see
  slow drifts that no single PR crosses.
