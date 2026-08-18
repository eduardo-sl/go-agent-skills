---
name: go-architecture-review
description: >
  Review Go project architecture: package structure, dependency direction,
  layering, separation of concerns, domain modeling, and module boundaries.
  Use when reviewing architecture, designing package layout, evaluating
  dependency graphs, or refactoring monoliths into modules. Trigger
  examples: "review architecture", "package structure", "project layout",
  "dependency direction", "clean architecture Go", "module boundaries".
  Not for: code-level style (go-coding-standards), endpoint design
  (go-api-design).
user-invocable: true
license: MIT
compatibility: Designed for Claude Code or similar AI coding agents working on Go projects. Requires the Go toolchain. Read-only: this skill reports findings, it does not edit code.
allowed-tools: Read Glob Grep Bash(go:*) Bash(gofmt:*)
metadata:
  author: eduardo-sl
  version: "1.2.1"
---

# Go Architecture Review

Good architecture makes the next change easy. Bad architecture makes every change scary.

## Operating Modes

Pick the mode that matches the request before starting:

- **Layout review** (default) — assess an existing codebase against the
  sections below and report violations with severity.
- **Refactor plan** — same assessment, but the deliverable is an ordered
  migration plan (smallest safe steps first), not just findings.
- **New service consultation** — asked "how should I structure X":
  apply sections 1-3 as prescriptive guidance instead of review checks.

## Auditing Large Codebases

For repositories with many packages, build the dependency picture before
judging it:

1. Map the module: `go list ./...` for packages, then import statements
   to trace dependency direction.
2. Run independent passes: (a) layout vs section 1, (b) dependency
   direction vs section 2, (c) wiring and config vs sections 3+5,
   (d) package design vs section 4.
3. If your environment supports delegating work to parallel sub-agents
   or tasks, assign each pass to one; synthesize at the end — dependency
   findings often explain layout findings.
4. Cite package paths and `file.go:line` in every finding.

## 1. Standard Project Layout

```text
myproject/
├── cmd/                    # Main applications (one dir per binary)
│   ├── api-server/
│   │   └── main.go
│   └── worker/
│       └── main.go
├── internal/               # Private packages — cannot be imported externally
│   ├── domain/             # Core business types (entities, value objects)
│   │   ├── user.go
│   │   └── order.go
│   ├── service/            # Business logic (use cases)
│   │   ├── user.go
│   │   └── order.go
│   ├── store/              # Data access (repositories)
│   │   ├── postgres/
│   │   │   └── user.go
│   │   └── redis/
│   │       └── cache.go
│   ├── handler/            # HTTP/gRPC handlers (adapters)
│   │   └── user.go
│   └── config/             # Configuration loading
│       └── config.go
├── pkg/                    # Public packages (use sparingly)
│   └── httputil/
│       └── response.go
├── migrations/             # Database migrations
├── api/                    # API definitions (OpenAPI, proto files)
├── go.mod
├── go.sum
└── Makefile
```

### Key Rules:
- `internal/` enforces encapsulation at the compiler level. Use it aggressively.
- `pkg/` is for genuinely reusable packages. When in doubt, use `internal/`.
- `cmd/` main packages should be thin — wire dependencies and call `Run()`.
- One `main.go` per binary, minimal logic inside.

## 2. Dependency Direction

Dependencies MUST flow inward. Domain core has zero external dependencies:

```text
handlers → services → domain ← stores
    ↓          ↓                  ↓
  (net/http)  (pure Go)     (database/sql)
```

Rules:
- `domain/` imports NOTHING from the project. No `store`, no `handler`, no `config`.
- `service/` depends on `domain/` types and interfaces, NOT on concrete stores.
- `handler/` depends on `service/` interfaces.
- `store/` implements interfaces defined in `service/` or `domain/`.
- Circular dependencies are a 🔴 BLOCKER. The compiler catches them, but design should prevent them.

