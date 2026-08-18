# Context Values

Full rules and examples for `context.WithValue`. The SKILL.md summary covers
what to store and why keys must be unexported; this file has the code.

## Use sparingly — only for request-scoped metadata:

```go
// ✅ Appropriate uses:
// - Request ID
// - Trace/span ID
// - Authenticated user info
// - Request-scoped logger

// ❌ Bad uses:
// - Database connections (use dependency injection)
// - Configuration (use struct fields)
// - Function parameters (pass explicitly)
```

## Use unexported key types to prevent collisions:

```go
// ✅ Good — unexported type prevents key collisions
type contextKey struct{}

var requestIDKey = contextKey{}

func WithRequestID(ctx context.Context, id string) context.Context {
    return context.WithValue(ctx, requestIDKey, id)
}

func RequestID(ctx context.Context) string {
    id, _ := ctx.Value(requestIDKey).(string)
    return id
}
```

```go
// ❌ Bad — string keys risk collisions across packages
ctx = context.WithValue(ctx, "request_id", id) // any package could overwrite this
```

## Always provide accessor functions — never expose the key:

```go
// ✅ Good — clean API with accessors
rid := middleware.RequestID(ctx)

// ❌ Bad — exposes internal key type
rid := ctx.Value(requestIDKey).(string) // caller needs key, risks panic on nil
```

