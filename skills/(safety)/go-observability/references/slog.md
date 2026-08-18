# Structured Logging with slog

Setup and wiring examples for `log/slog`. The SKILL.md section states the
rules; this file has the code.

## Handler setup

```go
// ✅ Good — structured, leveled logging
logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
    Level: slog.LevelInfo,
}))

logger.Info("user created",
    slog.String("user_id", user.ID),
    slog.String("email", user.Email),
    slog.Duration("latency", elapsed),
)
```

```go
// ❌ Bad — unstructured printf-style logging
log.Printf("user %s created with email %s in %v", user.ID, user.Email, elapsed)
```

## Logger as a dependency

```go
// ✅ Good — logger as dependency
type UserService struct {
    logger *slog.Logger
    store  UserStore
}

func NewUserService(logger *slog.Logger, store UserStore) *UserService {
    return &UserService{
        logger: logger.With(slog.String("component", "user_service")),
        store:  store,
    }
}
```

```go
// ❌ Bad — global logger
var logger = slog.Default()
```

## Child loggers with scoped attributes

```go
func (s *UserService) CreateUser(ctx context.Context, req CreateUserReq) error {
    log := s.logger.With(
        slog.String("method", "CreateUser"),
        slog.String("request_id", middleware.RequestID(ctx)),
    )

    log.Info("creating user", slog.String("email", req.Email))

    if err := s.store.Insert(ctx, req); err != nil {
        log.Error("failed to create user", slog.Any("error", err))
        return fmt.Errorf("create user: %w", err)
    }

    log.Info("user created successfully")
    return nil
}
```
