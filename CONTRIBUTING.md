# Contributing to go-agent-skills

Thanks for considering a contribution. These skills get loaded into AI agents
used by real engineers on real codebases, so quality matters more than quantity.

## Before You Start

1. **Check if the skill already exists.** Read the README catalog.
2. **Check if it belongs here.** This repo is for Go-specific skills. Language-agnostic
   skills (git workflows, general architecture) are only included when they have
   Go-specific content.
3. **Read `SKILL_GUIDELINES.md`** in this directory. It defines the format, quality
   bar, and conventions.

## Creating a New Skill

### 1. Pick the right category

| Category | For |
|---|---|
| `(code-quality)` | Style, review, error handling, idiomatic patterns |
| `(architecture)` | Package layout, interfaces, API design, modules |
| `(safety)` | Concurrency, security, performance |
| `(testing)` | Test patterns, mocking, coverage, benchmarks |
| `(workflow)` | Git, dependencies, CI/CD, automation |

If none fit, propose a new category in your PR description.

### 2. Create the skill directory

```bash
mkdir -p skills/(category)/your-skill-name
```

Naming rules:
- Lowercase only, hyphens for separators
- Prefix with `go-` for Go-specific skills
- Name must be 1-64 characters
- Must match the `name` field in SKILL.md frontmatter

### 3. Write the SKILL.md

Start from this template:

```markdown
---
name: your-skill-name
description: >
  What this skill does in one sentence.
  Use when: "trigger phrase 1", "trigger phrase 2", "trigger phrase 3".
  Do NOT use for: X (use other-skill instead).
---

# Skill Title

Brief intro — what problem this solves and why it matters.

## 1. First Topic

### Rule or pattern

[code example with ✅/❌ contrast]

## 2. Second Topic

...

## Verification Checklist

- [ ] Check 1
- [ ] Check 2
```

### 4. Validate

```bash
./scripts/validate.sh
```

### 5. Update the README and the other discovery files

Add your skill to the appropriate table in `README.md`, and to every other
platform discovery file listed in `AGENTS.md`. All of them must agree.

### 6. Add evaluation cases

```bash
# evals/cases/<your-skill>.json — see evals/README.md for the format
scripts/run-evals.py --skill <your-skill> --dry-run
```

At least one case must fail without the skill installed. A case the base
model already passes proves nothing about the skill.

### 7. Open a PR

Use a conventional commit message:

```
feat(skill): add go-grpc-patterns skill
```

## Modifying Existing Skills

- Fix factual errors without hesitation.
- For style/opinion changes, explain the reasoning in the PR.
- If adding content pushes past 250 lines, move detail to `references/`.
- Run `./scripts/validate.sh` before pushing.

## Quality Bar

A skill is ready to merge when:

1. `./scripts/validate.sh` passes with zero errors
2. `evals/cases/<skill>.json` exists and at least one case fails without the skill
3. Every code example compiles (mentally or actually)
4. ✅/❌ examples show contrast, not just the right way
5. Description has trigger phrases AND negative triggers
6. The skill teaches something an agent wouldn't know from training data alone
7. Another Go engineer would agree with the guidance (no hot takes without justification)

## What We Don't Accept

- Skills that duplicate stdlib documentation without adding judgment or patterns
- Skills with brand-specific advice (e.g., "use this specific SaaS product")
- Skills that require external services or API keys to function
- Generated/padded content — every line should earn its place
- Skills over 250 lines that could offload detail to references/

## Code of Conduct

Be constructive. Disagree with reasoning, not with people.
