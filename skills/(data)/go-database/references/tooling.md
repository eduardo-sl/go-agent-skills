# Repository Pattern, sqlc, and Migrations

Full examples for the structure/tooling rules summarized in SKILL.md.

## Repository Pattern

Define a repository interface at the consumer side:

```go
type UserRepository interface {
    GetByID(ctx context.Context, id string) (*User, error)
    List(ctx context.Context, filter UserFilter) ([]User, error)
    Create(ctx context.Context, user *User) error
    Update(ctx context.Context, user *User) error
    Delete(ctx context.Context, id string) error
}
```

Implement with concrete database access, mapping driver errors to domain
errors at this boundary:

```go
type pgUserRepo struct {
    db *sql.DB
}

func NewUserRepository(db *sql.DB) UserRepository {
    return &pgUserRepo{db: db}
}

func (r *pgUserRepo) GetByID(ctx context.Context, id string) (*User, error) {
    var u User
    err := r.db.QueryRowContext(ctx,
        "SELECT id, name, email, created_at FROM users WHERE id = $1", id,
    ).Scan(&u.ID, &u.Name, &u.Email, &u.CreatedAt)

    if errors.Is(err, sql.ErrNoRows) {
        return nil, ErrUserNotFound
    }
    if err != nil {
        return nil, fmt.Errorf("get user %s: %w", id, err)
    }
    return &u, nil
}
```

## sqlc — Type-Safe SQL

Prefer sqlc for projects that use raw SQL. It generates type-safe Go
code from SQL queries.

Write SQL queries with annotations:

```sql
-- name: GetUser :one
SELECT id, name, email, created_at
FROM users
WHERE id = $1;

-- name: ListUsers :many
SELECT id, name, email, created_at
FROM users
WHERE status = $1
ORDER BY created_at DESC
LIMIT $2 OFFSET $3;

-- name: CreateUser :one
INSERT INTO users (name, email)
VALUES ($1, $2)
RETURNING id, name, email, created_at;
```

sqlc generates Go code with proper types, eliminating manual `Scan`
calls and catching query/schema mismatches at build time.

## Migrations

Use a migration tool — never manual DDL. Recommended tools: `goose`,
`golang-migrate`, `atlas`.

Migration rules:

- One migration per schema change
- Migrations are forward-only in production — never edit applied migrations
- Include both `up` and `down` (rollback) SQL
- Test migrations against a copy of production data before deploying
- Keep migrations small and reversible

```sql
-- +goose Up
ALTER TABLE users ADD COLUMN phone VARCHAR(20);

-- +goose Down
ALTER TABLE users DROP COLUMN phone;
```

Run migrations at startup or as a separate step, not both:

```go
// ✅ Good — separate migration command
// cmd/migrate/main.go runs migrations
// cmd/server/main.go starts the server

// ❌ Bad — migrations in server startup
func main() {
    runMigrations(db) // blocks startup, risky in multi-instance deploys
    startServer()
}
```
