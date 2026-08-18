---
name: go-data-structures
description: >
  Correct use of Go's built-in data structures: slices (nil vs empty, append
  semantics, aliasing, preallocation), maps (comma-ok, sets, iteration order),
  arrays, and choosing between them.
  Use when: "slice vs array", "nil slice", "empty slice", "preallocate",
  "map iteration", "use a set in Go", "slice aliasing", "append gotcha",
  "copy a slice", "sync.Map or mutex".
  Do NOT use for: protecting structures shared across goroutines
  (use go-concurrency-review), allocation profiling (use go-performance-review),
  or generic container design (use go-design-patterns).
user-invocable: true
license: MIT
compatibility: Designed for Claude Code or similar AI coding agents working on Go projects. Requires the Go toolchain.
allowed-tools: Read Edit Write Glob Grep Bash(go:*) Bash(gofmt:*)
metadata:
  author: eduardo-sl
  version: "1.1.0"
---

# Go Data Structures

Slices and maps look simple and hide the sharpest edges in the language.
These rules prevent the aliasing, nil, and iteration bugs that survive
code review.

## 1. Nil Slice vs Empty Slice

```go
var a []int          // nil slice — len 0, cap 0, no allocation
b := []int{}         // empty slice — len 0, allocated header
c := make([]int, 0)  // empty slice — same as b
```

- `len`, `cap`, `range`, and `append` treat all three identically.
- **Prefer the nil slice** as the "no elements" value; don't allocate
  just to return "empty".
- Exception: JSON. `nil` marshals to `null`, empty marshals to `[]`.
  If the API contract requires `[]`, return an empty slice explicitly.
- Never distinguish nil from empty in logic — check `len(s) == 0`.

## 2. Append Semantics and Aliasing

`append` MAY return the same backing array or a new one. Both cases
bite:

```go
// ❌ Bad — result may alias the input
func addSuffix(base []string) []string {
    return append(base, "suffix") // if cap(base) > len(base),
}                                 // this WRITES INTO base's array

// ✅ Good — force a copy when the input must not be touched
func addSuffix(base []string) []string {
    out := make([]string, len(base), len(base)+1)
    copy(out, base)
    return append(out, "suffix")
}
```

```go
// ❌ Bad — subslice keeps the whole 64 MB alive
func header(big []byte) []byte {
    return big[:512] // backing array is still the full big
}

// ✅ Good — copy the window you keep
func header(big []byte) []byte {
    return slices.Clone(big[:512]) // Go 1.21+; or copy() manually
}
```

Rule: a function either owns a slice or copies it. Returning a subslice
of a caller's slice, or appending to one, silently shares memory.

## 3. Preallocation

When the final size is known or bounded, allocate once:

```go
// ✅ Good — one allocation
names := make([]string, 0, len(users))
for _, u := range users {
    names = append(names, u.Name)
}

// ❌ Bad — repeated growth and copying
var names []string
for _, u := range users {
    names = append(names, u.Name)
}
```

Same for maps: `make(map[string]int, len(items))`.
Don't preallocate when the size is unknown — a wrong large cap wastes
memory; `append` growth is fine for cold paths.

## 4. Map Essentials

```go
// Comma-ok distinguishes "missing" from "zero value"
count, ok := hits[key]
if !ok { /* key absent */ }

// Zero value reads are safe; writes to a nil map PANIC
var m map[string]int
_ = m["x"]      // 0, fine
m["x"] = 1      // panic: assignment to entry in nil map — make() first

// Iteration order is RANDOM and differs between runs.
// Sort keys when output must be deterministic:
keys := slices.Sorted(maps.Keys(m)) // Go 1.23+
for _, k := range keys {
    fmt.Println(k, m[k])
}
```

- Map values are not addressable: `m[k].Field = v` doesn't compile for
  struct values. Use a map of pointers, or read-modify-write.
- Deleting during `range` is safe; inserting during `range` is
  unspecified (the new key may or may not be visited).

## 5. Sets

The idiomatic set is a map with empty-struct values:

```go
seen := make(map[string]struct{}, len(items))
for _, it := range items {
    if _, dup := seen[it.ID]; dup {
        continue
    }
    seen[it.ID] = struct{}{}
    process(it)
}
```

`struct{}` occupies zero bytes; `map[string]bool` also works and reads
better when you'll test membership with `if seen[id]`.

## 6. Arrays vs Slices

- Arrays (`[4]byte`) are values: assignment and passing copy the whole
  array. Comparable with `==` when elements are comparable.
- Use arrays for fixed-size data with value semantics: hashes
  (`[32]byte`), IPv4 addresses, fixed matrices, map keys.
- Everything else is a slice. A function taking `[100]int` copies 800
  bytes per call — almost always wrong.

## 7. Choosing a Structure

| Need | Use |
|---|---|
| Ordered collection, growable | `[]T` |
| Membership / dedup | `map[K]struct{}` |
| Key→value lookup | `map[K]V` |
| Fixed size, value semantics, comparable | `[N]T` array |
| FIFO queue (single goroutine) | slice with head index, or `container/list` for heavy churn |
| Stack | slice + `append` / `s[:len(s)-1]` |
| Concurrent map, write-once read-many keys | `sync.Map` — otherwise mutex + map |

`sync.Map` is a special-case tool (append-only caches, disjoint key
sets). Default to `map` + `sync.RWMutex`; see the concurrency skill for
locking patterns.

## Verification Checklist

1. No logic distinguishes nil slice from empty slice; `len()` used for emptiness
2. JSON-facing slices explicitly empty (not nil) where the contract requires `[]`
3. No `append` to a slice the function doesn't own; copies made explicit
4. No long-lived subslices of large arrays without `slices.Clone`/`copy`
5. Slices and maps preallocated with capacity when size is known
6. Comma-ok used wherever "missing" differs from zero value
7. No writes to possibly-nil maps
8. Deterministic output paths sort map keys before iteration
9. Sets built as `map[K]struct{}` (or `map[K]bool` for readability)
10. Arrays only where value semantics or comparability is the point
