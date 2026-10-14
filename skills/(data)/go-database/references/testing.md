# Testing Database Code

Worked examples for the SKILL.md "Testing" section.

## Choose the level

| What you are testing | Use |
|---|---|
| Service logic above the repository | A fake implementing the consumer-side repository interface |
| SQL itself: queries, constraints, transactions, locking | A real database in a container |
| Error-path handling for a driver error | A fake returning that error, or a real constraint violation |

Mocking SQL strings (sqlmock) proves you wrote the query you wrote, not
that the database accepts it — keep it for rare cases where a real
database cannot reproduce the condition.

## Real PostgreSQL with testcontainers

```go
//go:build integration

func newTestDB(t *testing.T) *sql.DB {
    t.Helper()
    ctx := t.Context()
    pg, err := postgres.Run(ctx, "postgres:17-alpine",
        postgres.WithDatabase("app"),
        postgres.BasicWaitStrategies(),
    )
    if err != nil {
        t.Fatal(err)
    }
    t.Cleanup(func() { _ = pg.Terminate(context.Background()) })

    dsn, err := pg.ConnectionString(ctx, "sslmode=disable")
    if err != nil {
        t.Fatal(err)
    }
    db, err := sql.Open("pgx", dsn)
    if err != nil {
        t.Fatal(err)
    }
    t.Cleanup(func() { db.Close() })
    runMigrations(t, db) // the same migrations production runs
    return db
}
```

Start one container per package in `TestMain` when tests are many — a
container per test is correct but slow.

## Isolation between tests

- **Transaction per test:** begin in the test, pass the `*sql.Tx` to the
  code under test, roll back in `t.Cleanup`. Fast; does not work when the
  code under test commits on its own.
- **Template database (PostgreSQL):** migrate once into a template, then
  `CREATE DATABASE test_N TEMPLATE app_template` per test or package.
- **Truncate between tests:** simplest; forbids `t.Parallel()`.
