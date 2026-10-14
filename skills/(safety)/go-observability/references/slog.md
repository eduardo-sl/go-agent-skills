# Structured Logging with slog

Setup and wiring examples for `log/slog`. The SKILL.md section states the
rules; this file has the code.

## Contents

- Handler setup
- Logger as a dependency
- Child loggers with scoped attributes
- Redaction by type with `LogValuer`
- Trace IDs on every record
- Hot paths and runtime levels
- Fan-out (Go 1.26+)

## Handler setup

```go
// ✅ Good — structured, leveled logging
logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
    Level: slog.LevelInfo,
}))

logger.Info("user created",
    slog.String("user_id", user.ID),
    slog.Duration("latency", elapsed),
)
```

```go
// ❌ Bad — unstructured printf-style logging
log.Printf("user %s created in %v", user.ID, elapsed)
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

    log.Info("creating user", slog.String("tenant_id", req.TenantID))

    if err := s.store.Insert(ctx, req); err != nil {
        log.Error("failed to create user", slog.Any("error", err))
        return fmt.Errorf("create user: %w", err)
    }

    log.Info("user created successfully")
    return nil
}
```

## Redaction by type with `LogValuer`

```go
// Any value of this type logs as [REDACTED], wherever it ends up —
// including inside a struct someone logs with slog.Any next year.
type Secret string

func (Secret) LogValue() slog.Value { return slog.StringValue("[REDACTED]") }

// Structs choose which fields are safe to log.
func (u User) LogValue() slog.Value {
    return slog.GroupValue(
        slog.String("id", u.ID),
        slog.String("plan", u.Plan),
    ) // Email, Phone and PasswordHash never leave the process via logs
}
```

Redaction on the type is enforced at every call site; a code review rule
("don't log the email") is enforced at none.

## Trace IDs on every record

```go
// traceHandler adds trace_id/span_id from ctx to every *Context call.
type traceHandler struct{ slog.Handler }

func (h traceHandler) Handle(ctx context.Context, r slog.Record) error {
    if sc := trace.SpanContextFromContext(ctx); sc.IsValid() {
        r.AddAttrs(
            slog.String("trace_id", sc.TraceID().String()),
            slog.String("span_id", sc.SpanID().String()),
        )
    }
    return h.Handler.Handle(ctx, r)
}

// Without these two, logger.With(...) returns the inner handler and the
// trace IDs silently disappear from child loggers.
func (h traceHandler) WithAttrs(as []slog.Attr) slog.Handler { return traceHandler{h.Handler.WithAttrs(as)} }
func (h traceHandler) WithGroup(n string) slog.Handler      { return traceHandler{h.Handler.WithGroup(n)} }

logger := slog.New(traceHandler{slog.NewJSONHandler(os.Stdout, nil)})
logger.InfoContext(ctx, "order created", slog.String("order_id", id))
```

To ship logs through the OpenTelemetry pipeline instead of stdout, the
`go.opentelemetry.io/contrib/bridges/otelslog` handler does the same
correlation.

## Hot paths and runtime levels

```go
// LogAttrs avoids boxing every argument into `any`
logger.LogAttrs(ctx, slog.LevelInfo, "request served",
    slog.Int("status", status), slog.Duration("latency", d))

// Don't build expensive attributes for a disabled level
if logger.Enabled(ctx, slog.LevelDebug) {
    logger.DebugContext(ctx, "cache state", slog.Any("snapshot", c.snapshot()))
}

// A level that can change at run time (e.g. from an admin endpoint)
var level slog.LevelVar // zero value is Info
logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: &level}))
level.Set(slog.LevelDebug)
```

## Fan-out (Go 1.26+)

```go
logger := slog.New(slog.NewMultiHandler(
    slog.NewJSONHandler(os.Stdout, nil),
    auditHandler, // e.g. a handler that keeps only security events
))
```
