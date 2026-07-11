---
name: go-design-patterns
description: >
  Idiomatic Go design patterns: functional options, builder, factory, strategy,
  middleware chain, pub/sub, and other patterns adapted for Go's type system.
  Use when: "design pattern", "functional options", "builder pattern",
  "factory pattern", "strategy pattern", "middleware chain", "option pattern",
  "how to structure this".
  Do NOT use for: interface design principles (use go-interface-design),
  package layout (use go-architecture-review), or
  concurrency patterns (use go-concurrency-review).
license: MIT
metadata:
  version: "1.1.0"
---

# Go Design Patterns

Go favors composition over inheritance and simplicity over abstraction.
These patterns are idiomatic Go — not Java patterns ported to Go.

Detailed reference material, loaded on demand:

- `references/creation-patterns.md` — functional options (full example),
  options vs config struct, constructors, factory.
- `references/behavioral-patterns.md` — strategy, middleware/decorator,
  result type, defer cleanup, sentinel vs zero values.

Read a reference file only when the summary below is not enough.

## Pattern Selection

| Need | Pattern | Reference |
|---|---|---|
| Constructor with many optional settings | Functional options | creation-patterns.md |
| Config loaded from file/env, mostly required fields | Config struct | creation-patterns.md |
| Enforce invariants at creation | Constructor returning error | creation-patterns.md |
| Pick implementation from runtime config | Factory returning interface | creation-patterns.md |
| Swap simple behavior at runtime | Strategy via function type | behavioral-patterns.md |
| Swap complex behavior at runtime | Strategy via interface | behavioral-patterns.md |
| Wrap cross-cutting concerns (log, cache, metrics) | Middleware / decorator | behavioral-patterns.md |
| Value-or-error in concurrent pipelines | `Result[T]` struct | behavioral-patterns.md |

## 1. Functional Options (essentials)

```go
type Option func(*Server)

func WithAddr(addr string) Option {
    return func(s *Server) { s.addr = addr }
}

func NewServer(opts ...Option) *Server {
    s := &Server{
        addr:        ":8080", // sensible defaults first
        readTimeout: 5 * time.Second,
        logger:      slog.Default(),
    }
    for _, opt := range opts {
        opt(s)
    }
    return s
}

srv := NewServer(WithAddr(":9090"))
```

Use when: many optional parameters with sensible defaults, API evolves over
time (new options don't break callers), options need validation.
Use a plain config struct instead when most fields are required or the
configuration is deserialized from file/env.

## 2. Constructor Rules

- Every exported type with invariants needs a constructor.
- Validate required dependencies; return an error, don't panic:

```go
// ✅ Good — constructor enforces invariants
func NewUserService(repo UserRepository, logger *slog.Logger) (*UserService, error) {
    if repo == nil {
        return nil, errors.New("user service: nil repository")
    }
    return &UserService{repo: repo, logger: logger}, nil
}

// ❌ Bad — struct literal with no validation
svc := &UserService{} // nil dependencies → panic at runtime
```

## 3. Factory

Return the interface, not a concrete type. The factory is the only place
that knows about concrete implementations:

```go
func NewStore(cfg Config) (Store, error) {
    switch cfg.StoreType {
    case "redis":
        return newRedisStore(cfg.RedisAddr)
    case "memory":
        return newMemoryStore(), nil
    default:
        return nil, fmt.Errorf("unknown store type: %s", cfg.StoreType)
    }
}
```

## 4. Middleware Chain

The standard HTTP composition pattern:

```go
type Middleware func(http.Handler) http.Handler

func Chain(handler http.Handler, middlewares ...Middleware) http.Handler {
    for i := len(middlewares) - 1; i >= 0; i-- {
        handler = middlewares[i](handler)
    }
    return handler
}

handler := Chain(appHandler, Recoverer, RequestID, Logger, Auth)
```

The same shape works for any interface: stack decorators as
`cache → logging → metrics → actual repo`
(see `references/behavioral-patterns.md`).

## 5. Zero Values First

Prefer types whose zero value is useful (`sync.Mutex`, `bytes.Buffer`,
nil slices). Reach for sentinel wrappers or pointers only when the zero
value is ambiguous as an input (`nil *float64` = "not configured").

## Anti-Patterns to Avoid

```go
// ❌ God interface — too many methods
type Service interface {
    GetUser(ctx context.Context, id string) (*User, error)
    CreateUser(ctx context.Context, u *User) error
    DeleteUser(ctx context.Context, id string) error
    ListOrders(ctx context.Context, userID string) ([]Order, error)
    // 20 more methods...
}
// → Split into focused interfaces: UserReader, UserWriter, OrderLister

// ❌ Premature abstraction — interface for one implementation
type UserCache interface {
    Get(key string) (*User, bool)
    Set(key string, user *User)
}
// If there's only ever one implementation, use the concrete type.
// Extract an interface when a second consumer or implementation appears.

// ❌ Java-style inheritance simulation
type BaseService struct{ /* ... */ }
type UserService struct{ BaseService } // embedding is NOT inheritance
// → Use composition: UserService has a dependency, not a parent.
```

## Verification Checklist

1. Functional options used for types with optional configuration
2. Constructors validate required dependencies and return errors
3. Factory functions return interfaces, not concrete types
4. No god interfaces — each interface has 1-3 methods
5. Middleware follows `func(http.Handler) http.Handler` signature
6. Decorators wrap interfaces, not concrete types
7. `defer` used for all resource cleanup (files, connections, locks)
8. Zero values are meaningful — no unnecessary initialization
9. No premature abstractions — interfaces extracted only when needed
10. Composition used instead of embedding for code reuse
