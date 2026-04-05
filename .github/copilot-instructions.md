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

### Architecture & Design
- **go-architecture-review** — Package layout, dependency direction, layering
- **go-interface-design** — Consumer-side interfaces, composition, compliance checks
- **go-api-design** — REST/gRPC handlers, middleware, graceful shutdown
- **go-database** — Connection pools, transactions, sqlc, migrations
- **go-design-patterns** — Functional options, factory, strategy, decorator

### Safety & Performance
- **go-concurrency-review** — Goroutine lifecycle, channels, mutexes, race detection
- **go-security-audit** — OWASP, SQL injection, auth, secrets management
- **go-performance-review** — Allocations, benchmarking, pprof
- **go-observability** — Structured logging, tracing, metrics, OpenTelemetry

### Testing
- **go-test-quality** — Subtests, httptest, golden files, fuzz, testcontainers
- **go-test-table-driven** — Table-driven test patterns, struct design

### Workflow
- **go-dependency-audit** — govulncheck, go.mod hygiene, dep evaluation
- **git-commit** — Conventional Commits, atomic commits

All skills are in `skills/(category)/skill-name/SKILL.md`.
