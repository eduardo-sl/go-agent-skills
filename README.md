# go-agent-skills

Curated AI agent skills for Go projects. Install with one command, works everywhere.

```bash
npx skills add eduardo-sl/go-agent-skills
```

Supports **Claude Code**, **Cursor**, **Codex**, **GitHub Copilot**, **Windsurf**, **OpenCode**, and [37+ more agents](https://github.com/vercel-labs/skills#available-agents). Compatible with the open [Agent Skills](https://agentskills.io/) ecosystem and [`npx skills`](https://skills.sh) CLI.

Built on the [Uber Go Style Guide](https://github.com/uber-go/guide), [Effective Go](https://go.dev/doc/effective_go), and hard-won production experience with large-scale Go services.

---

## Why

AI coding agents are as good as the context you give them. Without Go-specific guidance, they'll write Java-flavored Go, ignore idiomatic error handling, create goroutine leaks, and use `interface{}` where generics belong.

These skills teach your agent how to write Go the way experienced Go engineers do — with proper error wrapping, consumer-side interfaces, table-driven tests, and all the idioms that make Go code maintainable at scale.

## Skills Catalog

Skills load automatically based on context. You can also invoke them directly via slash command (e.g., `/go-code-review`).

### Code Quality

| Skill | What it does | Triggers |
|---|---|---|
| [go-coding-standards](skills/(code-quality)/go-coding-standards/) | Style conventions, naming, imports, struct init, formatting | "check Go style", "fix formatting" |
| [go-code-review](skills/(code-quality)/go-code-review/) | Structured review process with severity classification | "review this code", "check this PR" |
| [go-error-handling](skills/(code-quality)/go-error-handling/) | Error wrapping, sentinels, custom types, `errors.Is`/`As` | "handle errors", "error wrapping" |
| [go-context](skills/(code-quality)/go-context/) | Context propagation, cancellation, timeouts, values | "context usage", "timeout", "context cancellation" |
| [go-modernize](skills/(code-quality)/go-modernize/) | Generics, slog, errors.Join, slices/maps, range-over-func | "modernize", "use generics", "update Go" |

### Architecture & Design

| Skill | What it does | Triggers |
|---|---|---|
| [go-architecture-review](skills/(architecture)/go-architecture-review/) | Package layout, dependency direction, layering, `internal/` | "review architecture", "project layout" |
| [go-interface-design](skills/(architecture)/go-interface-design/) | Consumer-side interfaces, composition, compliance checks | "design interface", "accept interfaces" |
| [go-api-design](skills/(architecture)/go-api-design/) | REST/gRPC handlers, middleware, graceful shutdown, pagination | "design API", "HTTP handler" |
| [go-database](skills/(architecture)/go-database/) | Connection pools, transactions, sqlc, migrations, repository pattern | "database access", "SQL query", "transactions" |
| [go-design-patterns](skills/(architecture)/go-design-patterns/) | Functional options, factory, strategy, middleware/decorator | "design pattern", "functional options" |

### Safety & Performance

| Skill | What it does | Triggers |
|---|---|---|
| [go-concurrency-review](skills/(safety)/go-concurrency-review/) | Goroutine lifecycle, channels, mutexes, race detection | "check thread safety", "goroutine leak" |
| [go-security-audit](skills/(safety)/go-security-audit/) | OWASP, SQL injection, auth, secrets, input validation | "security review", "check vulnerabilities" |
| [go-performance-review](skills/(safety)/go-performance-review/) | Allocations, benchmarking, pprof, hot path optimization | "check performance", "reduce allocations" |
| [go-observability](skills/(safety)/go-observability/) | Structured logging (slog), tracing, metrics, OpenTelemetry | "add logging", "tracing", "metrics" |

### Testing

| Skill | What it does | Triggers |
|---|---|---|
| [go-test-quality](skills/(testing)/go-test-quality/) | Test philosophy, subtests, httptest, golden files, fuzz, testcontainers | "add tests", "improve coverage" |
| [go-test-table-driven](skills/(testing)/go-test-table-driven/) | Deep dive on table-driven tests: when to use, struct design, refactoring | "table-driven test", "test matrix" |

### Workflow

| Skill | What it does | Triggers |
|---|---|---|
| [go-dependency-audit](skills/(workflow)/go-dependency-audit/) | Module hygiene, `govulncheck`, dep evaluation, go.mod review | "check dependencies", "audit deps" |
| [git-commit](skills/(workflow)/git-commit/) | Conventional Commits, atomic commits, pre-commit verification | "commit changes", "commit message" |

## Quick Start

### Install via npx (recommended)

```bash
# Install all skills (interactive — picks your agents)
npx skills add eduardo-sl/go-agent-skills

# List available skills before installing
npx skills add eduardo-sl/go-agent-skills --list

# Install specific skills
npx skills add eduardo-sl/go-agent-skills --skill go-code-review --skill go-concurrency-review

# Install to specific agents
npx skills add eduardo-sl/go-agent-skills -a claude-code -a cursor

# Install globally (all projects)
npx skills add eduardo-sl/go-agent-skills -g

# Non-interactive (CI/CD friendly)
npx skills add eduardo-sl/go-agent-skills --all -y
```

See [`npx skills` docs](https://github.com/vercel-labs/skills) for all options.

### Install via script

```bash
git clone https://github.com/eduardo-sl//go-agent-skills.git
./go-agent-skills/scripts/install.sh /path/to/your-go-project
```

### Manual install

```bash
# Claude Code
mkdir -p .claude/skills
cp -r go-agent-skills/skills/*/* .claude/skills/

# Cursor
mkdir -p .cursor/skills
cp -r go-agent-skills/skills/*/* .cursor/skills/

# GitHub Copilot
mkdir -p .github/skills
cp -r go-agent-skills/skills/*/* .github/skills/

# Codex (OpenAI)
mkdir -p .agents/skills
cp -r go-agent-skills/skills/*/* .agents/skills/
```

### Manage installed skills

```bash
# Check for updates
npx skills check

# Update all skills
npx skills update

# List installed skills
npx skills list

# Remove a skill
npx skills remove go-performance-review
```

## Repository Structure

```
go-agent-skills/
├── skills/                            # All skill definitions
│   ├── (code-quality)/                # go-coding-standards, go-code-review, go-error-handling, go-context, go-modernize
│   ├── (architecture)/                # go-architecture-review, go-interface-design, go-api-design, go-database, go-design-patterns
│   ├── (safety)/                      # go-concurrency-review, go-security-audit, go-performance-review, go-observability
│   ├── (testing)/                     # go-test-quality, go-test-table-driven
│   └── (workflow)/                    # go-dependency-audit, git-commit
│
├── # Platform discovery files (how each agent finds skills in this repo)
├── AGENTS.md                          # Universal: Codex, Gemini CLI, Copilot, Factory
├── CLAUDE.md                          # Claude Code
├── .claude-plugin/marketplace.json    # Claude Code plugin marketplace
├── .cursor/rules/go-skills.mdc       # Cursor
├── .windsurf/rules/go-skills.md      # Windsurf
├── .clinerules                        # Cline / Roo Code
├── .github/copilot-instructions.md   # GitHub Copilot
├── .opencode/config.json             # OpenCode
│
├── scripts/
│   ├── install.sh                     # Shell-based installer (alternative to npx)
│   └── validate.sh                    # CI: validate SKILL.md format
├── docs/
│   ├── CONTRIBUTING.md
│   └── SKILL_GUIDELINES.md
├── .github/workflows/validate.yml     # CI pipeline
├── README.md
└── LICENSE
```

## Design Principles

**Each skill is self-contained.** No cross-references or imports between skills. The agent loads only what's relevant, consuming minimal tokens.

**Instructions are for agents, not humans.** Step-by-step, imperative, with concrete ✅/❌ code examples. Agents learn better from contrast than from prose.

**Negative triggers prevent false activation.** Each skill explicitly states what it does NOT cover, pointing to the correct skill instead.

**Verification checklists close every skill.** The agent self-validates its output before presenting results.

**Under 500 lines per SKILL.md.** Detailed reference material goes in `references/` subdirectories, loaded on demand.

## Customization

These skills encode opinionated defaults. To adapt for your team:

1. Fork the repo
2. Edit the SKILL.md files to match your conventions
3. Add project-specific patterns to the code examples
4. Install from your fork: `npx skills add your-org/go-agent-skills`

Common customizations: linter config (golangci-lint rules), import ordering (with internal packages), preferred libraries (zap vs slog, chi vs stdlib), test frameworks (testify vs stdlib).

## Sources & Acknowledgments

These skills stand on the shoulders of:

- [Uber Go Style Guide](https://github.com/uber-go/guide/blob/master/style.md) — the foundation for most coding conventions
- [Effective Go](https://go.dev/doc/effective_go) — official Go team guidance
- [Go Code Review Comments](https://go.dev/wiki/CodeReviewComments) — community review standards
- [Tech Leads Club Agent Skills](https://github.com/tech-leads-club/agent-skills) — quality standards and format conventions
- [Anthropic Skills](https://github.com/anthropics/skills) — patterns for production-grade skills
- [Vercel Skills CLI](https://github.com/vercel-labs/skills) — the `npx skills` distribution ecosystem

## Contributing

See [CONTRIBUTING.md](docs/CONTRIBUTING.md) for guidelines on creating new skills, the review process, and quality standards.

## License

[MIT](LICENSE)
