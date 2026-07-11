# Generics Migration Patterns (Go 1.18+)

Full examples for the generics rules summarized in SKILL.md.

## Replace `interface{}` / `any` with Type Parameters

```go
// ❌ Before — loses type safety
func Contains(slice []interface{}, target interface{}) bool {
    for _, v := range slice {
        if v == target {
            return true
        }
    }
    return false
}

// ✅ After — type-safe generic
func Contains[T comparable](slice []T, target T) bool {
    for _, v := range slice {
        if v == target {
            return true
        }
    }
    return false
}
```

## Type Constraints

```go
// Built-in constraints
func Sum[T int | int64 | float64](values []T) T {
    var total T
    for _, v := range values {
        total += v
    }
    return total
}

// Or use golang.org/x/exp/constraints (or define your own)
type Number interface {
    ~int | ~int8 | ~int16 | ~int32 | ~int64 |
        ~float32 | ~float64
}

func Sum[T Number](values []T) T {
    var total T
    for _, v := range values {
        total += v
    }
    return total
}
```

The `~` prefix accepts named types whose underlying type matches
(`type Celsius float64` satisfies `~float64`).

## When NOT to Use Generics

```go
// ❌ Don't use generics when a single concrete type works
func PrintUser[T User](u T) { fmt.Println(u.Name) }
// → Just use: func PrintUser(u User) { fmt.Println(u.Name) }

// ❌ Don't use generics to avoid interfaces for behavior polymorphism
// Interfaces are still the right tool for runtime polymorphism

// ✅ Use generics for:
// - Container types (Set[T], Stack[T], Result[T])
// - Utility functions operating on multiple types (Map, Filter, Reduce)
// - Type-safe wrappers (sync pool, atomic values)
```

## Generic Container Example

```go
type Set[T comparable] struct {
    items map[T]struct{}
}

func NewSet[T comparable](items ...T) Set[T] {
    s := Set[T]{items: make(map[T]struct{}, len(items))}
    for _, item := range items {
        s.items[item] = struct{}{}
    }
    return s
}

func (s Set[T]) Contains(item T) bool {
    _, ok := s.items[item]
    return ok
}

func (s Set[T]) Add(item T) {
    s.items[item] = struct{}{}
}
```
