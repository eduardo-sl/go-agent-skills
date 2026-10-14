---
name: go-build-release
description: >
  Build and release Go binaries that are reproducible and verifiable:
  version stamping, -trimpath builds, cross-compilation, GoReleaser,
  checksums, SBOMs, cosign signing, build provenance attestations, and
  container images with ko or a multi-stage Dockerfile. Use when: "release
  a Go binary", "set up GoReleaser", "cross-compile", "reproducible build",
  "sign the release", "generate an SBOM", "build provenance", "publish a
  container image", "version command shows (devel)".
  Not for: test and lint pipelines (go-ci), shrinking the binary or image
  (go-binary-size), auditing dependencies (go-dependency-audit).
user-invocable: true
license: MIT
compatibility: Designed for Claude Code or similar AI coding agents working on Go projects. Requires the Go toolchain and git. GoReleaser, cosign, syft and ko are optional, used when the project adopts them.
allowed-tools: Read Edit Write Glob Grep Bash(go:*) Bash(git:*) Bash(goreleaser:*)
metadata:
  author: eduardo-sl
  version: "1.0.0"
---

# Go Build and Release

A release is a promise that the binary users run is the one your source
and pipeline produced. Make it reproducible so anyone can rebuild it, and
verifiable so anyone can check it — before automating the publishing.

Detailed reference material, loaded on demand:

- `references/goreleaser.md` — a complete `.goreleaser.yaml` and the
  tag-triggered release workflow.
- `references/supply-chain.md` — SBOMs, cosign signing and verification,
  provenance attestations, signing container images.

Read a reference file only when the summary below is not enough.

## 1. Version Stamping

```go
// Go 1.24+: built from a git checkout, Main.Version is the tag (v1.4.0)
// or a pseudo-version; vcs.* settings carry the commit and dirty flag.
info, _ := debug.ReadBuildInfo()
fmt.Println(info.Main.Version, info.GoVersion)
```

```bash
go version -m ./bin/api          # inspect what a binary was built from
```

- Prefer build info: it needs no flags and cannot drift from the source.
- When a release tool builds from an archive without `.git`, inject the
  values: `-ldflags "-X main.version=v1.4.0 -X main.commit=$SHA"`.
- Never stamp the wall-clock build time — it makes every build unique.
  Use the commit time if you need a date.

## 2. Reproducible Builds

The same source, toolchain and flags must give byte-identical binaries:

```bash
CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o bin/api ./cmd/api
sha256sum bin/api   # rebuild in a clean checkout and compare
```

- `-trimpath` removes your machine's paths from the binary.
- Pin the toolchain: the `go` and `toolchain` lines in `go.mod`, the same
  image or `setup-go` version in CI. Go's own toolchain is reproducible
  since 1.21.
- `CGO_ENABLED=0` unless you need cgo — a C toolchain is one more input
  that varies between machines.
- `go mod download` and `go mod verify` before building, so a tampered
  module cache fails the build.

## 3. Cross-Compilation

```bash
go tool dist list                                  # every GOOS/GOARCH pair
GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -trimpath -o bin/api-linux-arm64 ./cmd/api
GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go build -trimpath -o bin/api.exe ./cmd/api
```

Pure Go cross-compiles from any host. With cgo you need a C cross-compiler
per target; prefer pure-Go dependencies (e.g. a pure-Go SQLite driver)
when you ship to several platforms. Raise `GOAMD64` (v2/v3) only when every
target CPU supports it — the binary will not start on older ones.

## 4. Release Automation with GoReleaser

One config builds every target, archives, checksums, SBOMs and signs:

```yaml
# .goreleaser.yaml (excerpt — full file in references/goreleaser.md)
version: 2
builds:
  - main: ./cmd/api
    env: [CGO_ENABLED=0]
    flags: [-trimpath]
    ldflags: ["-s -w -X main.version={{.Version}} -X main.commit={{.Commit}}"]
    mod_timestamp: "{{ .CommitTimestamp }}" # reproducible file times
    goos: [linux, darwin, windows]
    goarch: [amd64, arm64]
checksum:
  name_template: checksums.txt
```

```bash
goreleaser check                         # validate the config
goreleaser release --snapshot --clean    # full dry run, nothing published
```

Release on tag push (`v1.4.0`) from CI, never from a laptop: the pipeline
is the only place whose inputs are recorded.

## 5. Supply-Chain Artifacts

| Artifact | Answers | Produced by |
|---|---|---|
| `checksums.txt` | Did my download arrive intact? | GoReleaser `checksum` |
| SBOM (SPDX or CycloneDX) | What is inside this binary? | `syft`, GoReleaser `sboms` |
| Signature bundle (`.sigstore.json`) | Did this project's pipeline publish it? | `cosign sign-blob --bundle`, keyless in CI |
| Provenance attestation | Which workflow, commit and runner built it? | `actions/attest` (SLSA provenance) |

Sign the checksums file rather than every archive — one signature then
covers them all. Keyless signing uses the CI job's OIDC identity, so there
is no private key to leak or rotate. Publish the exact verification
commands in the release notes; a signature nobody verifies protects
nobody. Commands: `references/supply-chain.md`.

## 6. Container Images

- **Pure-Go services: `ko`.** Builds from the Go source without a
  Dockerfile, on a distroless base, multi-arch, with an SBOM, reproducibly:
  `KO_DOCKER_REPO=ghcr.io/acme ko build --bare --platform=linux/amd64,linux/arm64 ./cmd/api`.
- **Otherwise a multi-stage Dockerfile:** build in `golang:<version>`,
  copy the binary into `gcr.io/distroless/static:nonroot`, run as non-root.
- Reference images by digest in deployments, and sign them with cosign.
- Image size is owned by the go-binary-size skill.

## 7. Versioning

- Tags are semver with a `v` prefix: `v1.4.0`. Never move or delete a
  published tag — the module proxy has cached it, and users' `go.sum`
  pins its hash.
- A breaking change to a library is a new major version with a `/v2`
  module path, not just a `v2.0.0` tag.
- A bad release is withdrawn with `retract` in `go.mod` (the
  go-dependency-audit skill), then fixed in a new patch release.
- Generate release notes from Conventional Commits (git-commit skill);
  GoReleaser's `changelog.groups` sorts them into features and fixes.

## Verification Checklist

1. `go version -m` on the release binary shows the tag and commit
2. Two clean builds of the same tag produce identical SHA-256 sums
3. `-trimpath`, `CGO_ENABLED=0` (or a justified cgo build), pinned toolchain
4. No build timestamps; file times derived from the commit
5. Releases come from a tag-triggered CI job, never a laptop
6. `checksums.txt` is signed; SBOMs are published; provenance is attested
7. Release notes include the `cosign verify-blob` / `gh attestation verify` commands
8. Images built with ko or multi-stage on distroless, non-root, referenced by digest
9. Published tags are never moved; bad releases are retracted
