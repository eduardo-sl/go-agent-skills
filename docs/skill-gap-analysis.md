# Skill Gap Analysis

Skills we **don't have yet** that would be valuable additions to this repository, identified through research of the Go AI skills ecosystem.

> Reference: existing skills are listed in `CLAUDE.md`.

---

## Current Coverage Map

| Our Skill | Coverage Area | Notes |
|---|---|---|
| `go-coding-standards` | Code style, naming, imports | Covers style and naming conventions |
| `go-code-review` | Structured code review | Unique to our repo |
| `go-error-handling` | Error wrapping, sentinels, custom types | Well covered |
| `go-architecture-review` | Package layout, dependency direction | Focuses on review, not layout guidance |
| `go-interface-design` | Consumer-side interfaces, composition | Focuses on interfaces; doesn't cover structs deeply |
| `go-api-design` | REST/gRPC handlers, middleware | Broad scope (REST + gRPC) |
| `go-concurrency-review` | Goroutines, channels, mutexes | Well covered |
| `go-security-audit` | OWASP, SQL injection, auth | Well covered |
| `go-performance-review` | Allocations, benchmarks, pprof | Well covered |
| `go-test-quality` | Subtests, httptest, golden files, fuzz | Well covered |
| `go-test-table-driven` | Table-driven test patterns | Unique to our repo |
| `go-dependency-audit` | govulncheck, go.mod hygiene | Well covered |
| `git-commit` | Conventional Commits | Unique to our repo |

---

## Candidate Skills for Implementation

### High Priority

These skills cover important areas where we have **zero coverage** today.

#### 1. `go-observability`
- **Scope:** Structured logging (slog), distributed tracing (OpenTelemetry), metrics, health checks
- **Why:** Observability is essential for production services and we have no skill in this area

#### 2. `go-database`
- **Scope:** Patterns for database/sql, connection pooling, migrations, query builders, ORMs (sqlc, GORM, ent), transactions, prepared statements
- **Why:** Database access is ubiquitous in Go services and a constant source of bugs and performance issues

#### 3. `go-design-patterns`
- **Scope:** Idiomatic Go patterns — functional options, builder, factory, strategy, middleware chain, pub/sub
- **Why:** Design patterns in Go differ significantly from other languages; Go-specific guidance adds high value

#### 4. `go-context`
- **Scope:** Correct usage of `context.Context` — propagation, cancellation, timeouts, values, anti-patterns
- **Why:** Context is one of the most misunderstood areas in Go and causes subtle production bugs

#### 5. `go-modernize`
- **Scope:** Updating code to use modern Go features — generics, structured logging (slog), iterators, range-over-func, errors.Join
- **Why:** High impact skill; helps teams adopt new language features correctly and avoid legacy patterns

### Medium Priority

Useful areas where we already have partial coverage or that are more situational.

#### 6. `go-data-structures`
- **Scope:** Slices, maps, sync.Map, generics collections, when to use each structure, common pitfalls (nil slice vs empty slice, map iteration order)
- **Why:** Complements `go-coding-standards` with specific focus on data structure selection and usage

#### 7. `go-documentation`
- **Scope:** Godoc conventions, testable examples, package docs, CHANGELOG, API docs
- **Why:** Go documentation has specific conventions that AI agents frequently get wrong

#### 8. `go-troubleshooting`
- **Scope:** Debugging with delve, deadlock diagnosis, memory leaks, pprof analysis, race detector, stack trace analysis
- **Why:** Complements `go-performance-review` with focus on investigation and problem resolution

#### 9. `go-ci`
- **Scope:** GitHub Actions for Go, Makefile patterns, linting pipeline (golangci-lint), test coverage, build matrix, caching
- **Why:** CI is critical for Go projects but our repo doesn't cover pipeline automation at all

#### 10. `go-dependency-injection`
- **Scope:** Constructor injection, wire, uber/fx, uber/dig, when to use DI vs. global state
- **Why:** Essential pattern for testability and maintainability in larger codebases

### Low Priority

More niche skills or ones that can be absorbed by existing skills.

#### 11. `go-cli`
- **Scope:** Cobra/Viper patterns, flags, subcommands, stdin/stdout, exit codes, signal handling
- **Why:** Useful but specific to CLI projects

#### 12. `go-linter`
- **Scope:** golangci-lint configuration, custom linters, nolint directives, CI integration
- **Why:** Could be partially absorbed by `go-ci` or `go-coding-standards`

#### 13. `go-safety`
- **Scope:** Nil pointer prevention, goroutine leaks, resource cleanup (defer), unsafe package, CGO safety
- **Why:** High impact but overlaps with `go-concurrency-review` and `go-security-audit`

#### 14. `go-grpc`
- **Scope:** Protobuf, gRPC interceptors, streaming, health checks, reflection, error codes
- **Why:** Our `go-api-design` already covers gRPC partially; this would be a deep dive

#### 15. `go-popular-libraries`
- **Scope:** Recommended libraries by category (HTTP, testing, logging, etc.)
- **Why:** Useful as a reference but changes frequently

---

## Summary

| Priority | Count | Skills |
|---|---|---|
| High | 5 | observability, database, design-patterns, context, modernize |
| Medium | 5 | data-structures, documentation, troubleshooting, ci, dependency-injection |
| Low | 5 | cli, linter, safety, grpc, popular-libraries |

**Total: 15 candidate skills for implementation**

High priority skills should be implemented first as they cover significant gaps in our repository with proven high impact.
