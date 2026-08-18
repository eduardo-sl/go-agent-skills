---
name: go-security-audit
description: >
  Security review for Go applications: input validation, SQL injection,
  authentication/authorization, secrets management, TLS, OWASP Top 10, and
  secure coding patterns. Use when performing security reviews, checking for
  vulnerabilities, hardening Go services, or reviewing auth implementations.
  Trigger examples: "security review", "check vulnerabilities", "OWASP",
  "SQL injection", "input validation", "secrets management", "auth review".
  Not for: dependency CVEs (go-dependency-audit), concurrency safety
  (go-concurrency-review).
user-invocable: true
license: MIT
compatibility: Designed for Claude Code or similar AI coding agents working on Go projects. Requires the Go toolchain. govulncheck, gosec and gitleaks are optional. Read-only: this skill reports findings, it does not edit code.
allowed-tools: Read Glob Grep Bash(go:*) Bash(gofmt:*) Bash(govulncheck:*) Bash(gosec:*) Bash(gitleaks:*)
metadata:
  author: eduardo-sl
  version: "1.4.0"
---

# Go Security Audit

Security is not a feature — it's a property. Every line of code either
maintains it or degrades it.

## Operating Modes

Pick the mode that matches the request before starting:

- **Targeted check** — a single concern ("is this query injectable?",
  "review this auth middleware"). Apply only the relevant sections.
- **Diff audit** — audit the changed lines of a PR or working tree for
  every concern below.
- **Full audit** (default for "security review the service") — sweep the
  codebase using the parallel passes in "Auditing Large Codebases".

## Run the Scanners First

Before manual review, run the automated scanners and fold their output
into the findings (skip any that is not installed and note it):

```bash
govulncheck ./...       # known CVEs actually reachable from your code
gosec ./...             # static analysis for insecure patterns
go vet ./...            # includes some security-relevant checks
```

Scanners find the known patterns; the manual passes below find the
logic flaws they cannot.

## Auditing Large Codebases

Each numbered section below is an independent audit pass. For codebases
beyond ~20 files:

1. Locate the attack surface first: HTTP/gRPC handlers, CLI entry
   points, queue consumers, and anything parsing external input.
2. Run one pass per concern: (a) input validation + injection,
   (b) authentication/authorization, (c) secrets + crypto,
   (d) TLS + security headers + rate limiting, (e) logging hygiene.
3. If your environment supports delegating work to parallel sub-agents
   or tasks, assign each pass to one — the passes don't overlap.
   Otherwise run them sequentially.
4. Every finding must cite `file.go:line`, the vulnerable input path,
   and a concrete fix. Aggregate into one report sorted by severity.

Detailed reference material, loaded on demand:

- `references/injection.md` — boundary validation, sanitization,
  parameterized and dynamic queries.
- `references/auth-and-transport.md` — passwords, JWT, authorization
  middleware, secrets, TLS, headers, rate limiting.

Read a reference file only when the section below is not enough.

## 1. Input Validation

Validate at the boundary, before the value reaches any business code:

- Cap the request body with `http.MaxBytesReader` — an unbounded decoder is
  a memory exhaustion vector.
- Decode into a typed struct, then validate it. A decode that succeeds is not
  a value that is valid.
- Reject rather than repair. Reply with the status code, not with the
  internal error text.
- Sanitize anything rendered back as HTML (`bluemonday`), parse emails with
  `net/mail`, and reject URLs whose scheme is not `http`/`https`.

Examples in `references/injection.md`.

## 2. SQL Injection Prevention

ALWAYS pass values as query parameters. There is no safe amount of string
concatenation:

```go
// ✅ Good — parameterized
row := db.QueryRowContext(ctx, "SELECT id, name FROM users WHERE email = $1", email)

// ❌ CRITICAL — SQL injection
query := "SELECT * FROM users WHERE email = '" + email + "'"
query := fmt.Sprintf("SELECT * FROM users WHERE id = %s", id)
```

Dynamic filters are built by appending placeholders (`$1`, `$2`, …) and
collecting the values into an `args` slice — never by interpolating the value
itself. Table and column names cannot be parameterized: allowlist them
against a fixed set.

Examples in `references/injection.md`.

## 3. Authentication & Authorization

- Hash passwords with `bcrypt` (or argon2id). NEVER store plaintext, NEVER
  use MD5/SHA — they are fast, which is the wrong property here.
- Compare with `bcrypt.CompareHashAndPassword`, which is constant-time.
  Hand-rolled comparisons leak timing.
- Validate every JWT claim that matters: signature with the expected
  algorithm, `exp`, `iss`, `aud`. Reject `alg: none` and never hardcode the
  signing key.
- Authorize per request in middleware, reading the identity from the request
  context. An endpoint with no role check is a public endpoint.
- Check ownership, not only role: a valid token for user A must not read
  user B's row.

Examples in `references/auth-and-transport.md`.

## 4. Secrets Management

- 🔴 NEVER hardcode secrets, tokens, or API keys in source code
- 🔴 NEVER commit secrets to git (even in "test" files)
- 🔴 NEVER log secrets, tokens, or passwords

Read them from the environment or a secrets manager, keep `.env`, `*.pem`,
`*.key` and `credentials.json` in `.gitignore`, and run `gitleaks detect` in
CI so a leak fails the build instead of ageing in history.

Examples in `references/auth-and-transport.md`.

## 5. Transport, Headers and Rate Limiting

- Set `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, a
  `Content-Security-Policy`, and HSTS on every response.
- TLS: `MinVersion: tls.VersionTLS12` and an explicit cipher suite list.
  NEVER `InsecureSkipVerify: true` outside a test.
- Rate limit auth endpoints, public APIs, and anything expensive, keyed per
  client rather than globally.

Examples in `references/auth-and-transport.md`.

## 6. Logging Security

Log the identifier, never the credential:

```go
// ❌ CRITICAL
log.Printf("user login: email=%s password=%s", email, password)
log.Printf("request body: %v", req) // may contain secrets

// ✅ Good — redacted
logger.Info("auth completed", slog.String("user_id", userID))
```

Whole-struct logging is the common leak: a `%v` on a request struct prints
whatever field someone adds next sprint.

## Security Audit Checklist

### Critical (🔴 BLOCKER)
- No SQL injection vectors (all queries parameterized)
- No hardcoded secrets/keys/tokens
- No plaintext password storage
- No disabled TLS certificate verification
- Request body size limited
- JWT signature verified, `alg: none` rejected

### Important (🟡 WARNING)
- Input validation on all external data
- Rate limiting on auth and public endpoints
- Security headers set on all responses
- CORS configured restrictively
- Error messages don't leak internals
- Audit logging for auth events

### Recommended (🟢 SUGGESTION)
- `govulncheck` in CI pipeline
- `gitleaks` for secret scanning
- Structured logging with redaction
- Dependency pinning with verified checksums
