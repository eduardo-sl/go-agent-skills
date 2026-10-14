# Handlers, Middleware and Validation

Worked examples for the rules in SKILL.md sections 1-3.

## HTTP Handler Structure

### Handler as a struct with dependencies

```go
// ✅ Good — method on a struct with dependencies
type UserHandler struct {
    store  UserStore
    logger *slog.Logger
}

func (h *UserHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
    switch r.Method {
    case http.MethodGet:
        h.handleGet(w, r)
    case http.MethodPost:
        h.handleCreate(w, r)
    default:
        http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
    }
}
```

### Handler method

```go
// Handler methods return nothing — they write directly to ResponseWriter.
// Errors are handled inside the handler, not returned.
func (h *UserHandler) handleGet(w http.ResponseWriter, r *http.Request) {
    ctx := r.Context()

    id := chi.URLParam(r, "id") // or mux.Vars(r)["id"]
    if id == "" {
        h.respondError(w, http.StatusBadRequest, "missing user id")
        return
    }

    user, err := h.store.GetByID(ctx, id)
    if err != nil {
        if errors.Is(err, ErrNotFound) {
            h.respondError(w, http.StatusNotFound, "user not found")
            return
        }
        h.logger.Error("get user", slog.Any("error", err))
        h.respondError(w, http.StatusInternalServerError, "internal error")
        return
    }

    h.respondJSON(w, http.StatusOK, user)
}
```

### JSON response helpers

```go
func (h *UserHandler) respondJSON(w http.ResponseWriter, status int, data interface{}) {
    w.Header().Set("Content-Type", "application/json")
    w.WriteHeader(status)
    if err := json.NewEncoder(w).Encode(data); err != nil {
        h.logger.Error("encode response", slog.Any("error", err))
    }
}

func (h *UserHandler) respondError(w http.ResponseWriter, status int, msg string) {
    h.respondJSON(w, status, map[string]string{"error": msg})
}
```

## Middleware Pattern

Middleware wraps handlers. Use the standard `func(http.Handler) http.Handler` signature:

```go
func RequestID(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        id := r.Header.Get("X-Request-ID")
        if id == "" {
            id = uuid.New().String()
        }
        ctx := context.WithValue(r.Context(), requestIDKey, id)
        w.Header().Set("X-Request-ID", id)
        next.ServeHTTP(w, r.WithContext(ctx))
    })
}

func Recoverer(logger *slog.Logger) func(http.Handler) http.Handler {
    return func(next http.Handler) http.Handler {
        return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
            defer func() {
                if rec := recover(); rec != nil {
                    logger.Error("panic recovered",
                        slog.Any("panic", rec),
                        slog.String("stack", string(debug.Stack())),
                    )
                    http.Error(w, "internal server error", http.StatusInternalServerError)
                }
            }()
            next.ServeHTTP(w, r)
        })
    }
}
```

### Middleware ordering (outside → inside)

```text
Recoverer → RequestID → Logger → Auth → RateLimit → Handler
```

Recover MUST be outermost. Auth before business logic. Logger captures timing.

## Request Validation

### Decode and validate in one step

```go
type CreateUserRequest struct {
    Name  string `json:"name"  validate:"required,min=2,max=100"`
    Email string `json:"email" validate:"required,email"`
}

func decodeAndValidate[T any](r *http.Request) (T, error) {
    var req T
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        return req, fmt.Errorf("decode: %w", err)
    }
    if err := validate.Struct(req); err != nil {
        return req, fmt.Errorf("validate: %w", err)
    }
    return req, nil
}
```

### Limit request body size

```go
r.Body = http.MaxBytesReader(w, r.Body, 1<<20) // 1 MB
```
