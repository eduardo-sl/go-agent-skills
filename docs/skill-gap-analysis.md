# Skill Gap Analysis

Tracks coverage of the Go AI skills ecosystem: what this repository
already provides, and which candidate skills remain unimplemented.

> Reference: the authoritative skill list lives in `CLAUDE.md` and the
> README catalog. `go-skills-router` is the in-repo routing index.

---

## Current Coverage Map (33 skills)

| Category | Skills |
|---|---|
| Code Quality | go-coding-standards, go-code-review, go-error-handling, go-context, go-modernize, go-data-structures, go-documentation |
| Architecture | go-architecture-review, go-project-layout, go-interface-design, go-api-design, go-openapi, go-graphql, go-grpc, go-design-patterns, go-dependency-injection, go-cli |
| Data | go-database |
| Safety & Performance | go-concurrency-review, go-security-audit, go-defensive-coding, go-performance-review, go-observability, go-troubleshooting |
| Testing | go-test-quality, go-test-table-driven |
| Workflow | go-dependency-audit, go-ci, go-refactoring, go-semantic-tools, go-binary-size, go-skills-router, git-commit |

## Implemented Candidates

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
| go-project-layout | `(architecture)/go-project-layout` |
| go-refactoring | `(workflow)/go-refactoring` |
| go-semantic-tools | `(workflow)/go-semantic-tools` |
| go-defensive-coding | `(safety)/go-defensive-coding` — nil traps, aliasing, overflow, resource lifecycle |
| go-openapi | `(architecture)/go-openapi` — codegen-tool opinion settled on oapi-codegen |
| go-graphql | `(architecture)/go-graphql` — gqlgen, dataloaders, query bounding |
| go-binary-size | `(workflow)/go-binary-size` — build-output size, not runtime performance |
| go-skills-router | `(workflow)/go-skills-router` — task-to-skill routing and overlap boundaries |
| go-linter | Absorbed into `go-ci` (curated .golangci.yml section) |
| go-safety | Delivered as `go-defensive-coding`, with the threat-facing half in go-security-audit |

## Ecosystem Comparison

Surveyed August 2026 against the published Go skill repositories.

**Covered here and not elsewhere:** structured review with severity levels
(`go-code-review`), architecture review as a distinct pass, table-driven
testing as its own deep dive, `go-openapi` with a settled codegen opinion,
`go-binary-size`, and Conventional Commits (`git-commit`).

**Deliberately not adopted from other repositories:**

| Pattern seen elsewhere | Why not |
|---|---|
| One skill per third-party library (cobra, viper, testify, wire, dig, fx, vendor-specific helper libraries) | Goes stale with each library release, and the guidance is already in the library's own docs. The concept skills (`go-cli`, `go-dependency-injection`, `go-test-quality`) name the options and stop there. |
| `popular-libraries` catalogue | High maintenance, stale within a quarter, and it encodes taste as fact. |
| `stay-updated` link list | A bookmark file, not a skill. Nothing for an agent to apply. |
| Separate `lint` skill | Absorbed into `go-ci`, where the config is actually enforced. |
| Separate `benchmark` skill | Absorbed into `go-performance-review`; splitting measurement from optimisation forces the agent to load both every time. |
| A pkg.go.dev query CLI skill | Would require installing a third-party binary to answer questions `go list -m -versions` and `govulncheck` already answer. |

## Remaining Candidates

### Low Priority / Situational

#### 1. `go-library-evaluation`
- **Scope:** evaluating third-party libraries (maintenance signals, API stability, pkg.go.dev metrics)
- **Why not yet:** substantially covered by `go-dependency-audit`'s dep evaluation section

#### 2. `go-build-release`
- **Scope:** goreleaser, reproducible builds, signing, SBOM, provenance
- **Why not yet:** partially covered by `go-ci` and `go-binary-size`; the
  supply-chain half (SLSA, cosign, SBOM) is the part that would justify it

#### 3. `go-wasm`
- **Scope:** GOOS=js/wasip1 targets, TinyGo trade-offs, host bindings
- **Why not yet:** niche; revisit on demand

## Structural Improvements Shipped Alongside

- Progressive disclosure: the largest skills split into lean SKILL.md +
  `references/*.md` loaded on demand.
- Operating modes + large-codebase parallel audit strategy in the
  review/audit skills.
- Executable verification sections (vet, golangci-lint, govulncheck,
  gosec, gopls modernize) in the core skills.
- Full frontmatter on every skill — `user-invocable`, `compatibility`,
  least-privilege `allowed-tools`, `metadata.author`, semver
  `metadata.version` — enforced by `scripts/validate.sh`.
- CI actually runs: the validation workflow moved from `scripts/` into
  `.github/workflows/`.
- `SECURITY.md` with the threat model contributions are reviewed against.
- `evals/` harness so a skill's value is a number, not an assertion.
