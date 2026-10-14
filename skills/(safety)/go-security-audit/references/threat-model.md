# Threat Modeling and Reporting

How to decide what is a vulnerability, how severe it is, and how to write
it up. The SKILL.md "Research Before Reporting" section states the rules.

## Find the trust boundaries

Untrusted data enters a Go service at a handful of places. List them
before reading any code:

- HTTP and gRPC handlers (bodies, headers, query strings, path values)
- Message consumers (Kafka, SQS, NATS payloads) and webhooks
- Files: uploads, archives, config read from writable locations
- Environment variables and flags in multi-tenant or CI contexts
- Rows written by *another* service or tenant
- Responses from third-party APIs

## STRIDE per boundary

| Threat | Question | Go-specific checks |
|---|---|---|
| **S**poofing | Can a caller pretend to be someone else? | JWT signature, `alg`, `aud`, `iss`, `exp`; mTLS peer verification; trusted-proxy headers |
| **T**ampering | Can a caller change data they should not? | Ownership checks per row; parameterized SQL; signed cookies; `os.Root` for paths |
| **R**epudiation | Can an action be denied later? | Audit log for auth and admin actions, with user ID and request ID |
| **I**nformation disclosure | Can a caller read what they should not? | `err.Error()` in responses, pprof on a public port, PII in logs, verbose 500s |
| **D**enial of service | Can a caller exhaust a resource? | `MaxBytesReader`, `ReadHeaderTimeout`, rate limits, bounded goroutines, decompression limits |
| **E**levation of privilege | Can a caller gain rights? | Role checks in middleware *and* handler, mass assignment into `role`/`is_admin` fields |

## Severity

Use the repository's three levels, defined for security work as:

| Level | Meaning |
|---|---|
| 🔴 BLOCKER | Exploitable today by someone who controls the input: injection, auth bypass, secret exposure, unbounded resource use on an unauthenticated path |
| 🟡 WARNING | A missing defence that needs a second failure to exploit, or exploitation that requires an authenticated, privileged caller |
| 🟢 SUGGESTION | Hardening: headers, tighter timeouts, defence in depth |

Upstream protection lowers severity; it does not delete the finding. A
string-built query reachable only through a strict integer parser is a
WARNING, not a BLOCKER — and still worth fixing, because the parser can
change.

## Finding template

```text
🔴 BLOCKER — SQL injection in order search
internal/orders/store.go:118
Path: GET /orders?sort=… → handler.List → store.Search → fmt.Sprintf into ORDER BY
Exploit: sort=id;DROP TABLE orders-- runs as the service's DB user
Fix: allowlist sort columns (map[string]string), never interpolate the value
```

When a reviewed sink is safe because of an upstream guarantee, leave a
one-line comment at the sink naming that guarantee
(`// safe: id parsed by strconv.ParseInt in handler.List`), so the next
audit does not have to rediscover it.
