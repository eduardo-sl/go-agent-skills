# Locking, Retries and Constraint Errors

Concurrent writers, retryable failures and driver error codes. The
SKILL.md "Concurrency Control" section states the rules; this file has the
code. Examples use PostgreSQL through pgx (`*pgconn.PgError`); MySQL
drivers expose the same codes on `*mysql.MySQLError`.

## Pessimistic locking

```sql
-- Read-then-write inside one transaction: no one else changes the row in between
SELECT balance FROM accounts WHERE id = $1 FOR UPDATE;

-- Job queue: each worker claims different rows instead of waiting on each other
SELECT id, payload FROM jobs
WHERE status = 'pending'
ORDER BY created_at
LIMIT 10
FOR UPDATE SKIP LOCKED;

-- Fail fast instead of waiting for a lock
SELECT ... FOR UPDATE NOWAIT;
```

Lock rows in a consistent order (by primary key) across code paths, or two
transactions that lock the same rows in opposite orders deadlock.

## Optimistic concurrency

```go
res, err := tx.ExecContext(ctx,
    `UPDATE documents SET body = $1, version = version + 1
     WHERE id = $2 AND version = $3`, body, id, expectedVersion)
if err != nil {
    return fmt.Errorf("update document %s: %w", id, err)
}
if n, _ := res.RowsAffected(); n == 0 {
    return ErrConflict // someone else saved first; reload and let the user merge
}
```

## Retrying serialization failures and deadlocks

Under `REPEATABLE READ`/`SERIALIZABLE`, the database may abort a
transaction with `40001` (serialization failure) or `40P01` (deadlock).
The fix is to retry the **whole transaction function**, not the statement:

```go
func WithTxRetry(ctx context.Context, db *sql.DB, opts *sql.TxOptions, fn func(*sql.Tx) error) error {
    const attempts = 5 // contention that survives 5 tries needs a design fix, not more retries
    for i := 0; ; i++ {
        err := withTxOpts(ctx, db, opts, fn) // WithTx from SKILL.md, taking options
        if err == nil || i == attempts-1 || !retryable(err) {
            return err
        }
        backoff := time.Duration(1<<i) * 10 * time.Millisecond
        select {
        case <-time.After(backoff + rand.N(backoff)): // jitter: retries don't collide again
        case <-ctx.Done():
            return ctx.Err()
        }
    }
}

func retryable(err error) bool {
    var pgErr *pgconn.PgError
    return errors.As(err, &pgErr) &&
        (pgErr.Code == pgerrcode.SerializationFailure || pgErr.Code == pgerrcode.DeadlockDetected)
}
```

`fn` runs again from the start, so it must have no side effects outside
the transaction — no HTTP calls, no messages published.

## Constraint violations as domain errors

```go
if _, err := db.ExecContext(ctx, `INSERT INTO users (email) VALUES ($1)`, email); err != nil {
    var pgErr *pgconn.PgError
    if errors.As(err, &pgErr) && pgErr.Code == pgerrcode.UniqueViolation {
        return ErrEmailTaken // 409 at the handler, not 500
    }
    return fmt.Errorf("insert user: %w", err)
}
```

Check `pgErr.ConstraintName` when a table has more than one unique
constraint. Let the database enforce uniqueness — a
"SELECT, then INSERT if absent" check races.
