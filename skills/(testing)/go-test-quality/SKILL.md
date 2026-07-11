---
name: go-test-quality
description: >
  Go testing patterns for production-grade code: subtests, test helpers, fixtures,
  golden files, httptest, testcontainers, property-based testing, and fuzz testing.
  Covers mocking strategies, test isolation, coverage analysis, and test design philosophy.
  Use when writing tests, improving coverage, reviewing test quality,
  setting up test infrastructure, or choosing a testing approach.
  Trigger examples: "add tests", "improve coverage", "write tests for this",
  "test helpers", "mock this dependency", "integration test", "fuzz test".
  Do NOT use for performance benchmarking methodology (use go-performance-review),
  security testing (use go-security-audit), or table-driven test patterns
  specifically (use go-test-table-driven).
license: MIT
metadata:
  version: "1.1.0"
---

# Go Test Quality

Tests are production code. They run in CI on every commit, they document behavior,
and they're the first thing you read when a function breaks at 3am.
Write them with the same care you'd give to code that handles money.

Detailed reference material, loaded on demand:

- `references/helpers-and-fixtures.md` — test helpers, factory functions
  with options, `t.Cleanup`, golden files, mock implementations.
- `references/integration-testing.md` — httptest recorder and server,
  testcontainers, build tags, `TestMain`, fuzz testing.

Read a reference file only when the summary below is not enough.

## 1. Test Design Philosophy

### Test behavior, not implementation

```go
// ✅ Good — tests what the function DOES
func TestTransferFunds_InsufficientBalance(t *testing.T) {
    from := NewAccount("alice", 100)
    to := NewAccount("bob", 0)

    err := TransferFunds(from, to, 150)

    require.ErrorIs(t, err, ErrInsufficientFunds)
    assert.Equal(t, 100, from.Balance(), "sender balance should be unchanged")
    assert.Equal(t, 0, to.Balance(), "receiver balance should be unchanged")
}

// ❌ Bad — tests HOW the function does it
// asserts debit() was called before credit(), rollback() was called,
// internal mutex was locked — breaks on every refactor
```

### One assertion per logical concept

Multiple `assert` calls are fine when they verify different facets of the
SAME behavior (both accounts after a transfer). A test that checks creation
AND update AND deletion is three tests pretending to be one.

### Name tests like bug reports

When the test fails, the name alone should say what broke:

```go
// ✅ Good — reads like a sentence
func TestOrderService_Cancel_RefundsPartiallyShippedItems(t *testing.T) { ... }
func TestParseConfig_ReturnsErrorOnMissingRequiredField(t *testing.T) { ... }

// ❌ Bad — says nothing useful
func TestCancel(t *testing.T) { ... }
func TestRateLimiter_Success(t *testing.T) { ... }
```

## 2. Subtests for Organized Scenarios

Use `t.Run` to group related scenarios under a parent test. Each subtest
gets its own setup, its own failure, and its own name in CI output:

```go
func TestUserService_Create(t *testing.T) {
    svc := setupUserService(t)

    t.Run("succeeds with valid input", func(t *testing.T) {
        user, err := svc.Create(ctx, CreateUserInput{Name: "Alice", Email: "alice@example.com"})
        require.NoError(t, err)
        assert.NotEmpty(t, user.ID)
    })

    t.Run("rejects duplicate email", func(t *testing.T) {
        _, _ = svc.Create(ctx, CreateUserInput{Name: "Alice", Email: "taken@example.com"})
        _, err := svc.Create(ctx, CreateUserInput{Name: "Bob", Email: "taken@example.com"})
        require.ErrorIs(t, err, ErrDuplicateEmail)
    })
}
```

## 3. Test Helper Rules

1. **Always call `t.Helper()`** in test utilities so failures point to the
   caller, not the helper.
2. **Factory functions with functional options** for complex test objects —
   defaults with per-test overrides, never a 15-parameter constructor.
3. **Prefer `t.Cleanup` over `defer`** — it runs even after `t.FailNow()`
   and is scoped to the test, not the function.

Full implementations in `references/helpers-and-fixtures.md`.

## 4. Choosing the Test Type

| Situation | Approach | Details |
|---|---|---|
| Pure function, 3+ data cases | Table-driven test | go-test-table-driven skill |
| HTTP handler in isolation | `httptest.NewRecorder` + mock store | `references/integration-testing.md` |
| Full routing/middleware stack | `httptest.NewServer` | `references/integration-testing.md` |
| Real database behavior | testcontainers + build tags | `references/integration-testing.md` |
| Complex output (JSON, HTML, SQL) | Golden files in `testdata/` | `references/helpers-and-fixtures.md` |
| Parser/validator on untrusted input | Fuzz test | `references/integration-testing.md` |

## 5. Mocking Rules

- **Interface-based hand-written mocks** for small interfaces (≤3 methods):
  a struct with function fields plus recorded calls.
- **Function injection** for simple seams (`now func() time.Time`).
- **Do NOT mock:** value objects, pure functions, the standard library, or
  your own code in the same package. Test the real thing.
- If you mock everything, you're testing your mocks, not your code.

## 6. Parallelism and Coverage

```go
func TestSlugify(t *testing.T) {
    t.Parallel() // safe: pure function, no shared state
    // ...
}
```

Do NOT use `t.Parallel()` when tests share mutable state, databases,
files, or process-level state (`os.Setenv`).

```bash
go test -race -coverprofile=coverage.out ./...
go tool cover -func=coverage.out
```

**Targets:** business logic 80%+, critical paths (auth, payments) 95%+,
handlers 70%+. Don't chase 100% on generated code and simple getters.

## Anti-Patterns

- 🔴 Test with no assertions — always passes, proves nothing
- 🔴 `time.Sleep` for synchronization — use channels or polling
- 🔴 Test depends on execution order — each test must stand alone
- 🔴 Mocking everything — you end up testing your mocks, not your code
- 🟡 Test names like `Test1`, `TestSuccess` — name the scenario
- 🟡 Reaching into private fields — test through the public API
- 🟡 No edge cases: empty, nil, zero, max values, unicode
- 🟡 Giant shared setup — each test should set up only what it needs
- 🟢 Fuzz anything that takes untrusted input
- 🟢 Golden files for complex output comparisons

## Verification Checklist

1. Every test has meaningful assertions (no empty test bodies)
2. Test names describe the scenario, not the method
3. `t.Helper()` called in every test utility function
4. `t.Cleanup()` used for resource teardown
5. `t.Parallel()` used where safe, avoided where not
6. Integration tests guarded with `testing.Short()` or build tags
7. Mocks are minimal — only mock external dependencies
8. Edge cases covered: empty, nil, zero, boundary values
9. `go test -race ./...` passes
10. Coverage is meaningful, not just high numbers
