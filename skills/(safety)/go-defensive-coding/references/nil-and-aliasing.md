# Nil Values, Aliasing, and Memory Retention

Loaded on demand from `go-defensive-coding`. Read this when the summary in
SKILL.md is not enough to resolve a concrete case.

## Interface nil-ness in full

An interface value is a pair: `(dynamic type, dynamic value)`. It is `nil`
only when **both** halves are unset.

```go
var p *bytes.Buffer      // p == nil
var w io.Writer = p      // w != nil, because the type half is *bytes.Buffer
fmt.Println(w == nil)    // false
```

The failure mode this creates:

```go
func open(path string) (io.ReadCloser, error) {
    f, err := os.Open(path)  // f is *os.File
    if err != nil {
        return f, err        // ❌ f is a typed nil, the interface is non-nil
    }
    return f, nil
}
```

A caller writing `if rc != nil { defer rc.Close() }` will call `Close` on a
nil `*os.File` and panic. Return the literal `nil`:

```go
    if err != nil {
        return nil, err      // ✅
    }
```

### Detecting it in a review

Search for functions whose return type is an interface and whose body
declares a variable of a concrete pointer type with the same role:

```bash
grep -rn "func .*) \(error\|io\.\w*\|.*Interface\)" --include="*.go" .
```

Then check every `return <var>` where `<var>` is a concrete type.

### Testing for it

```go
if got := find("ok"); got != nil {
    t.Fatalf("expected nil error, got %v (%T)", got, got)
}
```

Printing `%T` alongside the value is what makes a typed nil visible in the
failure output.

## Nil receivers can be valid

A method on a pointer receiver may be called with a nil receiver. This is a
legitimate pattern when documented:

```go
type Node struct {
    Left, Right *Node
    Val         int
}

// Sum tolerates a nil receiver so callers need no nil checks.
func (n *Node) Sum() int {
    if n == nil {
        return 0
    }
    return n.Val + n.Left.Sum() + n.Right.Sum()
}
```

Do this deliberately or not at all. An undocumented nil-tolerant method
becomes an undocumented nil-intolerant one on the next edit.

## Nil vs empty slice in JSON

`omitempty` treats both as empty and omits the field. Without it they differ:

```go
type Resp struct {
    Items []string `json:"items"`
}

json.Marshal(Resp{})                    // {"items":null}
json.Marshal(Resp{Items: []string{}})   // {"items":[]}
```

If a client iterates the field without a null check, return `[]string{}` from
the handler. Otherwise prefer nil.

## Slice aliasing scenarios

### Append through a subslice

```go
a := []int{1, 2, 3, 4}   // len 4, cap 4
b := a[:2]               // len 2, cap 4 — shares the array
b = append(b, 99)        // writes into a[2]
// a == [1 2 99 4]
```

`append` reallocates only when `len == cap`. Any spare capacity is written
in place.

### The fix: full slice expression

`a[low:high:max]` sets cap to `max-low`.

```go
b := a[:2:2]      // len 2, cap 2
b = append(b, 99) // must allocate; a is untouched
```

### Passing a slice to a callee that appends

```go
// ❌ The callee may or may not mutate the caller's array, depending on cap
func addDefault(tags []string) []string {
    return append(tags, "default")
}

// ✅ Make the copy explicit at the boundary
func addDefault(tags []string) []string {
    out := make([]string, 0, len(tags)+1)
    out = append(out, tags...)
    return append(out, "default")
}
```

### Struct fields that hold subslices

```go
type Record struct{ Payload []byte }

// ❌ Every Record shares one 1 MiB buffer, and each keeps it alive
func parse(buf []byte) []Record {
    var out []Record
    for _, off := range offsets(buf) {
        out = append(out, Record{Payload: buf[off : off+32]})
    }
    return out
}

// ✅ Clone the 32 bytes we keep, release the megabyte
        out = append(out, Record{Payload: slices.Clone(buf[off : off+32])})
```

## Memory retention

A slice keeps its whole backing array reachable, no matter how small the
view is. The same applies to a substring of a large string built from
`string(bigByteSlice)` only when re-slicing the byte slice — strings created
by conversion already copy.

Symptoms: heap profile shows a large `[]byte` alive with no obvious owner.
`go-troubleshooting` covers diffing heap profiles to find it.

Release pattern:

```go
head := slices.Clone(buf[:64]) // or: append([]byte(nil), buf[:64]...)
buf = nil                      // drop the reference if it is a long-lived field
```

## Map iteration order

Map iteration order is randomised per run, deliberately. Code that depends
on it is nondeterministic and will pass tests until it does not.

```go
// ✅ Sort the keys when order matters
keys := slices.Sorted(maps.Keys(m))
for _, k := range keys {
    fmt.Println(k, m[k])
}
```

`slices.Sorted` and `maps.Keys` require Go 1.23. On earlier versions collect
into a slice and call `sort.Strings`.

## Comma-ok on every dynamic lookup

```go
// ❌ Panics if v is not a *User
u := v.(*User)

// ✅
u, ok := v.(*User)
if !ok {
    return fmt.Errorf("expected *User, got %T", v)
}
```

The zero-value-vs-missing distinction for maps needs the same form:

```go
v, ok := m[k]
if !ok { /* absent — different from present-and-zero */ }
```
