---
name: go-dependency-audit
description: >
  Audit Go module dependencies: detect outdated packages, check for known
  vulnerabilities, review go.mod hygiene, identify unused or redundant deps,
  and evaluate dependency quality. Use when auditing dependencies, checking
  for CVEs, cleaning up go.mod, upgrading modules, or evaluating third-party
  packages. Trigger examples: "check dependencies", "audit deps", "go.mod
  review", "update modules", "vulnerability scan", "govulncheck".
  Not for: code-level security (go-security-audit), architecture review
  (go-architecture-review).
user-invocable: true
license: MIT
compatibility: Designed for Claude Code or similar AI coding agents working on Go projects. Requires the Go toolchain. Requires network access to proxy.golang.org. Read-only: this skill reports findings, it does not edit code.
allowed-tools: Read Glob Grep Bash(go:*) Bash(gofmt:*) Bash(govulncheck:*)
metadata:
  author: eduardo-sl
  version: "1.2.0"
---

# Go Dependency Audit

Every dependency you add is code you don't control but are responsible for.
Audit ruthlessly.

Detailed reference material, loaded on demand:

- `references/resolution-and-workspaces.md` — minimal version selection,
  `replace`/`exclude`/`retract`, `go.work`, tool dependencies.

Read a reference file only when the summary below is not enough.

## 1. Vulnerability Scanning

### govulncheck (official Go tool):

```bash
# Ad hoc, without touching go.mod
go run golang.org/x/vuln/cmd/govulncheck@latest ./...

# Pinned as a module tool (Go 1.24+) — recommend this to the project so
# every developer and CI job runs the same version
go get -tool golang.org/x/vuln/cmd/govulncheck
go tool govulncheck ./...

# Scan a built binary
go tool govulncheck -mode=binary ./bin/api-server
```

`govulncheck` checks against the Go vulnerability database and reports
only vulnerabilities that actually affect your code paths — not just
transitive deps you never call.

Run this in CI. No exceptions.

### Additional scanning:

```bash
# Nancy (Sonatype OSS Index)
go list -json -deps ./... | nancy sleuth

# Trivy (container + deps)
trivy fs --scanners vuln .
```

## 2. go.mod Hygiene

### Check for unused dependencies:

```bash
go mod tidy
git diff go.mod go.sum  # any changes = deps were stale
```

`go mod tidy` MUST be run before every commit. Add to CI:

```bash
go mod tidy
git diff --exit-code go.mod go.sum
```

### No replace directives in committed code

A committed `replace => ../local-path` breaks every other checkout; local
multi-module work belongs in `go.work`. The one exception — a temporary
fork with a linked issue — is in section 8.

### Verify checksums:

```bash
go mod verify
```

This confirms that downloaded modules match their expected checksums.
Failures indicate supply-chain tampering.

## 3. Dependency Evaluation Criteria

Before adding any dependency, evaluate:

| Criterion | Check |
|---|---|
| **Maintenance** | Last commit < 6 months? Active issue responses? |
| **Popularity** | Stars/forks alone mean nothing. Usage in production projects matters. |
| **License** | Compatible with your project? MIT/Apache/BSD preferred. |
| **Size** | Does it pull in 50 transitive deps for one function? |
| **Alternatives** | Can you do this with stdlib in < 50 lines? |
| **API stability** | Is it v1+? Does it follow semver? Frequent breaking changes? |
| **Test coverage** | Does the project have meaningful tests? |

### The stdlib question:

Go's standard library is excellent. Before adding a dependency, ask:
"Can I solve this with `net/http`, `encoding/json`, `database/sql`,
`text/template`, `crypto/*`, `os/exec`, etc.?"

If the answer is yes and the code is < 100 lines, write it yourself.

## 4. Module Version Audit

### List all dependencies with versions:

```bash
go list -m all
```

### Check for available updates:

```bash
go list -m -u all  # shows available updates
```

### Upgrade strategy:

```bash
# Update one module to its latest minor/patch
go get github.com/foo/bar@latest

# Patch releases only, for every dependency of the packages
go get -u=patch ./...

# Latest minor/patch of every dependency (add -t to include test deps)
go get -u ./...
```

`go get -u` never crosses a major version: `github.com/foo/bar/v2` is a
different module path. A major upgrade means changing the import paths
and reading the changelog — it is a migration, not an update.

ALWAYS run full test suite after updates:

```bash
go get github.com/foo/bar@v1.5.0
go mod tidy
go test -race ./...
```

## 5. Transitive Dependency Analysis

```bash
# Why is this module in my dependency tree?
go mod why github.com/some/transitive-dep

# Full dependency graph
go mod graph

# Visual dependency graph (with modgraphviz)
go mod graph | modgraphviz | dot -Tpng -o deps.png
```

Watch for:
- 🔴 Transitive deps with known CVEs
- 🔴 Abandoned transitive deps (no commits in 2+ years)
- 🟡 A dependency forcing a higher minimum version of a shared module on
  everyone (minimal version selection picks the highest requirement)
- 🟡 Two major versions of one library (`v1` and `v2`) linked side by side
- 🟡 Oversized transitive trees (a logging library pulling in gRPC)

## 6. Go Version Management

```go
// go.mod
module github.com/myorg/myproject

go 1.22  // minimum Go version required
```

Rules:
- Set `go` directive to the minimum version that supports features you use.
- `toolchain` directive (Go 1.21+) pins the exact toolchain version.
- Test against multiple Go versions in CI (at minimum: current and previous).

## 7. Adding a Dependency

Ask before adding one: a new module is code the team must audit, update
and trust indefinitely, and the agent should not make that decision
silently. When proposing one:

- Name the standard-library alternative and why it is not enough — since
  Go 1.21-1.27, `slog`, `slices`/`maps`, `errors.Join`, ServeMux routing,
  `os.Root` and `uuid` each removed a common reason to add a dependency.
- Report what the evaluation criteria above found: maintenance, license,
  transitive size (`go mod graph` after a trial `go get`), API stability.
- Avoid frameworks that take over `main`, ORMs that hide the SQL, and code
  generators nobody on the team understands.

## 8. Resolving Version Problems

- Minimal version selection builds with the highest *minimum* any module
  requires — adding one dependency can raise another's version.
- Application fixes: `replace` (temporary fork, with an issue link) and
  `exclude` (a known-broken version). Both apply only in the main module.
- Library fixes: `retract` versions you published by mistake; it is the
  only signal that reaches consumers.
- Local multi-module work uses `go.work`, not committed
  `replace => ../path` directives.
- Developer tools are `go.mod` tool dependencies (`go get -tool`, Go
  1.24+), not a `tools.go` file.

Examples: `references/resolution-and-workspaces.md`.

## Audit Output Format

```text
## Dependency Audit Report

**Module:** github.com/myorg/myproject
**Go version:** 1.22
**Direct deps:** N | **Indirect deps:** M

### 🔴 Vulnerabilities
- CVE-XXXX-YYYY in github.com/foo/bar@v1.2.3 — upgrade to v1.2.5

### 🟡 Outdated Dependencies
- github.com/foo/bar v1.2.3 → v1.5.0 available (minor)

### 🟢 Observations
- go.mod is clean, no replace directives
- All deps actively maintained
```
