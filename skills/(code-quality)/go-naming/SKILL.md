---
name: go-naming
description: >
  Go naming conventions for packages, files, types, functions, methods,
  receivers, variables, constants, errors, acronyms and tests, grounded in
  Effective Go and Go Code Review Comments. Use when: "what should I name
  this", "name this package", "naming review", "is this name idiomatic",
  "stuttering names", "Get prefix", "acronym casing", "error variable name",
  "receiver name".
  Not for: formatting, imports and declarations (go-coding-standards),
  carrying out a rename across the codebase (go-semantic-tools,
  go-refactoring).
user-invocable: true
license: MIT
compatibility: Designed for Claude Code or similar AI coding agents working on Go projects. Requires the Go toolchain.
allowed-tools: Read Edit Write Glob Grep Bash(go:*) Bash(gofmt:*)
metadata:
  author: eduardo-sl
  version: "1.0.0"
---

# Go Naming

In Go the package name is part of every call site, capitalization decides
visibility, and short names are the norm. A good name reads well *where it
is used*, not where it is declared.

> Community default. A project skill or agent-config rule that explicitly
> supersedes `go-naming` takes precedence over this one.

Detailed reference material, loaded on demand:

- `references/examples.md` — before/after renames for every rule below,
  including the initialism and stuttering edge cases.

Read a reference file only when the summary below is not enough.

## 1. Quick Reference

| Element | Convention | Example |
|---|---|---|
| Package | short, lowercase, one word, singular | `order`, `httpsign`, `postgres` |
| File | lowercase, `_` allowed, named after its main type or concern | `order_service.go`, `order_service_test.go` |
| Exported identifier | `MixedCaps` | `ParseToken`, `MaxRetries` |
| Unexported identifier | `mixedCaps` | `parseToken`, `maxRetries` |
| Initialism | all one case | `URL`, `userID`, `ServeHTTP`, `xmlParser` |
| Getter / setter | `Owner()` / `SetOwner()` | never `GetOwner()` |
| Constructor | `New` for the package's main type, `NewThing` otherwise | `ring.New`, `http.NewRequest` |
| Panicking variant | `Must` prefix | `template.Must`, `regexp.MustCompile` |
| Functional option | `With` + setting | `WithTimeout`, `WithLogger` |
| One-method interface | method + `-er` | `Reader`, `Notifier` |
| Receiver | 1-2 letters, same on every method | `func (s *Server)` |
| Sentinel error | `Err` prefix (`err` unexported) | `ErrNotFound`, `errClosed` |
| Error type | `Error` suffix | `ValidationError` |
| Enum constant | type name prefix, zero = unknown | `StatusUnknown`, `StatusActive` |
| Test | `Test` + function, `Test` + type `_` method | `TestParse`, `TestCache_Get` |

## 2. Packages

- Short, lowercase, single word: no underscores, no `mixedCaps`, no plural
  (`order`, not `orders`).
- Name it after what it *provides*: `retry`, `httpsign`, `postgres`. Never
  `util`, `common`, `helpers`, `misc`, `base`, `models`, `types` — they
  say nothing and collect everything.
- The directory name and the package name match.
- Avoid names callers want for their variables (`url`, `user`, `buf`) when
  the package is imported widely; a call site with `u := user.New()` reads
  better than shadowing the package.

## 3. Don't Stutter

The package name is always present at the call site, so don't repeat it:

```go
// ✅ Good — reads once
http.Client       order.Service     user.New()     config.Load()

// ❌ Bad — says it twice
http.HTTPClient   order.OrderService user.NewUser() config.LoadConfig()
```

The rule covers every exported name in the package, not just the main
type: in package `dbpool`, `Pool`, `Status` and `Option` — not `DBPool`,
`PoolStatus`, `PoolOption`.

## 4. MixedCaps, Initialisms and Constants

- Every identifier is `MixedCaps` or `mixedCaps`. Underscores appear only
  in test names (`TestCache_Get`), generated code, and cgo.
- An initialism keeps one case throughout: `URL`, `ID`, `HTTP`, `JSON`,
  `API` — `userID`, `parseURL`, `ServeHTTP`, `HTTPServer`, `xmlHTTPRequest`.
  Never `UserId`, `ParseUrl`, `HttpServer`.
