# Refactoring Bloated Table Tests

Before/after rewrites for the smells summarized in SKILL.md.

## Smell: Setup Functions Inside the Struct

If each case needs different mocks, different state, or different
dependencies, the table is just hiding complexity behind function fields:

```go
// ❌ Bad — table test with branching setup
tests := []struct {
    name         string
    setupMock    func(*mockStore)     // each case wires differently
    setupAuth    func(*mockAuth)      // more per-case wiring
    input        Request
    wantStatus   int
    shouldNotify bool                 // branching assertion
}{...}

for _, tt := range tests {
    t.Run(tt.name, func(t *testing.T) {
        store := &mockStore{}
        tt.setupMock(store)          // hiding logic inside functions
        auth := &mockAuth{}
        tt.setupAuth(auth)
        // ... 20 lines of conditional assertions
    })
}
```

Write separate subtests instead — they're longer but honest:

```go
// ✅ Good — explicit subtests for different scenarios
func TestOrderHandler_Create(t *testing.T) {
    t.Run("succeeds with valid order", func(t *testing.T) {
        store := &mockStore{createFunc: func(...) (*Order, error) {
            return &Order{ID: "1"}, nil
        }}
        handler := NewHandler(store)
        // ... clear, readable, self-contained
    })

    t.Run("returns 401 when unauthenticated", func(t *testing.T) {
        handler := NewHandler(&mockStore{})
        // ... different setup, different assertions
    })
}
```

## Smell: Fewer Than 3 Cases

Two cases don't need a table. The overhead of defining the struct is
more code than just writing two tests:

```go
// ❌ Overkill for 2 cases
tests := []struct {
    name    string
    input   string
    wantErr bool
}{
    {"valid", "hello", false},
    {"empty", "", true},
}

// ✅ Just write them
func TestValidate_AcceptsNonEmptyString(t *testing.T) {
    require.NoError(t, Validate("hello"))
}

func TestValidate_RejectsEmptyString(t *testing.T) {
    require.Error(t, Validate(""))
}
```

## Smell: The Loop Body Became a Mini-Program

The entire point of a table test is that the execution logic is
identical for every case:

```go
// ✅ Good — loop body is 5 lines
for _, tt := range tests {
    t.Run(tt.name, func(t *testing.T) {
        got, err := Process(tt.input)
        require.NoError(t, err)
        assert.Equal(t, tt.want, got)
    })
}

// ❌ Bad — loop body has become a mini-program
for _, tt := range tests {
    t.Run(tt.name, func(t *testing.T) {
        if tt.setupDB {
            db := setupDB(t)
            defer db.Close()
        }
        svc := NewService()
        if tt.withCache { svc.EnableCache() }
        got, err := svc.Process(tt.input)
        if tt.wantErr {
            require.Error(t, err)
            if tt.wantErrMsg != "" { assert.Contains(t, err.Error(), tt.wantErrMsg) }
            return
        }
        // ... more conditionals, more branches
    })
}
```

If your loop body has `if tt.shouldError` / `if tt.expectNotification` /
`if tt.wantRedirect` — you've outgrown the table. Each branch is a
different test pretending to share a structure. Split by scenario:

1. Group cases by which branch of the loop body they exercise.
2. Create one test function per group, named after the scenario
   (`TestProcess_WithCache`, `TestProcess_ErrorPaths`).
3. Keep a table inside each group only if 3+ cases remain and the
   loop body becomes branch-free.

## Symptom → Fix Table

| Symptom | Fix |
|---|---|
| Struct has 8+ fields | Split into multiple test functions by scenario |
| `setupFunc` field in struct | Extract to separate subtests with explicit setup |
| `if tt.shouldX` in loop body | Each branch is a different test — split it |
| Same 3 fields identical in every case | Move to shared setup outside the table |
| Test name is the only way to understand the case | The case is too complex for a table |
| Adding a case requires understanding all other cases | Table has grown beyond its useful life |
