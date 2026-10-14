---
name: go-api-design
description: >
  HTTP/REST API design for Go services: handlers, ServeMux routing,
  middleware, request validation, pagination, idempotency, health checks,
  error responses, and graceful shutdown. Use when designing APIs, writing
  HTTP handlers, implementing middleware, or structuring REST endpoints.
  Trigger examples: "design API", "REST endpoints", "HTTP handler",
  "middleware pattern", "graceful shutdown", "API versioning".
  Not for: gRPC services (go-grpc), spec-first OpenAPI work (go-openapi),
  general architecture (go-architecture-review), concurrency in handlers
  (go-concurrency-review).
user-invocable: true
license: MIT
compatibility: Designed for Claude Code or similar AI coding agents working on Go projects. Requires the Go toolchain.
allowed-tools: Read Edit Write Glob Grep Bash(go:*) Bash(gofmt:*)
metadata:
  author: eduardo-sl
  version: "2.0.1"
---

# Go API Design

APIs are contracts. Once published, they're promises. Design them as if
you'll maintain them for a decade — because you probably will.

> Community default. A project skill or agent-config rule that explicitly
> supersedes `go-api-design` takes precedence over this one.

Detailed reference material, loaded on demand:

- `references/handlers-and-middleware.md` — handler structs, JSON response
  helpers, request ID and recoverer middleware, decode-and-validate.

Read a reference file only when the summary below is not enough.

## 1. HTTP Handler Structure

- Route with the standard `http.ServeMux` (Go 1.22+): `"GET /users/{id}"`
  patterns match the method, `r.PathValue("id")` reads the wildcard, and a
  wrong method gets a 405 with `Allow`. A router dependency earns its place
  for middleware groups and sub-routers, not for path parameters.
- Handlers are methods on a struct that holds their dependencies (store,
  logger) — never package globals.
- Handler methods return nothing: they write the response and handle the
  error themselves, mapping domain errors (`errors.Is(err, ErrNotFound)`)
  to status codes and logging only the unexpected ones.
- Route through one JSON helper that sets `Content-Type`, writes the status
  once, and logs encode failures.

## 2. Middleware Pattern

Middleware is `func(http.Handler) http.Handler`. Order, outside → inside:

```text
Recoverer → RequestID → Logger → Auth → RateLimit → Handler
```

Recover MUST be outermost. Auth before business logic. Logger captures timing.

## 3. Request Validation

- Cap the body before decoding: `r.Body = http.MaxBytesReader(w, r.Body, 1<<20)`.
- Decode into a typed request struct, then validate it in the same step —
  a successful decode is not a valid value.
- Reply `400` with a stable message; never echo the decoder's error text.

## 4. URL and Naming Conventions

```text
GET    /api/v1/users          → list users
POST   /api/v1/users          → create user
GET    /api/v1/users/{id}     → get user
PUT    /api/v1/users/{id}     → replace user
PATCH  /api/v1/users/{id}     → partial update
DELETE /api/v1/users/{id}     → delete user

GET    /api/v1/users/{id}/orders → list user orders (nested resource)
```

Rules:
- Plural nouns for resources: `/users`, not `/user`
- Kebab-case for multi-word paths: `/order-items`
- One JSON field convention per API, never mixed — camelCase
  (`"createdAt"`) is the default here; match an existing API if one exists
- Version in URL path: `/api/v1/...`
- No verbs in URLs: `/users/search?q=alice`, NOT `/searchUsers`

## 5. Pagination

```go
type PageRequest struct {
    Cursor string `json:"cursor"`
    Limit  int    `json:"limit"`
}

type PageResponse[T any] struct {
    Items      []T    `json:"items"`
    NextCursor string `json:"nextCursor,omitempty"`
    HasMore    bool   `json:"hasMore"`
}
```

Prefer cursor-based pagination over offset/limit for large datasets.
Offset pagination breaks under concurrent writes.

## 6. Graceful Shutdown

```go
func main() {
    if err := run(context.Background()); err != nil {
        slog.Error("server stopped", slog.Any("error", err))
        os.Exit(1)
    }
}

func run(ctx context.Context) error {
    ctx, stop := signal.NotifyContext(ctx, os.Interrupt, syscall.SIGTERM)
    defer stop()

    srv := &http.Server{
        Addr:              ":8080",
        Handler:           router,
        ReadHeaderTimeout: 5 * time.Second, // Slowloris guard
        ReadTimeout:       10 * time.Second,
        WriteTimeout:      15 * time.Second,
        IdleTimeout:       120 * time.Second,
    }

    errc := make(chan error, 1)
    go func() { errc <- srv.ListenAndServe() }()

    select {
    case err := <-errc:
        return fmt.Errorf("listen: %w", err) // e.g. port already in use
    case <-ctx.Done():
    }

    // ctx is already cancelled; shutdown needs its own deadline.
    shutdownCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), 30*time.Second)
    defer cancel()
    if err := srv.Shutdown(shutdownCtx); err != nil {
        return fmt.Errorf("shutdown: %w", err)
    }
    if err := <-errc; !errors.Is(err, http.ErrServerClosed) {
        return err
    }
    return nil
}
```

- `ReadHeaderTimeout` is the Slowloris defence: without it a client can
  hold a connection open by trickling header bytes. `gosec` G112 flags a
  server that lacks it.
- Compare `http.ErrServerClosed` with `errors.Is`, never `==`.
- Exit only from `main`. A `log.Fatal` inside the serving goroutine skips
  every deferred cleanup, including the shutdown itself.

## 7. Health Check Endpoints

```go
// Liveness: is the process alive? GET /healthz → 200, no dependency checks
// Readiness: should it receive traffic? GET /readyz → 200 or 503
func (h *HealthHandler) handleReady(w http.ResponseWriter, r *http.Request) {
    if h.draining.Load() { // atomic.Bool, set when shutdown starts
        h.respondError(w, http.StatusServiceUnavailable, "shutting down")
        return
    }
    if err := h.db.PingContext(r.Context()); err != nil {
        h.respondError(w, http.StatusServiceUnavailable, "database unavailable")
        return
    }
    h.respondJSON(w, http.StatusOK, map[string]string{"status": "ready"})
}
```

On SIGTERM behind a load balancer: set `draining`, wait one readiness
period so the balancer stops routing, *then* call `srv.Shutdown`.
Shutting down first rejects requests the balancer is still sending. Keep
liveness free of dependency checks — a database outage should not make the
orchestrator restart every replica.

## 8. Error Response Format

Consistent error responses across the entire API:

```json
{
    "error": {
        "code": "VALIDATION_ERROR",
        "message": "invalid request parameters",
        "details": [
            {"field": "email", "message": "must be a valid email"}
        ]
    }
}
```

Map internal errors to HTTP status codes at the handler boundary.
Internal errors should NEVER leak to clients. For a standard shape, use
RFC 9457 problem details (`application/problem+json`) — the go-openapi
skill has the type.

## 9. Idempotency and Browser Clients

- `POST` endpoints that create or charge accept an `Idempotency-Key`
  header: store key → response for a bounded time, replay the stored
  response for a repeated key, and reject a concurrent duplicate with 409.
  Clients and proxies retry; without this, a retry is a double charge.
- APIs called from browsers with cookies need CSRF protection —
  `http.CrossOriginProtection` (Go 1.25+); the go-security-audit skill
  owns the details.
