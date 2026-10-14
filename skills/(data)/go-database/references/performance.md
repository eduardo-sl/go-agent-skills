# Bulk Writes, Pagination and Pool Monitoring

Worked examples for the SKILL.md "Performance" section.

## Bulk writes

```go
// pgx: COPY is the fastest way to load many rows
rows := [][]any{{"a@x.io", "Ann"}, {"b@x.io", "Bob"}}
n, err := conn.CopyFrom(ctx,
    pgx.Identifier{"users"},
    []string{"email", "name"},
    pgx.CopyFromRows(rows),
)
```

```go
// database/sql: one multi-row INSERT per batch of a few hundred rows
const batchSize = 500 // large enough to amortize round trips, small enough to keep locks short
for chunk := range slices.Chunk(users, batchSize) { // Go 1.23+
    var sb strings.Builder
    args := make([]any, 0, len(chunk)*2)
    sb.WriteString("INSERT INTO users (email, name) VALUES ")
    for i, u := range chunk {
        if i > 0 {
            sb.WriteString(", ")
        }
        fmt.Fprintf(&sb, "($%d, $%d)", 2*i+1, 2*i+2) // placeholders, never values
        args = append(args, u.Email, u.Name)
    }
    if _, err := tx.ExecContext(ctx, sb.String(), args...); err != nil {
        return fmt.Errorf("insert batch: %w", err)
    }
}
```

## Keyset pagination

```go
// ❌ OFFSET scans and throws away every skipped row, and shifts under inserts
//   SELECT ... ORDER BY created_at DESC LIMIT 50 OFFSET 100000

// ✅ Continue from the last row seen; uses the (created_at, id) index
rows, err := db.QueryContext(ctx, `
    SELECT id, created_at, title FROM posts
    WHERE (created_at, id) < ($1, $2)
    ORDER BY created_at DESC, id DESC
    LIMIT 50`, cursor.CreatedAt, cursor.ID)
```

Encode `(created_at, id)` of the last row as an opaque cursor for the
client. The `id` tiebreaker keeps rows with equal timestamps from being
skipped or repeated.

## Pool monitoring

```go
// Export these as gauges/counters every few seconds.
s := db.Stats()
s.OpenConnections   // in use + idle
s.InUse
s.WaitCount         // total waits for a free connection — rising means the pool is too small
s.WaitDuration      // total time spent waiting
s.MaxIdleClosed     // churn: idle pool too small for the load
s.MaxLifetimeClosed
```

`WaitCount` growing while the database is idle means the pool, not the
database, is the bottleneck — or something is holding connections
(unclosed rows, long transactions).

## Nullable columns with generics (Go 1.22+)

```go
var deletedAt sql.Null[time.Time]
err := row.Scan(&u.ID, &deletedAt)
if deletedAt.Valid {
    u.DeletedAt = &deletedAt.V
}
```
