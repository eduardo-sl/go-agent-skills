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
- `/go-data-structures` — Slices, maps, sets, aliasing, preallocation
- `/go-documentation` — Godoc conventions, examples, deprecation

### Architecture
- `/go-architecture-review` — Package layout, dependency direction, layering
- `/go-project-layout` — Scaffolding new projects, cmd/internal, thin main
- `/go-interface-design` — Consumer-side interfaces, composition, compliance
- `/go-api-design` — REST/gRPC handlers, middleware, graceful shutdown
- `/go-grpc` — Proto design, status codes, interceptors, streaming
- `/go-design-patterns` — Functional options, factory, strategy, decorator
- `/go-dependency-injection` — Constructor injection, composition root, wire/fx
- `/go-cli` — Flags, subcommands, exit codes, signals, Cobra

### Data
- `/go-database` — Connection pools, transactions, sqlc, migrations

### Safety & Performance
- `/go-concurrency-review` — Goroutines, channels, mutexes, race detection
- `/go-security-audit` — OWASP, SQL injection, auth, secrets
- `/go-performance-review` — Allocations, benchmarks, pprof
- `/go-observability` — Structured logging, tracing, metrics, OpenTelemetry
- `/go-troubleshooting` — Panics, deadlocks, leaks, pprof diffing, delve
- `/go-defensive-coding` — Nil traps, slice aliasing, integer overflow, defensive copying

### Testing
- `/go-test-quality` — Subtests, httptest, golden files, fuzz, testcontainers
- `/go-test-table-driven` — Table-driven test patterns, struct design, refactoring

### Workflow
- `/go-dependency-audit` — govulncheck, go.mod hygiene, dep evaluation
- `/go-ci` — GitHub Actions, golangci-lint, coverage gates, Makefile
- `/go-refactoring` — Behavior-preserving changes, extract package, migrations
- `/go-semantic-tools` — gopls navigation, go list graphs, semantic rename
- `/git-commit` — Conventional Commits, atomic commits
- `/go-binary-size` — Linker flags, CGO, build tags, dependency weight, image size
