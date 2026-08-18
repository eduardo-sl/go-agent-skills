---
name: go-binary-size
description: >
  Reduce the size of compiled Go binaries and container images: linker
  flags, inlining budget, CGO and build tags, embedded assets, dependency
  weight, and measuring what actually costs bytes. Use when a binary or
  image is too large, when shrinking a CLI for distribution, or when
  auditing what a dependency adds to the build. Trigger examples: "binary is
  too big", "shrink the binary", "reduce image size", "strip symbols", "what
  is making my binary large", "ldflags -s -w".
  Not for: runtime speed and allocations (go-performance-review), CI setup
  (go-ci), dependency CVEs (go-dependency-audit).
user-invocable: true
license: MIT
compatibility: Designed for Claude Code or similar AI coding agents working on Go projects. Requires the Go toolchain. upx and go-size-analyzer are optional.
allowed-tools: Read Edit Write Glob Grep Bash(go:*) Bash(gofmt:*) Bash(strip:*) Bash(upx:*) Bash(gsa:*)
metadata:
  author: eduardo-sl
  version: "1.0.1"
---

# Go Binary Size

A stock Go binary carries the runtime, the garbage collector, full symbol and
line tables, and every transitively reachable package. 8-15 MiB for a small
CLI is normal. Most of it is removable, but only with measurement — guessing
which dependency is heavy is almost always wrong.

## Procedure

Never apply a flag without a before and after number.

1. Build a baseline and record its size.
2. Find where the bytes are.
3. Apply one change class at a time, measuring after each.
4. Verify the binary still runs and its tests still pass.
5. Report the table of change → bytes saved → cost.

## 1. Measure First

```bash
# Baseline, reproducible
CGO_ENABLED=1 go build -trimpath -o /tmp/base ./cmd/app
ls -l /tmp/base

# Which packages and symbols cost the most
go tool nm -size -sort size /tmp/base | head -40

# Package-level attribution (third-party, more readable)
go install github.com/Zxilly/go-size-analyzer/cmd/gsa@latest
gsa --web /tmp/base
```

`go version -m /tmp/app` prints the module list and build settings baked into
the binary — useful to confirm which flags a release actually used.

Also measure compressed size when the artifact ships in a container layer or
a release archive. Stripping wins less after gzip; removing a dependency wins
more.

```bash
gzip -c /tmp/base | wc -c
```

## 2. Strip Symbols and DWARF — the largest single win

```bash
go build -ldflags="-s -w" -trimpath -o /tmp/stripped ./cmd/app
```

Typically 25-35% off the raw size.

What this costs, precisely:

- ✅ Panic messages and goroutine stack traces still work. The runtime uses
  its own `pclntab`, which `-s -w` does not remove.
- ❌ `dlv` and `gdb` can no longer resolve source lines. Do not ship stripped
  binaries to an environment where you plan to attach a debugger.
- ⚠️ Some profiling and crash-reporting tools that symbolise externally will
  degrade. `net/http/pprof` in-process is unaffected.

Keep an unstripped copy of every release build for post-mortem work.

Add `-buildvcs=false` when the VCS stamp is not needed. It saves little, but
it also removes commit metadata from a distributed artifact.

## 3. Disable Inlining — measure the trade

```bash
go build -ldflags="-s -w" -gcflags=all=-l -o /tmp/noinline ./cmd/app
```

Another 5-10 percentage points. It costs runtime performance on hot paths.
Acceptable for a CLI that starts, does one thing, and exits. Not acceptable
for a latency-sensitive server without benchmarking the regression first.

## 4. CGO and the Runtime

```bash
CGO_ENABLED=0 go build -tags netgo,osusergo -ldflags="-s -w" -o /tmp/pure ./cmd/app
```

These three go together: disabling cgo without `netgo,osusergo` leaves the
build depending on the C resolver stubs.

Check before assuming it helps:

- `go list -deps ./... | xargs go list -f '{{.ImportPath}} {{.CgoFiles}}'`
  shows which packages actually use cgo.
- Disabling cgo can **increase** size when the pure-Go replacement of a C
  binding is larger. Measure both.
- If the release config already sets `CGO_ENABLED=1` or
  `-linkmode=external`, there is a reason. Find it before changing it.

When cgo must stay and the project compiles C sources (SQLite bindings, image
codecs), `CGO_CFLAGS="-Oz"` optimises that C code for size.

## 5. Build Tags — the step most often skipped

Heavyweight optional features are usually gated behind tags that live outside
the Go source.

```bash
grep -rn '//go:build' --include='*.go' . | grep -v _test.go
grep -rnE '\-tags' Makefile Taskfile.y*ml .goreleaser.y*ml Dockerfile .github/workflows/ 2>/dev/null
```

Common wins: dropping a driver you do not use, excluding an admin UI from the
production build, building a `noembed` variant that fetches assets at runtime.

## 6. Dependency Weight

A single import can dominate the binary. `gsa` attributes bytes per module —
start there, not from intuition.

Recurring offenders:

- Cloud provider SDKs. Import the individual service package, never the
  aggregate root.
- `github.com/prometheus/client_golang` pulls a large surface for a handful
  of counters.
- Anything reflection-heavy: the linker cannot dead-code-eliminate through
  `reflect`, so a reflection-based codec keeps types alive that nothing calls.
- Generated protobuf packages for protos you do not use.

Replacing a dependency with 40 lines of standard library is a legitimate
size fix. Replacing a well-maintained dependency with your own crypto is not.

## 7. Embedded Assets

`//go:embed` content is stored uncompressed.

```go
//go:embed assets/*
var assets embed.FS
```

Options, in order of preference: ship fewer assets; pre-compress them and
serve with `Content-Encoding: gzip`; move them out of the binary entirely and
into the container image or a CDN.

## 8. Container Images

The binary is often the smaller half of the problem.

```dockerfile
FROM golang:1.25 AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/app ./cmd/app

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/app /app
USER nonroot:nonroot
ENTRYPOINT ["/app"]
```

`scratch` is smaller than `distroless/static` but ships no CA certificates,
no `/etc/passwd`, and no timezone database. Use `distroless/static` unless
you have verified the binary needs none of them.

## 9. UPX — last resort, usually wrong

`upx --best` roughly halves the on-disk size and costs decompression on every
start, breaks `mmap`-based tooling, and is a strong antivirus and EDR
heuristic trigger. Do not pack a binary that ships to end users or runs in a
monitored production environment. Consider it only for a size-constrained
embedded target, and say so explicitly in the report.

## Verification

After every change:

```bash
go build -o /tmp/candidate ./cmd/app && /tmp/candidate --version
go test ./...
ls -l /tmp/base /tmp/candidate
```

A smaller binary that no longer starts, or that lost a feature guarded by a
build tag, is not a win.

## Verification Checklist

1. A baseline size was recorded before any flag changed
2. Every claimed saving has a before/after number, raw and compressed
3. `-s -w` applied, and an unstripped artifact retained for debugging
4. `-gcflags=all=-l` benchmarked, not assumed, on latency-sensitive code
5. `CGO_ENABLED=0` measured both ways, not applied blind
6. Build tags in Makefile, goreleaser, Dockerfile and CI workflows inspected
7. Dependency attribution done with a tool, not from intuition
8. The candidate binary runs and the test suite passes
9. UPX used only with an explicit justification
