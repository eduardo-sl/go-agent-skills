# Go Agent Skills

This repository contains curated AI agent skills for Go development.
Skills follow the Agent Skills specification (SKILL.md with YAML frontmatter).

## Installation

```bash
npx skills add eduardo-sl/go-agent-skills -a copilot
```

Or manually: copy `skills/*/*/` into `.github/skills/`.

## Skills Catalog

### Code Quality
- **go-coding-standards** — Style conventions, naming, imports
- **go-code-review** — Structured review with BLOCKER/WARNING/SUGGESTION severity
- **go-error-handling** — Error wrapping, sentinel errors, custom types
- **go-context** — Context propagation, cancellation, timeouts, values
- **go-modernize** — Generics, slog, errors.Join, slices/maps, iterators
- **go-data-structures** — Slices, maps, sets, aliasing, preallocation
- **go-documentation** — Godoc conventions, examples, deprecation

### Architecture & Design
- **go-architecture-review** — Package layout, dependency direction, layering
- **go-project-layout** — Scaffolding new projects, cmd/internal, thin main
- **go-interface-design** — Consumer-side interfaces, composition, compliance checks
- **go-api-design** — REST/gRPC handlers, middleware, graceful shutdown
- **go-grpc** — Proto design, status codes, interceptors, streaming
- **go-design-patterns** — Functional options, factory, strategy, decorator
- **go-dependency-injection** — Constructor injection, composition root, wire/fx
- **go-cli** — Flags, subcommands, exit codes, signals, Cobra

### Data
- **go-database** — Connection pools, transactions, sqlc, migrations

### Safety & Performance
- **go-concurrency-review** — Goroutine lifecycle, channels, mutexes, race detection
- **go-security-audit** — OWASP, SQL injection, auth, secrets management
- **go-performance-review** — Allocations, benchmarking, pprof
- **go-observability** — Structured logging, tracing, metrics, OpenTelemetry
- **go-troubleshooting** — Panics, deadlocks, leaks, pprof diffing, delve

### Testing
- **go-test-quality** — Subtests, httptest, golden files, fuzz, testcontainers
- **go-test-table-driven** — Table-driven test patterns, struct design

### Workflow
- **go-dependency-audit** — govulncheck, go.mod hygiene, dep evaluation
- **go-ci** — GitHub Actions, golangci-lint, coverage gates, Makefile
- **go-refactoring** — Behavior-preserving changes, extract package, migrations
- **go-semantic-tools** — gopls navigation, go list graphs, semantic rename
- **git-commit** — Conventional Commits, atomic commits

All skills are in `skills/(category)/skill-name/SKILL.md`.
