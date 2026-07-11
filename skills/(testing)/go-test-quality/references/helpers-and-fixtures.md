# Test Helpers, Fixtures, and Golden Files

Full implementations for the rules summarized in SKILL.md.

## Helpers with `t.Helper()`

`t.Helper()` makes failure messages point to the caller, not the helper:

```go
func createTestUser(t *testing.T, svc *UserService, name string) *User {
    t.Helper()
    user, err := svc.Create(context.Background(), CreateUserInput{
        Name:  name,
        Email: name + "@test.com",
    })
    require.NoError(t, err)
    return user
}
```

## Factory Functions with Functional Options

For complex test objects, avoid a constructor with 15 parameters.
Use defaults with overrides:

```go
func newTestOrder(t *testing.T, opts ...func(*Order)) *Order {
    t.Helper()
    o := &Order{
        ID:        uuid.New(),
        UserID:    uuid.New(),
        Status:    OrderStatusPending,
        Total:     9999, // $99.99
        CreatedAt: time.Now(),
    }
    for _, opt := range opts {
        opt(o)
    }
    return o
}

// Usage — only override what matters for THIS test
func TestOrder_Cancel_RejectsShippedOrders(t *testing.T) {
    order := newTestOrder(t, func(o *Order) {
        o.Status = OrderStatusShipped
    })

    err := order.Cancel()
    require.ErrorIs(t, err, ErrCannotCancelShipped)
}
```

## Cleanup with `t.Cleanup`

Prefer `t.Cleanup` over `defer` — it runs even if the test calls
`t.FailNow()`, and it's scoped to the test, not the function:

```go
func setupTestDB(t *testing.T) *sql.DB {
    t.Helper()
    db, err := sql.Open("postgres", testDSN)
    require.NoError(t, err)

    t.Cleanup(func() {
        db.Close()
    })
    return db
}
```

## Golden File Testing

For complex outputs (JSON responses, HTML, SQL queries, protobuf),
comparing against golden files is more maintainable than inline
assertions:

```go
var update = flag.Bool("update", false, "update golden files")

func TestRenderInvoice(t *testing.T) {
    invoice := buildTestInvoice()

    got, err := RenderInvoice(invoice)
    require.NoError(t, err)

    golden := filepath.Join("testdata", t.Name()+".golden")

    if *update {
        // Run: go test -update  to regenerate golden files
        require.NoError(t, os.WriteFile(golden, got, 0644))
    }

    want, err := os.ReadFile(golden)
    require.NoError(t, err)
    assert.Equal(t, string(want), string(got))
}
```

Golden files live in `testdata/` directories (which `go build` ignores).
Commit them to git — they ARE the expected output. Review diffs in PRs.

## Interface-Based Mocks

Preferred for small interfaces (≤3 methods). A struct with function
fields plus recorded calls:

```go
type mockNotifier struct {
    sendFunc func(ctx context.Context, to, msg string) error
    sent     []string
}

func (m *mockNotifier) Send(ctx context.Context, to, msg string) error {
    m.sent = append(m.sent, to)
    if m.sendFunc != nil {
        return m.sendFunc(ctx, to, msg)
    }
    return nil
}
```

## Function Injection for Simple Seams

```go
type Service struct {
    now    func() time.Time
    randID func() string
}

// Production: svc := &Service{now: time.Now, randID: uuid.NewString}
// Test:       svc := &Service{now: fixedTime, randID: func() string { return "abc" }}
```

## What NOT to Mock

- Value objects and pure functions — just call them
- The standard library — test the real `json.Marshal`, not a mock
- Your own code in the same package — test the real thing
