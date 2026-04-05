# Guidance for AI Coding Agents

You are working on **go-agent-skills**, a repository of curated AI agent skills
for Go development. These skills follow the Agent Skills standard format.

## Project Context

This is NOT a Go application. It is a collection of Markdown instruction files
(SKILL.md) that teach AI coding agents how to write idiomatic Go. The repo has
no Go source code, no go.mod, and no build artifacts.

## Repository Structure

```
skills/(category-name)/skill-name/SKILL.md
```

- Categories use parentheses: `(code-quality)`, `(architecture)`, etc.
- Each category has a `_category.json` with metadata.
- Each skill is a directory containing at minimum a `SKILL.md`.
- Skills may also contain `references/` for supplementary docs.

## When modifying skills

1. **Read `docs/SKILL_GUIDELINES.md` first.** It defines the quality standards.
2. **Keep SKILL.md under 500 lines.** Move detailed content to `references/`.
3. **YAML frontmatter is mandatory.** Every SKILL.md must have `name` and `description`.
4. **Name must match directory name.** `go-code-review/SKILL.md` → `name: go-code-review`.
5. **Description must include trigger phrases AND negative triggers.** Example:
   ```
   Use when: "review this code", "check this PR"
   Do NOT use for: security audits (use go-security-audit)
   ```
6. **Run validation before committing:**
   ```bash
   ./scripts/validate.sh
   ```

## When creating new skills

1. Choose the correct category directory or create a new one.
2. Create `skill-name/SKILL.md` with proper frontmatter.
3. Add the skill to the README.md catalog table.
4. If creating a new category, add `_category.json`.
5. Run `./scripts/validate.sh` to verify format.

## Code style for this repo

- Markdown: ATX-style headers (`#`), fenced code blocks with language tags.
- Shell scripts: `set -euo pipefail`, shellcheck-clean.
- JSON: 2-space indentation.
- No trailing whitespace. Final newline on all files.

## Commit conventions

Follow Conventional Commits:

```
feat(skill): add go-grpc-patterns skill
fix(go-error-handling): correct errors.Join example for Go 1.20+
docs(readme): add installation instructions for Windsurf
chore(ci): add SKILL.md line count validation
```

## Distribution

This repo is distributed via the [`npx skills`](https://github.com/vercel-labs/skills)
CLI. Users install with:

```bash
npx skills add eduardo-sl/go-agent-skills
```

The CLI discovers skills by recursively searching `skills/` for SKILL.md files.

### Platform discovery files

Each agent has its own discovery mechanism. When adding or removing a skill,
update ALL of these:

| File | Platform | Purpose |
|---|---|---|
| `AGENTS.md` | Universal (Codex, Gemini CLI, Factory) | Agent instructions for this repo |
| `CLAUDE.md` | Claude Code | Session context with skill list |
| `.claude-plugin/marketplace.json` | Claude Code marketplace | Plugin manifest with skill paths |
| `.cursor/rules/go-skills.mdc` | Cursor | Project rules with skill discovery |
| `.windsurf/rules/go-skills.md` | Windsurf | Cascade rules |
| `.clinerules` | Cline / Roo Code | Project rules |
| `.github/copilot-instructions.md` | GitHub Copilot | Custom instructions |
| `.opencode/config.json` | OpenCode | Config manifest |

The skill list in all files MUST match. If a file lists a skill that doesn't
exist (or omits one that does), users on that platform get confused.

## Language

- **All files in this repository must be written in English.** This includes
  SKILL.md files, documentation, commit messages, comments, and any other
  text content. No exceptions.

## Important constraints

- Skills must be **agent-agnostic**. No Claude-specific, Cursor-specific, or
  Copilot-specific instructions inside SKILL.md files. Skills work everywhere.
- Skills must be **self-contained**. No skill should reference or depend on
  another skill being loaded. Each skill stands alone.
- **Do not add Go source code to this repo.** Code examples belong inside
  SKILL.md files as fenced blocks, not as separate .go files.
- **Do not add package managers, build tools, or frameworks.** This repo is
  distributed by copy/symlink. Keep it simple.
