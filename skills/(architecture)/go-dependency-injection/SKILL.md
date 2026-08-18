---
name: go-dependency-injection
description: >
  Dependency injection in Go: constructor injection, wiring in main, avoiding
  global state, and when frameworks (wire, fx, dig) earn their complexity.
  Use when: "dependency injection", "wire up dependencies", "inject this",
  "remove global state", "singleton in Go", "use google/wire", "uber fx",
  "make this testable".
  Do NOT use for: interface design principles (use go-interface-design),
  project directory structure (use go-project-layout), or
  test doubles and mocks (use go-test-quality).
user-invocable: true
license: MIT
compatibility: Designed for Claude Code or similar AI coding agents working on Go projects. Requires the Go toolchain. wire and fx are optional.
allowed-tools: Read Edit Write Glob Grep Bash(go:*) Bash(gofmt:*)
metadata:
  author: eduardo-sl
  version: "1.1.0"
---

# Go Dependency Injection

DI in Go is a pattern, not a framework: pass dependencies to
constructors, wire everything explicitly in `main`. Reach for a
framework only when manual wiring measurably hurts.

## 1. Constructor Injection — the Default

```go
// ✅ Good — dependencies are explicit parameters
type OrderService struct {
    repo     OrderRepository
    payments PaymentGateway
    logger   *slog.Logger
}

func NewOrderService(repo OrderRepository, payments PaymentGateway, logger *slog.Logger) *OrderService {
    return &OrderService{repo: repo, payments: payments, logger: logger}
}

// ❌ Bad — hidden dependencies reached through globals
func (s *OrderService) Place(ctx context.Context, o Order) error {
    db := database.Get()        // global singleton
    log.Printf("placing order") // global logger
    // untestable without touching process-wide state
}
```

Rules:

- Accept interfaces for dependencies the service calls; return the
  concrete type from the constructor.
- Every dependency visible in the signature — if the list feels long,
  the type does too much (split it), don't hide deps to shorten it.
- Validate required deps in the constructor and return an error
  (or accept a nil-safe default, e.g. `logger = slog.Default()`).

## 2. The Composition Root

All wiring lives in one place — `main` (or a `run` function it calls).
Construction order is the dependency order, checked by the compiler:

```go
func run(ctx context.Context, cfg Config) error {
    db, err := store.Open(ctx, cfg.DatabaseURL)
    if err != nil {
        return fmt.Errorf("open db: %w", err)
    }
    defer db.Close()

    orderRepo := store.NewOrderRepo(db)
    payments := stripe.NewGateway(cfg.StripeKey)
    logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))

    orders := service.NewOrderService(orderRepo, payments, logger)
    server := handler.NewServer(cfg.Addr, orders)

    return server.ListenAndServe(ctx)
}
```

- No package builds its own dependencies; it receives them.
- No `init()` wiring, no package-level `var DB *sql.DB`.
- Two binaries needing different wiring = two mains, same components.

## 3. Eliminating Global State

```go
// ❌ Before — package-level singleton
var defaultClient *api.Client

func Fetch(id string) (*Item, error) {
    return defaultClient.Get(id)
}

// ✅ After — the dependency moves into a struct
type Fetcher struct {
    client *api.Client
}

func NewFetcher(c *api.Client) *Fetcher { return &Fetcher{client: c} }

func (f *Fetcher) Fetch(id string) (*Item, error) {
    return f.client.Get(id)
}
```

Migration path for a legacy codebase: introduce the struct, keep a
deprecated package-level wrapper delegating to one instance built in
`main`, move callers over, delete the wrapper.

Acceptable package-level state: pure constants, compiled regexps,
`sync.Once`-guarded process singletons that hold no config.

## 4. Function Dependencies for Small Seams

A full interface is overkill for one function — inject the function:

```go
type Service struct {
    now     func() time.Time
    genID   func() string
    publish func(ctx context.Context, e Event) error
}

// Production: Service{now: time.Now, genID: uuid.NewString, publish: bus.Publish}
// Test:       Service{now: fixedTime, genID: constID, publish: capture}
```

## 5. When Frameworks Earn Their Complexity

Manual wiring scales further than expected — a 100-line `run` function
is still readable and compiler-checked. Consider a tool when wiring
crosses hundreds of components or many teams share one binary.

| Tool | Model | Trade-off |
|---|---|---|
| google/wire | Compile-time code generation | Wiring stays plain Go and compiler-checked; adds a codegen step |
| uber-go/fx | Runtime container + lifecycle | App lifecycle (start/stop hooks) managed; errors surface at runtime, magic in stack traces |
| uber-go/dig | Runtime container (fx's core) | Same runtime trade-offs, no lifecycle layer |

Decision rule: prefer manual wiring; if generation becomes necessary
prefer wire (failures at compile time beat failures at startup); adopt
fx only when you also want its lifecycle management and your team
accepts the runtime container.

Never mix models: one composition root, one mechanism.

## 6. Wire Example (when chosen)

```go
//go:build wireinject

func InitializeServer(cfg Config) (*handler.Server, error) {
    wire.Build(
        store.Open,
        store.NewOrderRepo,
        stripe.NewGateway,
        service.NewOrderService,
        handler.NewServer,
    )
    return nil, nil // replaced by generated code
}
```

`wire` generates the ordered constructor calls; the generated file is
committed and reviewed like handwritten code.

## Verification Checklist

1. Every service/handler receives dependencies via constructor parameters
2. No package-level mutable singletons (`var DB`, `var logger`, `Get()` accessors)
3. All wiring concentrated in main/run — no `init()` construction
4. Dependencies accepted as interfaces (or funcs), concrete types returned
5. Constructors validate required dependencies
6. Components testable by passing fakes — no process-global setup in tests
7. If a DI tool is used: exactly one, at the composition root only
8. `go build ./...` passes — wiring errors surface at compile time
