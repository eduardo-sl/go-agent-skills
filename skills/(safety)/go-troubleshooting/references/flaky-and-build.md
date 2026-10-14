# Flaky Tests and Build Failures

Procedures for SKILL.md sections 9 and 10.

## Flaky tests

### Reproduce

```bash
go test -run 'TestTransfer$' -count=200 -failfast ./internal/payments   # make it fail on demand
go test -run 'TestTransfer$' -count=50 -race ./internal/payments        # a race behind it?
go test -shuffle=on -count=5 ./internal/payments                        # order dependence
go test -shuffle=1712345678 ./internal/payments                         # replay the seed it printed
go test -run 'TestTransfer$' -count=50 -cpu=1,2,8 ./internal/payments   # scheduling dependence

# Under load, the way CI runs it:
go test -c -o /tmp/payments.test ./internal/payments
go run golang.org/x/tools/cmd/stress@latest /tmp/payments.test -test.run 'TestTransfer$'
```

### Usual causes and fixes

| Cause | Fix |
|---|---|
| `time.Sleep` used to wait for a goroutine | `synctest.Test` + `synctest.Wait`, or a channel |
| Real clock, timezone, or DST | Inject the clock; `synctest` for timers; fixed `time.Location` |
| Shared package state between tests | Remove the global, or drop `t.Parallel()` for that test |
| Map iteration order in an assertion | Sort before comparing, or compare as sets |
| Fixed ports, shared temp paths | Port `0`, `t.TempDir()` |
| Environment variables | `t.Setenv` (it also refuses to run in parallel tests) |
| Leftover goroutines from a previous test | `goleak.VerifyNone(t)` to find which test leaks |
| A real network service | Fake it, or move the test behind an `integration` build tag |

Retrying a flaky test in CI hides the bug from you and not from your
users. Fix it or quarantine it with a tracked issue.

## Build failures

| Error | Meaning and fix |
|---|---|
| `go.mod requires go >= 1.N (running go 1.M; GOTOOLCHAIN=local)` | The module needs a newer toolchain. Install it, or allow `GOTOOLCHAIN=auto` to download it |
| `missing go.sum entry for module providing package` | `go mod tidy` (or `go mod download` in CI with a committed `go.sum`) |
| `ambiguous import: found package X in multiple modules` | Two modules provide the same path — usually an old and a v2+ module side by side; `go mod why -m`, then drop one |
| `undefined: Foo` on one OS only | A build-constrained file (`_linux.go`, `//go:build`); check with `GOOS=windows go build ./...` and `go list -f '{{.GoFiles}}' ./pkg` |
| `cgo: C compiler "gcc" not found` | Install a C toolchain, or build with `CGO_ENABLED=0`; note `-race` needs cgo |
| `import cycle not allowed` | Structural — the go-refactoring skill breaks cycles |
| `inconsistent vendoring` | `go mod vendor` after changing `go.mod` |
| `410 Gone` / `verifying module: ... not found` for a private module | Set `GOPRIVATE=example.com/*` (implies no proxy, no checksum DB) |
| `stdversion` vet failure under `go test` (Go 1.27+) | A stdlib API newer than the `go` directive — raise the directive or gate the file |
| `link: duplicated definition of symbol` | Two packages with the same import path linked in, usually via `replace`; inspect `go list -m all` |
