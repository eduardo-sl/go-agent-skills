# Go Agent Skills

This repository contains curated AI agent skills for Go development, 
grounded in Effective Go, Go Code Review Comments, and real-world patterns from large-scale Go services.

## Installation

```bash
npx skills add eduardo-sl/go-agent-skills -a windsurf
```

Or manually: copy `skills/*/*/` into `.windsurf/skills/`.

## Skills

Code Quality: go-coding-standards, go-code-review, go-error-handling, go-context, go-modernize, go-data-structures, go-documentation
Architecture: go-architecture-review, go-project-layout, go-interface-design, go-api-design, go-grpc, go-design-patterns, go-dependency-injection, go-cli
Data: go-database
Safety: go-concurrency-review, go-security-audit, go-performance-review, go-observability, go-troubleshooting, go-defensive-coding
Testing: go-test-quality, go-test-table-driven
Workflow: go-dependency-audit, go-ci, go-refactoring, go-semantic-tools, git-commit

Each skill is a SKILL.md with YAML frontmatter (name + description) and markdown instructions.
