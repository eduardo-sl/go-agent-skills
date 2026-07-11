# HTTP, Integration, and Fuzz Testing

Full implementations for the test types summarized in SKILL.md.

## HTTP Handler Testing with `httptest.NewRecorder`

Unit-style handler tests with a mock store:

```go
func TestUserHandler_GetByID(t *testing.T) {
    store := &mockUserStore{
        getByIDFunc: func(ctx context.Context, id string) (*User, error) {
            if id == "123" {
                return &User{ID: "123", Name: "Alice"}, nil
            }
            return nil, ErrNotFound
        },
    }
    handler := NewUserHandler(store, slog.New(slog.NewTextHandler(io.Discard, nil)))

    t.Run("returns user as JSON", func(t *testing.T) {
        req := httptest.NewRequest(http.MethodGet, "/users/123", nil)
        req.SetPathValue("id", "123")

        rec := httptest.NewRecorder()
        handler.HandleGet(rec, req)

        assert.Equal(t, http.StatusOK, rec.Code)
        assert.Contains(t, rec.Header().Get("Content-Type"), "application/json")

        var body map[string]string
        require.NoError(t, json.Unmarshal(rec.Body.Bytes(), &body))
        assert.Equal(t, "Alice", body["name"])
    })

    t.Run("returns 404 for unknown user", func(t *testing.T) {
        req := httptest.NewRequest(http.MethodGet, "/users/unknown", nil)
        req.SetPathValue("id", "unknown")

        rec := httptest.NewRecorder()
        handler.HandleGet(rec, req)

        assert.Equal(t, http.StatusNotFound, rec.Code)
    })
}
```

## Full Server Test with `httptest.NewServer`

Exercises real routing and middleware:

```go
func TestAPI_CreateUser_Integration(t *testing.T) {
    if testing.Short() {
        t.Skip("skipping integration test")
    }

    app := setupApp(t)
    srv := httptest.NewServer(app.Router())
    t.Cleanup(srv.Close)

    resp, err := http.Post(srv.URL+"/api/v1/users",
        "application/json",
        strings.NewReader(`{"name":"Alice","email":"alice@test.com"}`))
    require.NoError(t, err)
    defer resp.Body.Close()

    assert.Equal(t, http.StatusCreated, resp.StatusCode)
}
```

## Integration Tests with Testcontainers

Real database behavior against a disposable container:

```go
func TestPostgresUserStore(t *testing.T) {
    if testing.Short() {
        t.Skip("skipping integration test")
    }

    ctx := context.Background()
    pg, err := postgres.Run(ctx,
        "postgres:16-alpine",
        postgres.WithDatabase("testdb"),
        postgres.WithUsername("test"),
        postgres.WithPassword("test"),
        testcontainers.WithWaitStrategy(
            wait.ForLog("database system is ready").
                WithOccurrence(2).
                WithStartupTimeout(30*time.Second),
        ),
    )
    require.NoError(t, err)
    t.Cleanup(func() { pg.Terminate(ctx) })

    connStr, err := pg.ConnectionString(ctx, "sslmode=disable")
    require.NoError(t, err)

    store, err := NewPostgresStore(connStr)
    require.NoError(t, err)

    t.Run("create and retrieve user", func(t *testing.T) {
        created, err := store.Create(ctx, &User{Name: "Alice"})
        require.NoError(t, err)

        fetched, err := store.GetByID(ctx, created.ID)
        require.NoError(t, err)
        assert.Equal(t, "Alice", fetched.Name)
    })
}
```

Separate with build tags: `//go:build integration`

Run with: `go test -tags=integration -count=1 ./...`

## TestMain for Shared Setup

Use when ALL tests in a package need expensive one-time setup:

```go
var testDB *sql.DB

func TestMain(m *testing.M) {
    var teardown func()
    testDB, teardown = setupTestDatabase()

    code := m.Run()

    teardown()
    os.Exit(code)
}
```

Use sparingly — most tests don't need it.

## Fuzz Testing (Go 1.18+)

Fuzz tests discover edge cases you'd never think of. Use for parsers,
validators, serializers — anything that takes arbitrary input:

```go
func FuzzParseEmail(f *testing.F) {
    f.Add("alice@example.com")
    f.Add("")
    f.Add("@")

    f.Fuzz(func(t *testing.T, input string) {
        result, err := ParseEmail(input)
        if err != nil {
            return // invalid input is fine, just don't panic
        }

        // Round-trip: parsing the output should give the same result
        reparsed, err := ParseEmail(result.String())
        require.NoError(t, err)
        assert.Equal(t, result, reparsed)
    })
}
```

Run with: `go test -fuzz=FuzzParseEmail -fuzztime=30s`

If your function can receive untrusted input, fuzz it.

## Coverage Commands

```bash
go test -coverprofile=coverage.out ./...
go tool cover -html=coverage.out -o coverage.html
go tool cover -func=coverage.out
```
