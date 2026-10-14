# Project-Level Documentation

Templates for the SKILL.md "Project-Level Documentation" section.

## README — library

```markdown
# retry

Retries with exponential backoff and jitter for Go. Context-aware, zero dependencies.

[![Go Reference](https://pkg.go.dev/badge/example.com/retry.svg)](https://pkg.go.dev/example.com/retry)

## Install

    go get example.com/retry

Requires Go 1.24+.

## Usage

    err := retry.Do(ctx, fetch, retry.MaxAttempts(5))

## Compatibility

Follows semantic versioning. Exported API is stable within v1.
```

Lead with what it does and the minimal working example; link to
pkg.go.dev for the API instead of duplicating it.

## README — service or CLI

```markdown
# payments-api

Accepts card payments and settles them nightly with the acquirer.

## Run locally

    make dev      # starts dependencies in Docker and the service on :8080

## Configuration

| Variable | Default | Meaning |
|---|---|---|
| `PAYMENTS_ADDR` | `:8080` | Listen address |
| `PAYMENTS_DB_URL` | — | PostgreSQL DSN (required) |

## Operations

Health: `GET /healthz`, `GET /readyz`. Metrics: `:9090/metrics`.
Runbooks: `docs/runbooks/`.
```

Generate the configuration table from the config struct where you can, so
it cannot drift from the code.

## CHANGELOG (Keep a Changelog)

```markdown
# Changelog

## [Unreleased]

## [1.4.0] - 2026-09-30
### Added
- `retry.OnRetry` hook for logging attempts.
### Deprecated
- `retry.Backoff`; use `retry.Exponential`. Removal in v2.
### Fixed
- Jitter could exceed `MaxDelay` by one interval.
```

Entries describe changes for the user of the module, not the commits.
Group them as Added, Changed, Deprecated, Removed, Fixed, Security.

## llms.txt

A short Markdown index at the repository or documentation root that
helps AI assistants find the right pages:

```markdown
# retry

> Retries with exponential backoff and jitter for Go.

## Docs
- [API reference](https://pkg.go.dev/example.com/retry): every exported symbol
- [Examples](https://pkg.go.dev/example.com/retry#pkg-examples): runnable usage

## Optional
- [Design notes](docs/design.md): why backoff is capped
```

## CONTRIBUTING

State how to run the tests and linters (`make ci`), the commit convention,
how to propose a change to exported API, and how to report a security
issue privately (`SECURITY.md`).
