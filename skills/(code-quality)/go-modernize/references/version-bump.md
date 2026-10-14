# Raising the `go` Directive

A version bump changes behavior even when no source line changes. Treat it
as its own reviewed change, separate from adopting new features.

## Contents

- Procedure
- Go 1.27
- Go 1.26
- Go 1.25

## Procedure

1. Confirm CI images, Dockerfiles and `setup-go` already run the target
   toolchain. A `go` line newer than the build image fails the build.
2. In one commit: `go mod edit -go=1.N` (update `toolchain` only if the
   project pins one), then `go mod tidy`.
3. Run `go vet ./...` and `go test -race ./...`. From Go 1.27, `go test`
   also runs the `stdversion` check, which fails on stdlib APIs newer than
   a file's effective Go version — bump the directive or gate the file with
   a build tag; do not silence it.
4. Walk the checklist for every version you crossed, oldest first.
5. Only then, in later commits, run `go fix ./...` and adopt new features.

## Go 1.27

- **Removed GODEBUG settings fail the build when pinned to an old value**:
  `asynctimerchan`, `tlsunsafeekm`, `tlsrsakex`, `tls3des`, `tls10server`,
  `x509keypairleaf`, `gotypesalias`. Search `go.mod` `godebug` blocks and
  `//go:debug` directives:

  ```bash
  grep -rn --include=go.mod --include='*.go' -e 'godebug' -e '//go:debug' .
  ```

  With `asynctimerchan` gone, `time` channels are always unbuffered: code
  that inspected `len(timer.C)` or relied on a buffered tick changes
  behavior.
- **`encoding/json` error text may differ** — it now runs on the v2 engine.
  Tests asserting on JSON error strings break; assert on `errors.As` with
  `*json.SyntaxError` / `*json.UnmarshalTypeError` instead.
- **`compress/flate` output changed** — and with it `compress/gzip`,
  `compress/zlib`, `archive/zip` and `image/png`. Golden files holding
  compressed bytes break; compare decompressed content.
- **Function literal names changed**, and identical literals may share
  code. Tests that match `func1`-style names in stack traces, or compare
  `reflect.Value.Pointer` of closures, break.
- **gofmt alignment changed** — expect small whitespace diffs; land the
  `gofmt` run as its own commit.
- **`go mod tidy` merges `require` blocks** into one direct and one
  indirect block — a one-off `go.mod` diff.
- **Tracebacks print pprof goroutine labels.** If labels carry tenant IDs
  or anything sensitive, set `GODEBUG=tracebacklabels=0` or stop putting it
  in labels.
- **`net/http`**: an HTTP/1 `Response.Body` drains unread content on close
  (up to a limit), and `Server.MaxHeaderValueCount` applies a default limit
  on repeated header values.
- **`net`**: `UnixConn` reads return `io.EOF` directly, no longer wrapped
  in `*net.OpError`.
- **`crypto/x509`**: `SystemCertPool` honors `SSL_CERT_FILE` /
  `SSL_CERT_DIR` on macOS and Windows too.
- **`go vet` printf** flags `fmt.Errorf("...: %w", p)` when `p` is `*E` and
  `E` has a value-receiver `Error` — `errors.As` targets for `E` miss it.
- **Allocator**: allocations under 80 bytes are up to 30% cheaper, binaries
  grow ~60 KB. A benchmark comparison across the 1.26→1.27 boundary
  measures the toolchain — rerun the baseline on the new toolchain.
- **Ports**: macOS 13 minimum; `linux/ppc64` is ELFv2 (kernel 3.13+);
  `bzr` VCS support removed from the `go` command.

## Go 1.26

- **Green Tea GC is the default.** Re-measure before keeping old `GOGC`
  tuning. The `nogreenteagc` opt-out was scheduled for removal in 1.27.
- **Caller-supplied randomness is ignored** by `crypto/ecdsa`,
  `crypto/ed25519`, `crypto/rsa`, `crypto/ecdh`, `crypto/dsa` and
  `crypto/rand`. Tests that fed a fixed reader to get deterministic
  signatures break (`GODEBUG=cryptocustomrand=1` is temporary).
- **Hybrid post-quantum TLS key exchanges** (`SecP256r1MLKEM768`,
  `SecP384r1MLKEM1024`) are on by default — middleboxes that choke on
  large ClientHellos surface here.
- **`net/url.Parse` rejects colons in the host** (`http://::1/`);
  `urlstrictcolons=0` restores the old parse.
- **`net/http.ServeMux` trailing-slash redirects are 307**, not 301, and
  `httptest.Server.Client` routes `example.com` to the test server.
- **`image/jpeg` was reimplemented** — golden files of JPEG bytes break.
- **`go mod init` writes `go 1.(N-1).0`**, not the toolchain version. Set
  the directive deliberately when the project needs the newer APIs.
- **`go tool doc` is gone** — use `go doc`.
- **`go fix` runs the modernizers** — review its diff like any other.

## Go 1.25

- **Container-aware `GOMAXPROCS`.** The runtime now honors cgroup CPU
  limits and updates when they change (`containermaxprocs=0`,
  `updatemaxprocs=0` opt out). Remove `go.uber.org/automaxprocs` unless a
  measurement says otherwise.
- **Nil checks are no longer delayed.** A 1.21–1.24 compiler bug let code
  use a result before checking its error without panicking:

  ```go
  f, err := os.Open(name)
  n := f.Name() // panics on Go 1.25+ when Open failed — check err first
  if err != nil { ... }
  ```

- **New vet analyzers** `waitgroup` (misplaced `wg.Add`) and `hostport`
  (`fmt.Sprintf("%s:%d")` addresses for `net.Dial`) report new findings.
- **DWARF 5** debug info by default — older debuggers and binary tooling
  may need upgrading.
