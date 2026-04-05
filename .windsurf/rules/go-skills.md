# Go Agent Skills

This repository contains curated AI agent skills for Go development, 
grounded in Effective Go, Go Code Review Comments, and real-world patterns from large-scale Go services.

## Installation

```bash
npx skills add eduardo-sl/go-agent-skills -a windsurf
```

Or manually: copy `skills/*/*/` into `.windsurf/skills/`.

## Skills

Code Quality: go-coding-standards, go-code-review, go-error-handling, go-context, go-modernize
Architecture: go-architecture-review, go-interface-design, go-api-design, go-database, go-design-patterns
Safety: go-concurrency-review, go-security-audit, go-performance-review, go-observability
Testing: go-test-quality, go-test-table-driven
Workflow: go-dependency-audit, git-commit

Each skill is a SKILL.md with YAML frontmatter (name + description) and markdown instructions.