```go
// ✅ Good — service defines the interface it needs
// internal/service/user.go
type UserStore interface {
    GetByID(ctx context.Context, id string) (*domain.User, error)
    Create(ctx context.Context, user *domain.User) error
}

type UserService struct {
    store UserStore // depends on interface, not postgres.Store
}

// internal/store/postgres/user.go
type Store struct { db *sql.DB }

// Implements service.UserStore without importing the service package
func (s *Store) GetByID(ctx context.Context, id string) (*domain.User, error) { ... }
```

## 3. Main Package Wiring

`main.go` is the composition root. Wire everything here:

```go
func main() {
    cfg := config.Load()
    logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))

    db, err := sql.Open("postgres", cfg.DatabaseURL)
    if err != nil {
        logger.Error("connect db", slog.Any("error", err))
        os.Exit(1)
    }
    defer db.Close()

    // Wire dependencies
    userStore := postgres.NewUserStore(db)
    userService := service.NewUserService(userStore)
    userHandler := handler.NewUserHandler(userService, logger)

    // Setup router
    r := chi.NewRouter()
    r.Mount("/api/v1/users", userHandler.Routes())

    // Run server
    srv := &http.Server{Addr: cfg.Addr, Handler: r}
    // ... graceful shutdown
}
```

Avoid dependency injection frameworks. Go's explicit wiring is a feature.
If wiring gets complex, use Google's `wire` for compile-time DI code generation.

## 4. Package Design Principles

### One package = one purpose

```go
// ✅ Good — clear purpose
package orderservice  // business rules for orders
package postgres      // PostgreSQL data access
package httphandler   // HTTP transport layer

// ❌ Bad — grab-bag packages
package utils    // what ISN'T a util?
package common   // everything and nothing
package models   // types without behavior
```

### Avoid package stuttering

```go
// ❌ Bad — package name repeated in type
package user
type UserService struct{} // user.UserService

// ✅ Good
package user
type Service struct{} // user.Service
```

### Package cohesion over size

A package with 20 related files is better than 20 packages with 1 file each.
Split packages when they have distinct responsibilities, not when they get big.

## 5. Configuration

```go
type Config struct {
    Addr        string        `env:"ADDR" envDefault:":8080"`
    DatabaseURL string        `env:"DATABASE_URL,required"`
    LogLevel    string        `env:"LOG_LEVEL" envDefault:"info"`
    Timeout     time.Duration `env:"TIMEOUT" envDefault:"30s"`
}
```

Rules:
- All config from environment variables (12-factor).
- Validate at startup, fail fast with clear messages.
- No config scattered across packages — centralize in `internal/config`.
- Never hardcode values. Not even "just for now."

## 6. Init Functions

Avoid `init()`. It runs implicitly, makes testing harder, and creates hidden dependencies.

```go
// ❌ Bad — hidden side effects
func init() {
    db, _ = sql.Open("postgres", os.Getenv("DB_URL"))
}

// ✅ Good — explicit initialization
func NewStore(dsn string) (*Store, error) {
    db, err := sql.Open("postgres", dsn)
    if err != nil {
        return nil, fmt.Errorf("open db: %w", err)
    }
    return &Store{db: db}, nil
}
```

Exception: registering drivers or codecs is acceptable in `init()`:
```go
func init() {
    sql.Register("custom", &CustomDriver{})
}
```

## Architecture Review Checklist

- 🔴 No circular dependencies between packages
- 🔴 Domain types have zero infrastructure dependencies
- 🔴 No business logic in `cmd/` main packages
- 🔴 No `init()` with side effects (DB connections, HTTP calls)
- 🟡 `internal/` used for project-private packages
- 🟡 Interfaces defined at the consumer, not the producer
- 🟡 Configuration centralized and validated at startup
- 🟡 Dependency direction flows inward (handlers → services → domain)
- 🟢 Package names are short, singular, descriptive
- 🟢 No `utils/`, `common/`, `helpers/` packages
- 🟢 Main package is a thin composition root
