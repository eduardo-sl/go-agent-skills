# Embedding, Assertions and Sealed Interfaces

Worked examples for SKILL.md sections 8 and 9.

## Embedding promotes everything

```go
// ❌ Bad — Lock and Unlock become part of Cache's public API
type Cache struct {
    sync.Mutex
    items map[string]Item
}

// ✅ Good — the mutex is an implementation detail
type Cache struct {
    mu    sync.Mutex
    items map[string]Item
}
```

Embed when the outer type genuinely *is* an extended version of the inner
one and every promoted method makes sense on it. Use a named field and
delegate the few methods you need otherwise.

## Embedding an interface in a struct

```go
// A test fake that implements only the method the code under test calls.
type fakeStore struct {
    UserStore // nil: any method not overridden panics if called
    user *User
}

func (f *fakeStore) GetByID(ctx context.Context, id string) (*User, error) {
    return f.user, nil
}
```

Useful in tests; in production code it turns a missing method into a
runtime panic instead of a compile error.

## Optional capabilities via interface assertion

```go
func stream(w http.ResponseWriter, events <-chan Event) {
    flusher, ok := w.(http.Flusher)
    if !ok {
        http.Error(w, "streaming unsupported", http.StatusInternalServerError)
        return
    }
    for e := range events {
        fmt.Fprintf(w, "data: %s\n\n", e)
        flusher.Flush()
    }
}
```

Always use the comma-ok form — a bare `w.(http.Flusher)` panics when a
middleware wraps the writer.

## Sealed interfaces for closed sets of variants

```go
// Shape is implemented only inside this package: the unexported method
// keeps other packages from adding variants.
type Shape interface{ isShape() }

type Circle struct{ R float64 }
type Rect struct{ W, H float64 }

func (Circle) isShape() {}
func (Rect) isShape()   {}

func Area(s Shape) float64 {
    switch s := s.(type) {
    case Circle:
        return math.Pi * s.R * s.R
    case Rect:
        return s.W * s.H
    default:
        panic(fmt.Sprintf("unknown shape %T", s)) // unreachable while sealed
    }
}
```

Use this when variants carry different data (`go/ast` does it for
expressions). When they carry none, a typed constant enum is simpler.
