# Standard Library Migrations

Full before/after examples for the migrations summarized in SKILL.md.

## log/slog (Go 1.21+)

Replace `log`/`fmt.Printf` with structured logging:

```go
// ❌ Before
log.Printf("processing order %s for user %s", orderID, userID)

// ✅ After
slog.Info("processing order",
    slog.String("order_id", orderID),
    slog.String("user_id", userID),
)
```

Replace third-party loggers where slog is sufficient:

```go
// Before — zap
logger.Info("request completed",
    zap.String("method", method),
    zap.Int("status", status),
    zap.Duration("latency", elapsed),
)

// After — slog (if you don't need zap-specific features)
slog.Info("request completed",
    slog.String("method", method),
    slog.Int("status", status),
    slog.Duration("latency", elapsed),
)
```

Keep zap/zerolog if you need their performance characteristics for
high-throughput logging. For most services, slog is sufficient.

## errors.Join (Go 1.20+)

```go
// ❌ Before — manual error accumulation
var errMsgs []string
for _, item := range items {
    if err := validate(item); err != nil {
        errMsgs = append(errMsgs, err.Error())
    }
}
if len(errMsgs) > 0 {
    return fmt.Errorf("validation: %s", strings.Join(errMsgs, "; "))
}

// ✅ After — errors.Join preserves the error chain
var errs []error
for _, item := range items {
    if err := validate(item); err != nil {
        errs = append(errs, err)
    }
}
if err := errors.Join(errs...); err != nil {
    return fmt.Errorf("validation: %w", err)
}
```

`errors.Join` preserves the full error chain — `errors.Is` and
`errors.As` work on each individual error.

## slices Package (Go 1.21+)

```go
// ❌ Before — manual sort
sort.Slice(users, func(i, j int) bool {
    return users[i].Name < users[j].Name
})

// ✅ After — slices.SortFunc
slices.SortFunc(users, func(a, b User) int {
    return cmp.Compare(a.Name, b.Name)
})
```

```go
// ❌ Before — manual contains check
found := false
for _, v := range items {
    if v == target {
        found = true
        break
    }
}

// ✅ After
found := slices.Contains(items, target)
```

```go
// ❌ Before — manual index search
idx := -1
for i, v := range items {
    if v.ID == targetID {
        idx = i
        break
    }
}

// ✅ After
idx := slices.IndexFunc(items, func(item Item) bool {
    return item.ID == targetID
})
```

## maps Package (Go 1.21+)

```go
// ❌ Before — manual key collection
keys := make([]string, 0, len(m))
for k := range m {
    keys = append(keys, k)
}

// ✅ After
keys := slices.Collect(maps.Keys(m))
```

```go
// ❌ Before — manual map clone
clone := make(map[string]int, len(m))
for k, v := range m {
    clone[k] = v
}

// ✅ After
clone := maps.Clone(m)
```

## Range Over Integers (Go 1.22+)

```go
// ❌ Before
for i := 0; i < n; i++ {
    process(i)
}

// ✅ After
for i := range n {
    process(i)
}
```

## Range Over Function / Iterators (Go 1.23+)

Custom iterator with `iter.Seq2` that yields values and errors:

```go
// ✅ Iterator that yields filtered results
func (db *DB) ActiveUsers(ctx context.Context) iter.Seq2[User, error] {
    return func(yield func(User, error) bool) {
        rows, err := db.QueryContext(ctx, "SELECT id, name FROM users WHERE active = true")
        if err != nil {
            yield(User{}, fmt.Errorf("query active users: %w", err))
            return
        }
        defer rows.Close()

        for rows.Next() {
            var u User
            if err := rows.Scan(&u.ID, &u.Name); err != nil {
                if !yield(User{}, fmt.Errorf("scan user: %w", err)) {
                    return
                }
                continue
            }
            if !yield(u, nil) {
                return
            }
        }
        if err := rows.Err(); err != nil {
            yield(User{}, fmt.Errorf("iterate users: %w", err))
        }
    }
}

// Usage — clean range loop
for user, err := range db.ActiveUsers(ctx) {
    if err != nil {
        return fmt.Errorf("active users: %w", err)
    }
    process(user)
}
```

Standard library iterators — use them:

```go
// maps.Keys, maps.Values return iterators (Go 1.23+)
for key := range maps.Keys(m) {
    fmt.Println(key)
}

// slices.All, slices.Values, slices.Backward
for i, v := range slices.Backward(items) {
    fmt.Printf("%d: %v\n", i, v)
}
```

## http.NewRequestWithContext (Go 1.13+, often missed)

```go
// ❌ Before — request without context
req, err := http.NewRequest(http.MethodGet, url, nil)

// ✅ After — context propagated
req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
```
