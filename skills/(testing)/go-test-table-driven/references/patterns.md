# Table-Driven Test Patterns

Worked examples for the rules summarized in SKILL.md.

## Canonical Table

```go
func TestFormatCurrency(t *testing.T) {
    tests := []struct {
        name     string
        cents    int64
        currency string
        want     string
    }{
        {
            name:     "USD whole dollars",
            cents:    1000,
            currency: "USD",
            want:     "$10.00",
        },
        {
            name:     "USD with cents",
            cents:    1050,
            currency: "USD",
            want:     "$10.50",
        },
        {
            name:     "EUR formatting",
            cents:    999,
            currency: "EUR",
            want:     "€9.99",
        },
        {
            name:     "zero amount",
            cents:    0,
            currency: "USD",
            want:     "$0.00",
        },
        {
            name:     "negative amount",
            cents:    -500,
            currency: "USD",
            want:     "-$5.00",
        },
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            got := FormatCurrency(tt.cents, tt.currency)
            assert.Equal(t, tt.want, got)
        })
    }
}
```

## Removing Constants from the Struct

Every field should change between at least 2 cases. If a field has the
same value in all cases, it's not a variable — it's setup:

```go
// ❌ Bad — userRole is "admin" in every case
tests := []struct {
    name     string
    userRole string  // always "admin"
    input    string
    want     string
}{
    {"case1", "admin", "a", "A"},
    {"case2", "admin", "b", "B"},
}

// ✅ Good — remove constants from the struct
func TestAdminFormatter(t *testing.T) {
    ctx := contextWithRole("admin") // shared setup, outside table

    tests := []struct {
        name  string
        input string
        want  string
    }{
        {"case1", "a", "A"},
        {"case2", "b", "B"},
    }
    // ...
}
```

## Naming the `name` Field

The `name` field appears in test output. Make it a short sentence that
explains the scenario, not a label:

```go
// ✅ Good names
{name: "trims leading whitespace"},
{name: "returns error for negative amount"},
{name: "handles unicode characters"},

// ❌ Bad names
{name: "case1"},
{name: "success"},
{name: "test with special chars"},
```

## `wantErr` Boolean

```go
tests := []struct {
    name    string
    input   string
    want    int
    wantErr bool
}{
    {name: "valid number", input: "42", want: 42},
    {name: "empty string", input: "", wantErr: true},
    {name: "not a number", input: "abc", wantErr: true},
}

for _, tt := range tests {
    t.Run(tt.name, func(t *testing.T) {
        got, err := ParseInt(tt.input)
        if tt.wantErr {
            require.Error(t, err)
            return
        }
        require.NoError(t, err)
        assert.Equal(t, tt.want, got)
    })
}
```

## `wantErrIs` with Sentinel Errors

When callers must detect a specific error, use a `wantErrIs` field with
a sentinel error, not just a boolean:

```go
tests := []struct {
    name      string
    id        string
    wantErrIs error // nil means no error expected
}{
    {name: "valid id", id: "123"},
    {name: "empty id", id: "", wantErrIs: ErrInvalidID},
    {name: "not found", id: "999", wantErrIs: ErrNotFound},
}

for _, tt := range tests {
    t.Run(tt.name, func(t *testing.T) {
        _, err := store.GetByID(ctx, tt.id)
        if tt.wantErrIs != nil {
            require.ErrorIs(t, err, tt.wantErrIs)
            return
        }
        require.NoError(t, err)
    })
}
```

## Parallel Tables and Loop Variable Capture

```go
for _, tt := range tests {
    t.Run(tt.name, func(t *testing.T) {
        t.Parallel()
        got := Transform(tt.input)
        assert.Equal(t, tt.want, got)
    })
}
```

In Go 1.22+, the loop variable is scoped per iteration, so the old
`tt := tt` capture is unnecessary. For Go <1.22, you still need it:

```go
// Go <1.22 only
for _, tt := range tests {
    tt := tt // capture range variable
    t.Run(tt.name, func(t *testing.T) {
        t.Parallel()
        // ...
    })
}
```

## Aligned Struct Literals for Scanning

```go
tests := []struct {
    name  string
    input string
    want  string
}{
    {"lowercase",           "hello",       "hello"},
    {"uppercase",           "HELLO",       "hello"},
    {"mixed case",          "HeLLo",       "hello"},
    {"with spaces",         "Hello World", "hello world"},
    {"already lowercase",   "test",        "test"},
}
```

This works for simple cases. For complex structs, use the multi-line
format:

```go
tests := []struct {
    name   string
    config Config
    want   string
}{
    {
        name: "default timeout",
        config: Config{
            Host:    "localhost",
            Timeout: 0, // should get default
        },
        want: "localhost:8080",
    },
    {
        name: "custom port",
        config: Config{
            Host: "localhost",
            Port: 9090,
        },
        want: "localhost:9090",
    },
}
```

## Map-Based Tables

When the struct would just be `{name, input, want}`:

```go
func TestStatusText(t *testing.T) {
    cases := map[string]struct {
        code int
        want string
    }{
        "ok":           {200, "OK"},
        "not found":    {404, "Not Found"},
        "server error": {500, "Internal Server Error"},
    }

    for name, tc := range cases {
        t.Run(name, func(t *testing.T) {
            assert.Equal(t, tc.want, StatusText(tc.code))
        })
    }
}
```

Note: map iteration order is random, so this also stress-tests that
your cases are truly independent.

## Error-Only Tables

When testing a validator and only caring about which inputs fail, two
simple slices beat a struct:

```go
func TestValidateEmail(t *testing.T) {
    valid := []string{
        "user@example.com",
        "user+tag@example.com",
        "user@sub.domain.com",
    }
    for _, email := range valid {
        t.Run("valid/"+email, func(t *testing.T) {
            require.NoError(t, ValidateEmail(email))
        })
    }

    invalid := []string{
        "",
        "@",
        "user@",
        "@domain.com",
        "user space@example.com",
    }
    for _, email := range invalid {
        t.Run("invalid/"+email, func(t *testing.T) {
            require.Error(t, ValidateEmail(email))
        })
    }
}
```

The test name includes the input value, so failures are self-documenting.
