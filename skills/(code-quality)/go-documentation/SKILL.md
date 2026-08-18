---
name: go-documentation
description: >
  Go documentation conventions: godoc comments, package docs, testable
  Example functions, deprecation notices, and doc links. Use when: "add
  godoc", "document this package", "write doc comments", "add examples to
  docs", "deprecate a function", "package documentation", "improve the
  docs".
  Not for: commit messages (git-commit), README-level guides (plain writing
  task), code style (go-coding-standards).
user-invocable: true
license: MIT
compatibility: Designed for Claude Code or similar AI coding agents working on Go projects. Requires the Go toolchain.
allowed-tools: Read Edit Write Glob Grep Bash(go:*) Bash(gofmt:*)
metadata:
  author: eduardo-sl
  version: "1.1.1"
---

# Go Documentation

Godoc is not free-form prose — it's a convention the toolchain renders.
Comments that follow the convention become browsable documentation on
pkg.go.dev; comments that don't become noise.

## 1. Doc Comment Form

Every exported identifier gets a doc comment. It starts with the
identifier's name and is a complete sentence:

```go
// ✅ Good
// ParseDuration parses a duration string such as "300ms" or "2h45m".
// It returns an error if the string is not a valid duration.
func ParseDuration(s string) (Duration, error) { ... }

// ❌ Bad — doesn't start with the name, fragment, restates signature
// this function parses durations
func ParseDuration(s string) (Duration, error) { ... }
```

- Groups of related constants/variables may share one comment on the
  block: `// Common HTTP methods.` above the `const (...)` group.
- Unexported identifiers: comment when the purpose isn't obvious from
  the name — same form, no obligation.
- Say what the caller needs: behavior, error conditions, nil/zero-value
  handling, concurrency safety. Not the implementation.

## 2. Package Documentation

One package comment per package, on the `package` clause. For more than
a few sentences, put it in a dedicated `doc.go`:

```go
// Package retry implements backoff strategies for retrying failed
// operations.
//
// The zero value of Policy retries three times with exponential
// backoff. Use functional options to customize:
//
//	p := retry.NewPolicy(retry.WithMaxAttempts(5))
//	err := p.Do(ctx, fetchUser)
package retry
```

- Begins with "Package <name> ...".
- Indented lines (one tab) render as code blocks.
- `main` packages: the comment describes the command and its flags —
  it becomes the command's documentation.

## 3. Doc Links and Formatting (Go 1.19+)

```go
// Fetch retrieves the resource. It honors the deadline of ctx and
// returns [ErrNotFound] if the resource does not exist.
//
// For batch retrieval use [Client.FetchAll]. See the [net/http]
// package for transport configuration.
func (c *Client) Fetch(ctx context.Context, id string) (*Resource, error)
```

- `[Name]`, `[Type.Method]`, `[pkg/path]` become hyperlinks on pkg.go.dev.
- A line starting with `# ` is a heading (rare; only in long package docs).
- Lists: lines starting with a space and a bullet. Keep them shallow.

## 4. Testable Examples

Example functions are documentation the compiler checks. Put them in
`example_test.go` in the `<pkg>_test` package:

```go
func ExampleParseDuration() {
    d, _ := ParseDuration("1h30m")
    fmt.Println(d.Minutes())
    // Output: 90
}

// Method example: ExampleType_Method
func ExamplePolicy_Do() { ... }

// Second example for the same symbol: suffix
func ExampleParseDuration_negative() { ... }
```

- The `// Output:` comment makes it a test — `go test` fails if the
  printed output differs. Examples without it compile but don't run.
- Write an example for every non-trivial exported API. It renders
  directly under the symbol on pkg.go.dev.

## 5. Deprecation

```go
// Fetch retrieves the resource.
//
// Deprecated: Use [Client.FetchContext] instead, which honors
// context cancellation.
func (c *Client) Fetch(id string) (*Resource, error)
```

- The paragraph must start exactly with `Deprecated: `.
- Always name the replacement.
- Tools (gopls, staticcheck, pkg.go.dev) surface these automatically.

## 6. What NOT to Write

```go
// ❌ Noise — restates the code
// GetName returns the name.
func (u *User) GetName() string { return u.name }

// ❌ Maintenance history — belongs in git
// Changed 2024-03-01 by alice: added caching.

// ❌ Commented-out code kept "for reference"
```

If a doc comment can only restate the signature, improve the name until
the comment says something the signature can't — or accept a minimal
comment for symmetry in a fully documented API.

## Executable Verification

```bash
go vet ./...                  # flags some malformed doc comments
gofmt -l .                    # Go 1.19+ gofmt normalizes doc comments
go test ./...                 # runs Example functions with Output
go doc ./mypkg Symbol         # render what users will actually see
```

For a browsable preview, run a local pkgsite if available:
`go run golang.org/x/pkgsite/cmd/pkgsite@latest` and open the module.

## Verification Checklist

1. Every exported identifier has a doc comment starting with its name
2. Package has a package comment ("Package <name> ..."), in doc.go if long
3. Error conditions and nil/zero-value behavior documented for exported APIs
4. Concurrency safety stated where callers could guess wrong
5. `[Symbol]` doc links used instead of bare names in running text
6. Non-trivial exported APIs have Example functions with `// Output:`
7. Deprecations use the exact `Deprecated: ` form and name a replacement
8. No comments restating signatures, tracking history, or holding dead code
9. `go test ./...` passes with examples enabled
