# Receivers and Struct Tags

Worked examples for SKILL.md sections 11 and 12.

## Receivers

Pick one receiver kind per type and use it for every method on that type.
A type with both value and pointer methods has a method set that changes
depending on how it is held, which is a bug waiting to happen.

Use a **pointer receiver** when any of these hold — and then use it everywhere:

- A method mutates the receiver
- The struct contains a `sync.Mutex` or any other field that must not be copied
- The struct is large enough that copying it per call is measurable
- Any other method on the type already needs a pointer receiver

Use a **value receiver** for small immutable types: `time.Time`-like value
objects, enums, and types whose methods only read.

```go
// ✅ Consistent — every method on *Buffer takes a pointer
func (b *Buffer) Write(p []byte) (int, error) { ... }
func (b *Buffer) Len() int                     { ... }

// ❌ Mixed — Len() on a value copies the mutex
func (b *Buffer) Write(p []byte) (int, error) { ... }
func (b Buffer) Len() int                      { ... }
```

Name the receiver one or two letters after the type (`s *Server`, `b *Buffer`).
Never `this` or `self`. Keep the same name across every method on the type.

## Struct Tags

Tags are strings the compiler does not check. A typo is silent.

```go
// ✅ Good — backticks, no spaces after commas, explicit names
type User struct {
    ID        string    `json:"id" db:"id"`
    Email     string    `json:"email" db:"email" validate:"required,email"`
    CreatedAt time.Time `json:"created_at" db:"created_at"`
    password  string    `json:"-"` // never serialised
}

// ❌ Bad
type User struct {
    ID    string `json: "id"`        // space after the colon: tag is ignored
    Email string `json:"email,"`     // trailing comma
    Token string                     // no tag: marshals as "Token"
}
```

Rules:

- Tag every field of a type that crosses a serialisation boundary, including
  the ones whose name would happen to match.
- Use `json:"-"` for anything that must never leave the process. Do not rely
  on a field being unexported — an unexported field is skipped by
  `encoding/json` silently, which reads as an oversight rather than intent.
- `omitempty` omits zero values, so it cannot distinguish "absent" from
  "explicitly zero". Use a pointer or a wrapper type when that distinction
  carries meaning.
- `omitempty` never omits a struct value. `omitzero` (Go 1.24+) omits the Go
  zero value, or whatever a type's `IsZero()` method reports — the right
  tag for `time.Time` and other struct fields.
- `go vet` includes a `structtag` check. Run it — it catches the malformed
  cases above.
