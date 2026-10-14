# Resilience Patterns and Types That Carry Invariants

Worked examples for SKILL.md sections 6 and 7.

## Contents

- Retry with backoff and jitter
- Circuit breaker
- Bulkheads
- Make illegal states unrepresentable

## Retry with backoff and jitter

```go
// Retry calls fn until it succeeds, returns a non-retryable error, runs out
// of attempts, or ctx is done. Full jitter spreads retries from many clients
// so they don't hit the recovering dependency in lockstep.
func Retry(ctx context.Context, attempts int, base, maxDelay time.Duration,
    fn func(context.Context) error) error {
    var err error
    for i := range attempts {
        if err = fn(ctx); err == nil || !retryable(err) {
            return err
        }
        if i == attempts-1 {
            break
        }
        delay := rand.N(min(maxDelay, base<<i)) // math/rand/v2: jitter, not security
        t := time.NewTimer(delay)
        select {
        case <-ctx.Done():
            t.Stop()
            return errors.Join(err, ctx.Err())
        case <-t.C:
        }
    }
    return err
}

func retryable(err error) bool {
    var netErr net.Error
    return errors.Is(err, ErrUnavailable) || (errors.As(err, &netErr) && netErr.Timeout())
}
```

- Retry only operations that are safe to repeat (reads, idempotent writes,
  requests with an idempotency key).
- Retry at one layer. Retries at the client, the service and the database
  driver multiply: 3 × 3 × 3 = 27 attempts against a dependency that is
  already failing.
- Respect `Retry-After` when the server sends it.

## Circuit breaker

When a dependency is down, failing fast protects both sides: callers stop
holding goroutines and connections, and the dependency gets room to
recover. The breaker opens after a failure threshold, rejects calls for a
cool-down, then lets a few probe calls through (half-open) before closing.

```go
cb := gobreaker.NewCircuitBreaker[*Rate](gobreaker.Settings{ // github.com/sony/gobreaker/v2
    Name:    "fx-rates",
    Timeout: 30 * time.Second, // how long to stay open before probing
    ReadyToTrip: func(c gobreaker.Counts) bool {
        return c.Requests >= 20 && float64(c.TotalFailures)/float64(c.Requests) > 0.5
    },
})

rate, err := cb.Execute(func() (*Rate, error) { return client.Rate(ctx, "EUR") })
if errors.Is(err, gobreaker.ErrOpenState) {
    return cachedRate("EUR") // degrade instead of failing the request
}
```

Use a maintained implementation rather than hand-rolling the state
machine; the half-open transitions are easy to get wrong under concurrency.

## Bulkheads

```go
// At most 10 concurrent calls to the slow reporting service, so it cannot
// absorb every goroutine and connection the process has.
var reportSlots = semaphore.NewWeighted(10) // golang.org/x/sync/semaphore

func (s *Service) Report(ctx context.Context, id string) (*Report, error) {
    if err := reportSlots.Acquire(ctx, 1); err != nil {
        return nil, err // ctx done while waiting
    }
    defer reportSlots.Release(1)
    return s.reports.Get(ctx, id)
}
```

## Make illegal states unrepresentable

```go
// Email can only be built by ParseEmail, so a function that takes an Email
// never needs to validate it again.
type Email struct{ addr string }

func ParseEmail(s string) (Email, error) {
    a, err := mail.ParseAddress(s)
    if err != nil {
        return Email{}, fmt.Errorf("parse email: %w", err)
    }
    return Email{addr: a.Address}, nil
}

func (e Email) String() string { return e.addr }
```

```go
// ❌ Four booleans allow 16 combinations; most are nonsense (shipped but unpaid)
type Order struct{ Paid, Shipped, Delivered, Cancelled bool }

// ✅ One state, explicit transitions
type OrderStatus int

const (
    StatusUnknown OrderStatus = iota
    StatusPending
    StatusPaid
    StatusShipped
    StatusDelivered
    StatusCancelled
)

func (o *Order) Ship() error {
    if o.Status != StatusPaid {
        return fmt.Errorf("ship order in status %v: %w", o.Status, ErrInvalidTransition)
    }
    o.Status = StatusShipped
    return nil
}
```
