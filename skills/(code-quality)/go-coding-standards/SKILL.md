---
name: go-coding-standards
description: >
  Go coding standards and style conventions grounded in Effective Go, Go
  Code Review Comments, and production-proven idioms. Use when writing or
  reviewing Go code, enforcing naming conventions, import ordering, variable
  declarations, struct initialization, or formatting rules. Trigger
  examples: "check Go style", "fix formatting", "review naming", "Go
  conventions".
  Not for: architecture (go-architecture-review), concurrency
  (go-concurrency-review), performance tuning (go-performance-review).
user-invocable: true
license: MIT
compatibility: Designed for Claude Code or similar AI coding agents working on Go projects. Requires the Go toolchain. golangci-lint is optional.
allowed-tools: Read Edit Write Glob Grep Bash(go:*) Bash(gofmt:*) Bash(golangci-lint:*)
metadata:
  author: eduardo-sl
  version: "1.3.3"
---

# Go Coding Standards

Idiomatic Go conventions grounded in Effective Go, Go Code Review Comments, and production-proven idioms.
All code MUST pass `goimports`, `go vet`, and `staticcheck` (or `golangci-lint run`) without errors.

Detailed reference material, loaded on demand:

- `references/file-organization.md` — declaration grouping, file order,
  breaking long signatures.
- `references/receivers-and-tags.md` — receiver consistency and struct tag
  examples.

Read a reference file only when the summary below is not enough.

## 1. Import Ordering

Group imports in this order, separated by blank lines:

```go
import (
    // 1. Standard library
    "context"
    "fmt"
    "log/slog"
    "net/http"

    // 2. External packages
    "github.com/gorilla/mux"

    // 3. Internal/project packages
    "github.com/myorg/myproject/internal/service"
)
```

NEVER use dot imports. Use aliasing only to resolve conflicts.

## 2. Naming Conventions

### Packages
- Short, lowercase, single-word names. No underscores, no camelCase.
- Name should describe what the package *provides*, not what it *contains*.
- Avoid generic names: `util`, `common`, `helpers`, `misc`, `base`.

### Functions & Methods
- MixedCaps (exported) or mixedCaps (unexported). No underscores except in test files.
- Getters: use `Name()`, NOT `GetName()`. Setters: use `SetName()`.
- Constructors: `NewFoo()` returns `*Foo`. If only one type in package: `New()`.

### Variables
- Short names in tight scopes: `i`, `n`, `err`, `ctx`.
- Descriptive names for wider scopes: `userCount`, `retryTimeout`.
- Prefix unexported package-level globals with `_`: `var _defaultTimeout = 5 * time.Second`.
- Do NOT shadow built-in identifiers (`error`, `len`, `cap`, `new`, `make`, `close`).

### Interfaces
- Single-method interfaces: method name + `-er` suffix (`Reader`, `Writer`, `Closer`).
- Define interfaces where they are *consumed*, not where they are *implemented*.

## 3. Variable Declarations

### Top-level
Use `var` for top-level declarations. Do NOT specify type when it matches the expression:

```go
// ✅ Good
var _defaultPort = 8080
var _logger = slog.Default()

// ❌ Bad — redundant type
var _defaultPort int = 8080
```

### Local
- Prefer `:=` for local variables.
- Use `var` only when zero-value initialization is intentional and meaningful.

```go
// ✅ Good — zero value is meaningful
var buf bytes.Buffer

// ✅ Good — short declaration
name := getUserName()
```

## 4. Struct Initialization

ALWAYS use field names. Never rely on positional initialization:

```go
// ✅ Good
user := User{
    Name:  "Alice",
    Email: "alice@example.com",
    Age:   30,
}

// ❌ Bad — positional, breaks on field reordering
user := User{"Alice", "alice@example.com", 30}
```

Omit zero-value fields unless clarity requires them:

```go
// ✅ Good — zero values omitted
user := User{
    Name: "Alice",
}
```

## 5. Reduce Nesting

Handle errors and special cases first with early returns, so the happy
path stays at the left margin. Drop an `else` whose `if` already returns,
and prefer assign-default-then-override:

```go
// ✅ Good — guard clauses; no else
for _, v := range data {
    if !v.IsValid() {
        continue
    }
    if err := v.Process(); err != nil {
        return fmt.Errorf("process %s: %w", v.ID, err)
    }
}

a := 10 // default, then override
if condition {
    a = 20
}
```

## 6. Grouping and Ordering

- Group related `const` and `var` declarations in one parenthesized block.
- File order: constants and variables, constructors, exported methods
  (by importance, not alphabetically), unexported methods, helpers.
- Methods sit directly after the type they belong to.

## 7. Line Length

Soft limit of 99 characters. Break a long signature one parameter per
line, closing parenthesis on its own line. Examples:
`references/file-organization.md`.

## 8. Defer Usage

Use `defer` for cleanup. It makes intent clear at the point of acquisition:

```go
mu.Lock()
defer mu.Unlock()

f, err := os.Open(path)
if err != nil {
    return err
}
defer f.Close()
```

## 9. Enums

Reserve the zero value for an explicit `Unknown` sentinel, so a value that
was never set cannot pass for a real state:

```go
type Status int

const (
    StatusUnknown Status = iota
    StatusActive
    StatusInactive
)
```

## 10. Use `time` Package Properly

- Use `time.Duration` for durations, NOT raw integers.
- Use `time.Time` for instants. Use `time.Since(start)` instead of `time.Now().Sub(start)`.
- External APIs: accept `int` or `float64` and convert internally.

```go
// ✅ Good
func poll(interval time.Duration) { ... }
poll(10 * time.Second)

// ❌ Bad
func poll(intervalSecs int) { ... }
poll(10)
```

## 11. Receivers

Pick one receiver kind per type and use it on every method — a mixed
method set changes with how the value is held. Use a pointer receiver if
any method mutates, the struct holds a `sync.Mutex` or other no-copy
field, the struct is large, or another method already needs a pointer.
Use a value receiver for small immutable types. Name the receiver one or
two letters after the type (`s *Server`), the same on every method, never
`this` or `self`. Examples: `references/receivers-and-tags.md`.

## 12. Struct Tags

The compiler does not check tags, so a typo is silent.

- Tag every field of a type that crosses a serialization boundary, even
  when the name already matches.
- `json:"-"` for anything that must never leave the process — an
  unexported field is skipped silently, which reads as an oversight.
- `omitempty` cannot tell "absent" from "zero"; use a pointer or wrapper
  when that distinction matters.
- Run `go vet` — its `structtag` check catches malformed tags.

## Verification Checklist

Before considering code complete:
1. `goimports` runs clean
2. `go vet ./...` passes
3. `golangci-lint run` passes (if configured)
4. No shadowed built-in identifiers
5. All imports properly grouped and ordered
6. Struct initializations use field names
7. No unnecessary nesting or else blocks
8. Receiver kind is consistent across every method on a type
9. Every serialised struct field carries an explicit tag
