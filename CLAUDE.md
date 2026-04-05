# Go Agent Skills

This repository contains curated AI agent skills for Go development, 
grounded in Effective Go, Go Code Review Comments, and real-world patterns from large-scale Go services.

## Available Skills

Install skills with: `npx skills add eduardo-sl/go-agent-skills`

Or use directly by invoking `/skill-name` in Claude Code.

### Code Quality
- `/go-coding-standards` — Style, naming, imports, struct init
- `/go-code-review` — Structured review with severity levels
- `/go-error-handling` — Wrapping, sentinels, custom types, errors.Is/As
- `/go-context` — Context propagation, cancellation, timeouts, values
- `/go-modernize` — Generics, slog, errors.Join, slices/maps, iterators

### Architecture
- `/go-architecture-review` — Package layout, dependency direction, layering
- `/go-interface-design` — Consumer-side interfaces, composition, compliance
- `/go-api-design` — REST/gRPC handlers, middleware, graceful shutdown
- `/go-design-patterns` — Functional options, factory, strategy, decorator

### Data
- `/go-database` — Connection pools, transactions, sqlc, migrations

### Safety & Performance
- `/go-concurrency-review` — Goroutines, channels, mutexes, race detection
- `/go-security-audit` — OWASP, SQL injection, auth, secrets
- `/go-performance-review` — Allocations, benchmarks, pprof
- `/go-observability` — Structured logging, tracing, metrics, OpenTelemetry

### Testing
- `/go-test-quality` — Subtests, httptest, golden files, fuzz, testcontainers
- `/go-test-table-driven` — Table-driven test patterns, struct design, refactoring

### Workflow
- `/go-dependency-audit` — govulncheck, go.mod hygiene, dep evaluation
- `/git-commit` — Conventional Commits, atomic commits
