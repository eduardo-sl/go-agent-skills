# Timeout Budgets and Deadlines

How a child timeout divides the parent's remaining budget, and how to read
the deadline before starting work that cannot finish inside it.

## Timeout budgets — don't exceed parent timeout:

```go
// ✅ Good — child timeout shorter than parent
func handler(ctx context.Context) error {
    // Parent has 30s timeout (from HTTP server)

    // Give DB query 5s of the 30s budget
    dbCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
    defer cancel()
    data, err := db.QueryContext(dbCtx, query)

    // Give external API 10s of the remaining budget
    apiCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
    defer cancel()
    result, err := client.Call(apiCtx, data)

    return nil
}

// ❌ Bad — child timeout exceeds parent (silently capped anyway)
ctx, cancel := context.WithTimeout(parentCtx, 60*time.Second) // parent has 5s left
// This timeout is 60s but will actually fire at parent's deadline
```

## Check if deadline exists:

```go
if deadline, ok := ctx.Deadline(); ok {
    remaining := time.Until(deadline)
    if remaining < minRequired {
        return fmt.Errorf("insufficient time remaining: %v", remaining)
    }
}
```
