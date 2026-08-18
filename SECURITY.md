# Security Policy

## What this repository ships

This repository contains no executable application code. It ships Markdown
instruction files (`SKILL.md`) that are injected into an AI coding agent's
context, plus two shell scripts (`scripts/install.sh`, `scripts/validate.sh`).

The security-relevant consequence: a malicious or careless skill can steer an
agent that already holds file-write and shell access. Skill content is treated
as security-sensitive here, not as documentation.

## Threat model

Contributions are reviewed against these categories:

| Category | What is rejected |
|---|---|
| Prompt injection | Instructions that override the host agent, the user, or another skill; hidden text; text framed as a system message |
| Data exfiltration | Reading secrets, environment, or source and sending them anywhere off-host |
| Malicious execution | Piping remote content to a shell, destructive commands, privilege escalation |
| Tool/trust exploitation | Instructing the agent to bypass confirmation prompts, widen permissions, or disable safety checks |
| Obfuscation | Base64, encoded payloads, invisible or homoglyph characters, non-obvious indirection |
| Supply chain | Recommending unmaintained, typosquatted, or unpinned third-party modules and tools |

Code examples inside skills that demonstrate an **anti-pattern** are allowed and
expected, but they must be clearly marked (`// ❌`) and must not contain values
that resemble real credentials.

## Guarantees

- Every skill declares `allowed-tools` in its frontmatter. Review and audit
  skills do not request write access.
- No skill fetches remote content or executes code downloaded at runtime.
- The only external hosts referenced anywhere in `skills/` are `github.com`
  and `localhost`.
- `scripts/validate.sh` runs on every pull request via GitHub Actions.

## Reporting a vulnerability

Report privately through
[GitHub Security Advisories](https://github.com/eduardo-sl/go-agent-skills/security/advisories/new).
Do not open a public issue for a suspected injection or exfiltration vector.

Include the skill name, the file and line, and the agent behaviour you were able
to induce. Expect an acknowledgement within 7 days.

## Third-party audits

Published skills are scanned by the [skills.sh](https://www.skills.sh) registry
(Socket, Snyk, and Gen Agent Trust Hub). Results are linked from each skill's
page on the registry.
