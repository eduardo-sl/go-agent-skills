# Skill Gap Analysis

Tracks coverage of the Go AI skills ecosystem: what this repository
already provides, and which candidate skills remain unimplemented.

> Reference: the authoritative skill list lives in `CLAUDE.md` and the
> README catalog.

---

## Current Coverage Map (28 skills)

| Category | Skills |
|---|---|
| Code Quality | go-coding-standards, go-code-review, go-error-handling, go-context, go-modernize, go-data-structures, go-documentation |
| Architecture | go-architecture-review, go-project-layout, go-interface-design, go-api-design, go-grpc, go-design-patterns, go-dependency-injection, go-cli |
| Data | go-database |
| Safety & Performance | go-concurrency-review, go-security-audit, go-performance-review, go-observability, go-troubleshooting |
| Testing | go-test-quality, go-test-table-driven |
| Workflow | go-dependency-audit, go-ci, go-refactoring, go-semantic-tools, git-commit |

## Implemented Candidates

All previously identified high-priority candidates are done:

| Candidate | Delivered as |
|---|---|
| go-observability | `(safety)/go-observability` |
| go-database | `(data)/go-database` |
| go-design-patterns | `(architecture)/go-design-patterns` |
| go-context | `(code-quality)/go-context` |
| go-modernize | `(code-quality)/go-modernize` |
| go-data-structures | `(code-quality)/go-data-structures` |
| go-documentation | `(code-quality)/go-documentation` |
| go-troubleshooting | `(safety)/go-troubleshooting` |
| go-ci | `(workflow)/go-ci` |
| go-dependency-injection | `(architecture)/go-dependency-injection` |
| go-cli | `(architecture)/go-cli` |
| go-grpc | `(architecture)/go-grpc` |
| go-project-layout | `(architecture)/go-project-layout` (new candidate, scaffolding counterpart to architecture review) |
| go-refactoring | `(workflow)/go-refactoring` (new candidate, safe-change process) |
| go-semantic-tools | `(workflow)/go-semantic-tools` (new candidate, gopls/go list navigation) |
| go-linter | Absorbed into `go-ci` (curated .golangci.yml section) |
| go-safety | Absorbed into go-concurrency-review, go-security-audit, and go-troubleshooting |

## Remaining Candidates

### Low Priority / Situational

#### 1. `go-graphql`
- **Scope:** gqlgen patterns, resolvers, dataloaders, N+1 in GraphQL
- **Why not yet:** niche relative to REST/gRPC; revisit on demand

#### 2. `go-openapi`
- **Scope:** OpenAPI-first workflows, oapi-codegen, contract testing
- **Why not yet:** overlaps go-api-design; needs a codegen-tool opinion first

#### 3. `go-library-evaluation`
- **Scope:** evaluating third-party libraries (maintenance, API stability, pkg.go.dev signals)
- **Why not yet:** partially covered by go-dependency-audit's dep evaluation section

#### 4. `go-popular-libraries`
- **Scope:** recommended libraries by category
- **Why not yet:** high maintenance burden, goes stale quickly

## Structural Improvements Shipped Alongside

- Progressive disclosure: the five largest skills split into lean
  SKILL.md + `references/*.md` loaded on demand.
- Operating modes + large-codebase parallel audit strategy in the four
  review/audit skills.
- Executable verification sections (vet, golangci-lint, govulncheck,
  gosec, gopls modernize) in the core skills.
- Semver `metadata.version` + `license` in every skill frontmatter,
  enforced by `scripts/validate.sh`.
