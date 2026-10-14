# Error Patterns and Boundaries

Worked examples for SKILL.md sections 8 and 9.

## Checking patterns

```go
// Inline error check — preferred for simple cases
if err := doSomething(); err != nil {
    return fmt.Errorf("do something: %w", err)
}

// Multi-return with named result — acceptable for complex functions
func process() (result string, err error) {
    defer func() {
        if err != nil {
            err = fmt.Errorf("process: %w", err)
        }
    }()
    // ...
}

// errors.Join for multiple errors (Go 1.20+)
var errs []error
for _, item := range items {
    if err := validate(item); err != nil {
        errs = append(errs, err)
    }
}
return errors.Join(errs...)
```

## Matching a family of errors with `Is`

```go
var ErrNotFound = errors.New("not found")

type NotFoundError struct{ Kind, ID string }

func (e *NotFoundError) Error() string { return e.Kind + " " + e.ID + ": not found" }

// errors.Is(err, ErrNotFound) now matches every *NotFoundError, so callers
// can test the category without knowing the concrete type.
func (e *NotFoundError) Is(target error) bool { return target == ErrNotFound }
```

## Translating at the HTTP boundary

```go
func (h *Handler) writeError(w http.ResponseWriter, r *http.Request, err error) {
    status, msg := http.StatusInternalServerError, "internal error"
    switch {
    case errors.Is(err, ErrNotFound):
        status, msg = http.StatusNotFound, "not found"
    case errors.Is(err, ErrConflict):
        status, msg = http.StatusConflict, "already exists"
    }
    if status >= 500 {
        // Logged once, here, with the full chain. The client never sees it.
        h.logger.ErrorContext(r.Context(), "request failed", slog.Any("error", err))
    }
    http.Error(w, msg, status)
}
```

## Low-cardinality log messages

```go
// ❌ Every user ID mints a new message; the log backend cannot group them
logger.Error(fmt.Sprintf("failed to load user %d: %v", id, err))

// ✅ Stable message, variable data as attributes
logger.Error("load user failed", slog.Int64("user_id", id), slog.Any("error", err))
```

## `%w` on a pointer to a value-receiver error (vet, Go 1.27+)

```go
type ParseError struct{ Line int }

func (e ParseError) Error() string { return fmt.Sprintf("line %d", e.Line) }

pe := ParseError{Line: 3}
err := fmt.Errorf("load: %w", &pe) // ❌ vet: wraps *ParseError; errors.As(err, &ParseError{}) misses it
err = fmt.Errorf("load: %w", pe)   // ✅ wrap the value the Error method is defined on
```
