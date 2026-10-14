# Reference Layout and Wiring

Worked examples for SKILL.md sections 1 and 3.

## Reference service layout

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

## Composition root

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
