---
name: go-observability
description: >
  Structured logging, distributed tracing, metrics, and health checks for Go
  services. Covers slog, OpenTelemetry, Prometheus, and observability best
  practices. Use when: "add logging", "structured logs", "add tracing",
  "OpenTelemetry", "add metrics", "Prometheus", "observability", "instrument
  this code".
  Not for: pprof profiling (go-performance-review), error handling
  (go-error-handling), health endpoints (go-api-design).
user-invocable: true
license: MIT
compatibility: Designed for Claude Code or similar AI coding agents working on Go projects. Requires the Go toolchain.
allowed-tools: Read Edit Write Glob Grep Bash(go:*) Bash(gofmt:*)
metadata:
  author: eduardo-sl
  version: "1.2.0"
---

# Go Observability

Observability is not optional for production services. Every service must produce
structured logs, expose metrics, and propagate trace context. Use the stdlib
`log/slog` for logging and OpenTelemetry for tracing and metrics.

Detailed reference material, loaded on demand:

- `references/slog.md` — handler setup, logger injection, child loggers.
- `references/tracing.md` — tracer provider, spans, propagation, shutdown.
- `references/metrics.md` — metric definitions, HTTP instrumentation.

Read a reference file only when the section below is not enough.

## 1. Structured Logging with slog

Use `log/slog` (Go 1.21+) with a JSON handler in production. Every line is
key-value pairs, never a formatted sentence:

```go
// ✅ Good — structured, leveled
logger.Info("user created", slog.String("user_id", user.ID), slog.Duration("latency", elapsed))

// ❌ Bad — unparseable in production
log.Printf("user %s created in %v", user.ID, elapsed)
```

Inject the logger as a dependency; never reach for a package-level global.
Derive child loggers with `logger.With(...)` so component, method and request
ID are attached once instead of at every call site. See `references/slog.md`.

### Log levels — use them consistently

| Level | Use for |
|---|---|
| `Debug` | Verbose diagnostic info, disabled in production |
| `Info` | Normal operations: request received, job completed |
| `Warn` | Recoverable issues: retry succeeded, deprecated usage |
| `Error` | Failures requiring attention: DB down, external call failed |

NEVER log at Error level for expected conditions (user not found → Info or Warn).

### Sensitive data — NEVER log

- Passwords, tokens, API keys
- Full credit card numbers, SSNs
- Raw request bodies containing PII

```go
// ✅ Good — redacted
logger.Info("auth attempt", slog.String("user", email), slog.Bool("success", ok))

// ❌ Bad — leaks credentials
logger.Info("auth attempt", slog.String("password", password))
```

## 2. Distributed Tracing with OpenTelemetry

Start a span for every operation worth seeing on a waterfall — inbound
requests, DB calls, outbound HTTP, meaningful business steps — and always
`defer span.End()`.

Rules the reference examples follow:

- Name the span after the operation (`GetUser`, `db.query`), never after the
  fully-qualified function, and never `doStuff`.
- On failure call `span.RecordError(err)` and `span.SetStatus(codes.Error, ...)`,
  or the trace shows a green span for a failed request.
- Pass `ctx` down the whole chain. A `context.Background()` mid-chain silently
  starts a new trace and breaks the parent link.

Setup and examples in `references/tracing.md`.

## 3. Metrics with OpenTelemetry / Prometheus

| Type | Use for | Example |
|---|---|---|
| Counter | Monotonically increasing values | Requests total, errors total |
| Gauge | Values that go up and down | Active connections, queue depth |
| Histogram | Distribution of values | Request latency, response size |

Naming is `<namespace>_<subsystem>_<name>_<unit>`:

```text
http_request_duration_seconds     ✅ (unit in name)
http_requests_total               ✅ (counter with _total suffix)
db_connections_active             ✅ (gauge, no suffix needed)
user_signups                      ❌ (missing _total for counter)
requestLatency                    ❌ (camelCase, no unit)
```

Keep cardinality bounded. Label with the route pattern, method and status —
never a user ID, request ID or raw `r.URL.Path`, each of which mints a new
time series per value and eventually takes the metrics backend down.

Definitions and middleware in `references/metrics.md`.

## 4. Connecting Logs, Traces, and Metrics

A log line without a trace ID cannot be joined to the request that produced
it. Pull `trace.SpanContextFromContext(ctx)` and attach `trace_id` and
`span_id` to the logger at the top of each handler or service method.

## 5. Graceful Shutdown of Telemetry

The batch span processor holds spans in memory. Call `tp.Shutdown(ctx)` with
its own timeout on the way out, or the last seconds before a crash — the
interesting ones — never reach the collector.

Both examples in `references/tracing.md`.

## Verification Checklist

1. All logging uses `log/slog` with structured key-value pairs, not `fmt.Printf` or `log.Printf`
2. Logger is injected as a dependency, not used as a global
3. No sensitive data (passwords, tokens, PII) in log output
4. Trace context is propagated through all function calls via `context.Context`
5. Spans are created for significant operations (DB calls, HTTP requests, business logic)
6. Spans record errors with `span.RecordError(err)` and set error status
7. Metrics follow naming conventions: `_seconds`, `_total`, `_bytes`
8. No high-cardinality labels (user IDs, request IDs) in metrics
9. Telemetry providers are shut down gracefully on service exit
10. Trace IDs are included in log entries for correlation
