# Behavioral and Structural Patterns

Full examples for the behavioral patterns summarized in SKILL.md.

## Contents

- Strategy with Function Types (simpler)
- Strategy with Interfaces (when behavior is complex)
- HTTP Middleware Chain
- Interface Decorator
- Result Type Pattern
- Cleanup with defer
- Sentinel Values vs Zero Values

## Strategy with Function Types (simpler)

```go
type RetryStrategy func(attempt int) time.Duration

func ExponentialBackoff(base time.Duration) RetryStrategy {
    return func(attempt int) time.Duration {
        return base * time.Duration(1<<uint(attempt))
    }
}

func ConstantDelay(d time.Duration) RetryStrategy {
    return func(_ int) time.Duration {
        return d
    }
}

func Retry(ctx context.Context, maxAttempts int, strategy RetryStrategy, fn func() error) error {
    var err error
    for i := 0; i < maxAttempts; i++ {
        if err = fn(); err == nil {
            return nil
        }
        select {
        case <-ctx.Done():
            return ctx.Err()
        case <-time.After(strategy(i)):
        }
    }
    return fmt.Errorf("after %d attempts: %w", maxAttempts, err)
}
```

## Strategy with Interfaces (when behavior is complex)

```go
type Notifier interface {
    Notify(ctx context.Context, event Event) error
}

type SlackNotifier struct{ webhookURL string }
type EmailNotifier struct{ smtpClient *smtp.Client }
type NoopNotifier struct{}

// Each implements Notifier. Inject the right one at startup.
```

## HTTP Middleware Chain

```go
type Middleware func(http.Handler) http.Handler

func Chain(handler http.Handler, middlewares ...Middleware) http.Handler {
    for i := len(middlewares) - 1; i >= 0; i-- {
        handler = middlewares[i](handler)
    }
    return handler
}

// Usage:
handler := Chain(appHandler, Recoverer, RequestID, Logger, Auth)
```

## Interface Decorator

```go
type UserRepository interface {
    GetByID(ctx context.Context, id string) (*User, error)
}

// Logging decorator
type loggingUserRepo struct {
    next   UserRepository
    logger *slog.Logger
}

func NewLoggingUserRepo(next UserRepository, logger *slog.Logger) UserRepository {
    return &loggingUserRepo{next: next, logger: logger}
}

func (r *loggingUserRepo) GetByID(ctx context.Context, id string) (*User, error) {
    start := time.Now()
    user, err := r.next.GetByID(ctx, id)
    r.logger.Info("GetByID",
        slog.String("id", id),
        slog.Duration("duration", time.Since(start)),
        slog.Any("error", err),
    )
    return user, err
}
```

Stack decorators: `cache → logging → metrics → actual repo`.

## Result Type Pattern

For operations that can return a value or an error in concurrent
pipelines:

```go
type Result[T any] struct {
    Value T
    Err   error
}

func fetchAll(ctx context.Context, ids []string) []Result[User] {
    results := make([]Result[User], len(ids))

    var g errgroup.Group
    g.SetLimit(8) // bound concurrent fetches; an unbounded fan-out is a DoS on the backend

    for i, id := range ids { // Go 1.22+: i and id are per-iteration
        g.Go(func() error {
            user, err := fetchUser(ctx, id)
            results[i] = Result[User]{Value: user, Err: err} // each goroutine owns one index
            return nil // per-item errors live in the result, not the group
        })
    }
    _ = g.Wait() // always nil: every func returns nil
    return results
}
```

Use this shape when one failure must not cancel the rest. When it should,
switch to `errgroup.WithContext` and return the error from the func.

## Cleanup with defer

Resource management pattern:

```go
func processFile(path string) error {
    f, err := os.Open(path)
    if err != nil {
        return fmt.Errorf("open %s: %w", path, err)
    }
    defer f.Close()

    // process file...
    return nil
}
```

Multi-resource cleanup:

```go
func migrate(ctx context.Context, srcDSN, dstDSN string) error {
    src, err := sql.Open("postgres", srcDSN)
    if err != nil {
        return fmt.Errorf("open source: %w", err)
    }
    defer src.Close()

    dst, err := sql.Open("postgres", dstDSN)
    if err != nil {
        return fmt.Errorf("open dest: %w", err)
    }
    defer dst.Close()

    // defers execute LIFO: dst.Close() first, then src.Close()
    return doMigration(ctx, src, dst)
}
```

## Sentinel Values vs Zero Values

Use the zero value as a useful default when possible:

```go
// ✅ Good — sync.Mutex zero value is an unlocked mutex
var mu sync.Mutex

// ✅ Good — bytes.Buffer zero value is an empty buffer
var buf bytes.Buffer

// ✅ Good — slice zero value is a valid empty slice
var users []User // nil slice works with append, len, range
```

Use sentinel values when the zero value is ambiguous:

```go
// When zero value is a valid input, use pointer or custom type
type Temperature struct {
    Celsius float64
    IsSet   bool
}

// Or use a pointer
func SetThreshold(t *float64) { // nil means "not configured"
    if t != nil {
        applyThreshold(*t)
    }
}
```
