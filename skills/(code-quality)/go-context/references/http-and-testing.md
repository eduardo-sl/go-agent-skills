# Context in HTTP Handlers and Tests

Request-scoped context in `net/http` handlers and middleware, and how to test
cancellation. The SKILL.md summary states the rules; this file has the code.

## HTTP Handlers

### Use r.Context() for the request context:

```go
func (h *Handler) GetUser(w http.ResponseWriter, r *http.Request) {
    ctx := r.Context() // carries cancellation when client disconnects

    user, err := h.service.GetUser(ctx, id)
    if err != nil {
        if errors.Is(err, context.Canceled) {
            return // client disconnected, no point writing response
        }
        // handle error...
    }
    // ...
}
```

### Attach values via middleware:

```go
func AuthMiddleware(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        user, err := authenticate(r)
        if err != nil {
            http.Error(w, "unauthorized", http.StatusUnauthorized)
            return
        }
        ctx := WithUser(r.Context(), user)
        next.ServeHTTP(w, r.WithContext(ctx))
    })
}
```

## Testing

### Use context with timeout in tests to prevent hangs:

```go
func TestSlowOperation(t *testing.T) {
    ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
    defer cancel()

    result, err := slowOperation(ctx)
    if err != nil {
        t.Fatalf("unexpected error: %v", err)
    }
    // assert result...
}
```

### Test cancellation behavior:

```go
func TestCancellation(t *testing.T) {
    ctx, cancel := context.WithCancel(context.Background())
    cancel() // cancel immediately

    _, err := operation(ctx)
    if !errors.Is(err, context.Canceled) {
        t.Errorf("expected context.Canceled, got %v", err)
    }
}
```

