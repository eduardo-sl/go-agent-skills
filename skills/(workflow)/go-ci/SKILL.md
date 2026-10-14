---
name: go-ci
description: >
  Continuous integration for Go projects: GitHub Actions pipelines, caching,
  golangci-lint setup, test/coverage gates, vulnerability scanning, SAST
  (CodeQL, gosec), Dependabot, action pinning, build matrices, Makefile
  targets. Use when: "set up CI", "GitHub Actions for
  Go", "add lint to the pipeline", "CI is slow", "coverage gate", "build
  matrix", "write a Makefile", "run govulncheck in CI".
  Not for: commit conventions (git-commit), choosing or auditing
  dependencies (go-dependency-audit), writing the tests themselves
  (go-test-quality).
user-invocable: true
license: MIT
compatibility: Designed for Claude Code or similar AI coding agents working on Go projects. Requires the Go toolchain. Targets GitHub Actions.
allowed-tools: Read Edit Write Glob Grep Bash(go:*) Bash(gofmt:*) Bash(golangci-lint:*) Bash(git:*)
metadata:
  author: eduardo-sl
  version: "1.2.0"
---

# Go CI

A Go pipeline has exactly four gates: build, vet/lint, test with race
detector, vulnerability scan. Everything else is optimization.

Detailed reference material, loaded on demand:

- `references/security-and-automation.md` — CodeQL and gosec SARIF,
  Dependabot config, SHA pinning, repository hardening, Trivy, an AI
  review workflow.

Read a reference file only when the summary below is not enough.

## 1. Baseline GitHub Actions Workflow

```yaml
name: ci
on:
  push:
    branches: [main]
  pull_request:

permissions:
  contents: read

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-go@v7
        with:
          go-version-file: go.mod   # single source of truth
          cache: true               # caches module + build cache
      - run: go build ./...
      - run: go vet ./...
      - run: go test -race -shuffle=on -coverprofile=coverage.out ./...

  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-go@v7
        with:
          go-version-file: go.mod
      - uses: golangci/golangci-lint-action@v9  # v7+ runs golangci-lint v2
        with:
          version: v2.6                         # pin a minor; v2.6+ has `modernize`

  vuln:
    runs-on: ubuntu-latest
    steps:
      - uses: golang/govulncheck-action@v1
        with:
          go-version-file: go.mod
```

Action major versions move several times a year. Treat the ones above as
a snapshot, and let Dependabot's `github-actions` ecosystem keep them
current rather than editing them by hand.

Key decisions baked in:

- `go-version-file: go.mod` — never hardcode the Go version in two places.
- `cache: true` on setup-go handles module and build caches; do not add
  manual `actions/cache` steps for Go on top of it.
- `-race -shuffle=on` — races and order-dependent tests fail in CI, not
  production.
- `permissions: contents: read` — least privilege by default.
- Lint in a separate job — it fails fast and parallelizes with tests.

## 2. golangci-lint Configuration

Commit a `.golangci.yml`; an unconfigured linter is noise:

```yaml
version: "2"            # required: golangci-lint v2 rejects v1 files

linters:
  default: standard     # errcheck, govet, ineffassign, staticcheck, unused
  enable:
    - errorlint         # %w misuse, == on errors
    - gosec             # security patterns
    - revive            # style, replaces golint
    - misspell
  exclusions:
    rules:
      - path: _test\.go
        linters: [gosec]  # test code may use weak randomness etc.
```

golangci-lint v2 moved exclusions from `issues.exclude-rules` to
`linters.exclusions.rules` and made the `version` key mandatory. A v1 file
fails to load, and `golangci-lint migrate` converts one in place.

Start from this small set and add linters deliberately. Enabling
everything produces hundreds of findings nobody triages. `nolint`
directives require a reason: `//nolint:gosec // G404: jitter, not crypto`.

## 3. Build Matrix — Only When You Ship It

```yaml
strategy:
  matrix:
    go: [oldstable, stable]      # the two releases the Go team supports
    os: [ubuntu-latest, macos-latest, windows-latest]
```

Libraries: test the two supported Go releases. setup-go resolves
`stable`/`oldstable` at run time, so the matrix never goes stale.
Services deployed on Linux: skip the OS matrix — it doubles cost for
platforms you never ship. Cross-compilation is cheaper than emulation:
`GOOS=windows go build ./...` catches most portability breaks.

## 4. Coverage Gate

```yaml
- run: go test -race -coverprofile=coverage.out ./...
- name: enforce coverage floor
  run: |
    total=$(go tool cover -func=coverage.out | awk '/^total:/ {sub(/%/,"",$3); print $3}')
    echo "coverage: ${total}%"
    awk -v t="$total" 'BEGIN { exit (t < 70.0) }'
```

Gate on a floor that ratchets up, not a target that gets gamed. Exclude
generated code via `//go:generate`d files' build tags or grep filters,
not by lowering the floor.

## 5. Makefile — Local Mirror of CI

CI must run what developers run. One definition, two callers:

```makefile
.PHONY: build lint test vuln ci

build:
	go build ./...

lint:
	golangci-lint run

test:
	go test -race -shuffle=on -coverprofile=coverage.out ./...

vuln:
	go tool govulncheck ./...   # pinned via `go get -tool` (Go 1.24+)

ci: build lint test vuln
```

If CI does anything `make ci` doesn't, developers discover failures
only after pushing. Keep them identical.

## 6. Speed Rules

- Split lint / test / vuln into parallel jobs (as in §1).
- `go test ./...` already parallelizes across packages; don't shard a
  small repo.
- Integration tests behind a build tag run in a separate job or on a
  schedule, not on every push: `go test -tags=integration ./...`.
- If the build cache misses constantly, check that `go.sum` is the
  cache key input (setup-go does this) and that jobs don't mutate it.

## 7. Security Gates

Beyond `govulncheck`: CodeQL (`security-extended`) and gosec as SARIF
uploads to the Security tab, and Trivy on any container image you build.
Start gosec with `-no-fail` to collect a baseline, then make new findings
fail the PR.

## 8. Dependency Updates and Action Pinning

- Dependabot for both `gomod` and `github-actions`, weekly, with minor and
  patch updates grouped into one PR. Majors stay separate — they need a
  changelog read.
- Pin third-party actions by commit SHA with the version in a comment; a
  tag can be moved to malicious code, and Dependabot updates SHA pins.

## 9. Workflow and Repository Hardening

- Per-job permissions on top of a read-only default.
- No `pull_request_target` workflow that checks out and runs fork code
  with secrets available.
- Branch protection: required checks, a review, no force pushes.
- An AI reviewer loaded with the go-code-review skill is an extra reviewer,
  never a check that can approve on its own.

Snippets for sections 7-9: `references/security-and-automation.md`.

## Verification Checklist

1. Pipeline has all four gates: build, vet+lint, test -race, govulncheck
2. Go version sourced from go.mod (`go-version-file`), not duplicated
3. `permissions: contents: read` set at workflow level
4. Tests run with `-race -shuffle=on`
5. `.golangci.yml` committed with a curated linter set
6. Every `nolint` carries a linter name and a reason
7. Matrix limited to versions/platforms actually supported
8. Coverage floor enforced, generated code excluded
9. `make ci` reproduces the pipeline locally, byte-for-byte
10. Integration tests isolated behind tags, not slowing every push
11. CodeQL/gosec results uploaded as SARIF; images scanned before push
12. Dependabot covers modules and actions; third-party actions pinned by SHA
13. Per-job permissions; no fork code run with secrets
