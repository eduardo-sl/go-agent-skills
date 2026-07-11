# Query Patterns and Pitfalls

Full examples for the query rules summarized in SKILL.md.

## Parameterized Queries — NEVER String Concatenation

```go
// ✅ Good — parameterized
rows, err := db.QueryContext(ctx,
    "SELECT id, name FROM users WHERE status = $1 AND created_at > $2",
    status, since,
)

// ❌ Bad — SQL injection vulnerability
rows, err := db.QueryContext(ctx,
    fmt.Sprintf("SELECT id, name FROM users WHERE status = '%s'", status),
)
```

## Context Propagation

```go
// ✅ Good — context propagated
row := db.QueryRowContext(ctx, "SELECT id, name FROM users WHERE id = $1", id)

// ❌ Bad — no context, no cancellation support
row := db.QueryRow("SELECT id, name FROM users WHERE id = $1", id)
```

## Multi-Row Iteration

Always close rows and check `rows.Err()` after the loop:

```go
rows, err := db.QueryContext(ctx, query, args...)
if err != nil {
    return fmt.Errorf("query users: %w", err)
}
defer rows.Close()

var users []User
for rows.Next() {
    var u User
    if err := rows.Scan(&u.ID, &u.Name, &u.Email); err != nil {
        return fmt.Errorf("scan user: %w", err)
    }
    users = append(users, u)
}

// ALWAYS check rows.Err() after iteration
if err := rows.Err(); err != nil {
    return fmt.Errorf("iterate users: %w", err)
}
```

## Single-Row Queries

```go
var user User
err := db.QueryRowContext(ctx,
    "SELECT id, name, email FROM users WHERE id = $1", id,
).Scan(&user.ID, &user.Name, &user.Email)

if errors.Is(err, sql.ErrNoRows) {
    return nil, ErrUserNotFound
}
if err != nil {
    return nil, fmt.Errorf("get user %s: %w", id, err)
}
```

## Transaction Usage

With the `WithTx` helper from SKILL.md:

```go
err := WithTx(ctx, db, func(tx *sql.Tx) error {
    if _, err := tx.ExecContext(ctx,
        "UPDATE accounts SET balance = balance - $1 WHERE id = $2", amount, fromID,
    ); err != nil {
        return fmt.Errorf("debit: %w", err)
    }

    if _, err := tx.ExecContext(ctx,
        "UPDATE accounts SET balance = balance + $1 WHERE id = $2", amount, toID,
    ); err != nil {
        return fmt.Errorf("credit: %w", err)
    }

    return nil
})
```

Isolation levels for critical operations:

```go
tx, err := db.BeginTx(ctx, &sql.TxOptions{
    Isolation: sql.LevelSerializable, // for critical financial operations
})
```

## Null Handling

```go
// ✅ Good — use sql.Null types or pointers
type User struct {
    ID    string
    Name  string
    Phone sql.NullString // nullable column
}

// Or with pointers:
type User struct {
    ID    string
    Name  string
    Phone *string // nil = SQL NULL
}
```

## Avoiding N+1 Queries

```go
// ❌ Bad — N+1 query pattern
users, _ := listUsers(ctx)
for _, u := range users {
    orders, _ := getOrdersByUser(ctx, u.ID) // 1 query per user
    u.Orders = orders
}

// ✅ Good — single query with JOIN or batch
users, _ := listUsersWithOrders(ctx) // JOIN or subquery
```

## Connection Leak Prevention

```go
// ❌ Bad — rows not closed on early return
rows, err := db.QueryContext(ctx, query)
if err != nil {
    return err
}
// forgot defer rows.Close()
if someCondition {
    return nil // rows leaked!
}
```

Place `defer rows.Close()` on the line immediately after the error
check, before any other logic.