- Constants are `MixedCaps` like everything else: `MaxRetries`, not
  `MAX_RETRIES` — case already means "exported" in Go.
- Name constants for their role, not their value: `DefaultPort`, not
  `Port8080`.
- Do not shadow predeclared identifiers: `len`, `cap`, `new`, `make`,
  `close`, `copy`, `error`, `string`, `min`, `max`.

## 5. Functions and Methods

- Getters drop `Get`: `u.Name()`, and the setter is `u.SetName()`.
  `Is`/`Has`/`Can` stay on boolean predicates: `IsActive()`.
- Constructors: `New` when the package has one main type, `NewThing`
  otherwise. A constructor that panics on bad input is `MustThing`.
- Canonical names carry a contract. Call a method `Read`, `Write`,
  `Close`, `Flush`, `String`, `Error` or `ServeHTTP` only if it has the
  standard signature and meaning — and if it does, use that name
  (`String()`, never `ToString()`).
- Name for what the caller gets, not how it is computed: `Users()`, not
  `QueryAndBuildUserList()`.
- Format-string variants end in `f`: `Errorf`, `Logf`.

## 6. Variables and Receivers

- Name length grows with scope: `i`, `n`, `err`, `ctx`, `buf` inside a few
  lines; `retryTimeout`, `pendingOrders` across a function; full words at
  package level.
- Don't put the type in the name (`userSlice` → `users`, `nameStr` →
  `name`), and don't repeat context the reader already has (`order.ID`
  inside `type Order`, not `order.OrderID`).
- Receivers are one or two letters from the type (`s *Server`,
  `rw *responseWriter`), the same on every method of the type — never
  `this` or `self`.
- Unexported package-level variables may take a `_` prefix
  (`_defaultTimeout`) to keep them distinct from locals — the Uber style
  convention. Follow whichever the codebase already uses.
- Boolean names read as a question: `isReady`, `hasChildren`, `canRetry`.

## 7. Types and Interfaces

- Types are nouns: `Request`, `FileHeader`, `RetryPolicy`.
- A one-method interface is the method plus `-er`: `Reader`, `Notifier`,
  `Validator`. Never an `I` prefix or `Interface` suffix.
- Name an interface after the behavior the consumer needs, in the
  consumer's package (`orderStore` in the service), not after the
  implementation it happens to have.

## 8. Errors

- Exported sentinels `ErrNotFound`, unexported `errClosed`.
- Error types end in `Error`: `NotFoundError`, `SyntaxError`.
- Error strings are lowercase with no trailing punctuation, prefixed with
  the package or operation: `"order: invalid quantity"`. They get wrapped
  into longer messages, so they must read mid-sentence.

## 9. Enums and Tests

- Enum constants are prefixed with their type and start with an explicit
  `Unknown` at zero: `StatusUnknown`, `StatusActive`, `StatusClosed`.
- Tests: `TestParse`, `TestCache_Get`, `BenchmarkParse`, `ExampleCache_Get`
  (the example name must match a real identifier, or `go vet` complains).
- Subtest names are short lowercase phrases — `"empty input"`,
  `"expired token"` — because `go test -run 'TestParse/empty_input'`
  selects them.

## Applying a Rename

Rename with gopls, not search-and-replace: it follows the type graph and
refuses renames that would break interface satisfaction (the
go-semantic-tools skill). Then grep struct tags, templates and SQL for the
old name — gopls does not see them. Exported names in a published library
need a deprecation cycle (the go-refactoring skill).

## Verification Checklist

1. No package named `util`, `common`, `helpers`, `models`, `types`, `misc` or `base`
2. No exported name repeats its package name
3. Initialisms keep one case (`ID`, `URL`, `HTTP`); no `ALL_CAPS` constants
4. No `Get` prefix on getters; `Must` only on panicking functions
5. Canonical method names (`String`, `Read`, `Close`, …) have canonical signatures
6. Receivers are short and identical across a type's methods; no `this`/`self`
7. Sentinels use `Err`, error types end in `Error`, error strings are lowercase
8. Enum constants carry the type prefix and an `Unknown` zero value
9. No predeclared identifier is shadowed
10. Renames done with gopls; tags and templates checked afterwards
