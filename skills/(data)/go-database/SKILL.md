---
name: go-database
description: >
  Database patterns for Go services: database/sql, connection management,
  transactions, migrations, query builders, and ORM usage (sqlc, GORM, ent).
  Use when: "database access", "SQL query", "connection pool",
  "transactions", "database migration", "sqlc", "GORM", "ent", "prepared
  statement", "repository pattern".
  Not for: in-memory structures (go-data-structures), SQL security
  (go-security-audit), query profiling (go-performance-review).
user-invocable: true
license: MIT
compatibility: Designed for Claude Code or similar AI coding agents working on Go projects. Requires the Go toolchain. sqlc, golang-migrate and Docker are optional.
allowed-tools: Read Edit Write Glob Grep Bash(go:*) Bash(gofmt:*)
metadata:
  author: eduardo-sl
  version: "1.2.1"
---

# Go Database Patterns

Database access is where most Go services spend their complexity budget.
Get connection management, transactions, and query patterns right.

Detailed reference material, loaded on demand:

- `references/query-patterns.md` — full query/scan/rows patterns, null
  handling, N+1 avoidance, connection-leak examples.
- `references/tooling.md` — repository pattern implementation, sqlc
  annotated queries, migration tooling and rules.

Read a reference file only when the summary below is not enough.

## 1. Connection Management

Configure the pool explicitly — the default is unbounded connections:

```go
func OpenDB(dsn string) (*sql.DB, error) {
    db, err := sql.Open("postgres", dsn)
    if err != nil {
        return nil, fmt.Errorf("open db: %w", err)
    }

    db.SetMaxOpenConns(25)
    db.SetMaxIdleConns(10)
    db.SetConnMaxLifetime(5 * time.Minute)
    db.SetConnMaxIdleTime(1 * time.Minute)

    if err := db.PingContext(context.Background()); err != nil {
        return nil, fmt.Errorf("ping db: %w", err)
    }

    return db, nil
}
```

| Setting | Guideline |
|---|---|
| `MaxOpenConns` | Match your DB's max connections / number of app instances |
| `MaxIdleConns` | 40-50% of MaxOpenConns |
| `ConnMaxLifetime` | 5-10 minutes (prevents stale connections behind load balancers) |
| `ConnMaxIdleTime` | 1-2 minutes |

## 2. Query Rules

1. **Parameterized queries only** — string concatenation into SQL is an
   injection vulnerability, no exceptions.
2. **Always pass context** — use the `*Context` variants
   (`QueryContext`, `QueryRowContext`, `ExecContext`) so queries respect
   cancellation and timeouts.
3. **`defer rows.Close()`** immediately after the error check, and check
   `rows.Err()` after the iteration loop.
4. **Handle `sql.ErrNoRows` explicitly** with `errors.Is`, mapping it to
   a domain error like `ErrUserNotFound`.

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

Multi-row iteration patterns: `references/query-patterns.md`.

## 3. Transactions

Use a helper that guarantees rollback on error:

```go
func WithTx(ctx context.Context, db *sql.DB, fn func(tx *sql.Tx) error) error {
    tx, err := db.BeginTx(ctx, nil)
    if err != nil {
        return fmt.Errorf("begin tx: %w", err)
    }

    if err := fn(tx); err != nil {
        if rbErr := tx.Rollback(); rbErr != nil {
            return fmt.Errorf("rollback failed: %v (original: %w)", rbErr, err)
        }
        return err
    }

    if err := tx.Commit(); err != nil {
        return fmt.Errorf("commit tx: %w", err)
    }
    return nil
}
```

Set isolation explicitly for critical operations:
`sql.TxOptions{Isolation: sql.LevelSerializable}`.

## 4. Structure and Tooling

- **Repository pattern:** define the interface at the consumer side,
  implement it with concrete database access, map driver errors to
  domain errors at this boundary.
- **sqlc:** prefer it for raw-SQL projects — generates type-safe Go from
  annotated SQL, catching query/schema mismatches at build time.
- **Migrations:** use a tool (`goose`, `golang-migrate`, `atlas`), one
  migration per change, forward-only in production, with `down` SQL, run
  as a separate step — not at server startup.

Implementations and examples: `references/tooling.md`.

## 5. Common Pitfalls

- **Null columns:** use `sql.NullString`/`sql.NullInt64` or pointer
  fields (`*string`, nil = SQL NULL). Scanning NULL into a plain string
  errors at runtime.
- **N+1 queries:** a query inside a loop over query results. Replace
  with a JOIN or a batch query (`WHERE id = ANY($1)`).
- **Connection leaks:** any early `return` between `Query` and
  `defer rows.Close()` leaks a connection from the pool.

Worked examples of each pitfall: `references/query-patterns.md`.

## Verification Checklist

1. Connection pool configured with explicit limits (`MaxOpenConns`, `MaxIdleConns`, lifetimes)
2. All queries use parameterized placeholders, never string concatenation
3. All `QueryContext` results have `defer rows.Close()` immediately after error check
4. `rows.Err()` checked after row iteration loop
5. `sql.ErrNoRows` handled explicitly with `errors.Is`
6. Transactions use a helper that guarantees rollback on error
7. Context propagated to all database calls (`*Context` variants)
8. Nullable columns use `sql.NullString` / `sql.NullInt64` or pointer types
9. No N+1 query patterns — use JOINs or batch queries
10. Migrations are versioned, reversible, and run separately from app startup
