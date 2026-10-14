# Memory and I/O Patterns

Worked examples for the SKILL.md allocation, hot-path, map and I/O sections.

## Contents

- Allocation Reduction
- Hot Path Optimizations
- Map Performance
- Memory retention
- Struct layout
- HTTP clients
- Streaming instead of buffering
- Batching

## Allocation Reduction

### Prefer `strconv` over `fmt` for primitive conversions:

```go
// ✅ Good — zero allocations for simple conversions
s := strconv.Itoa(42)
s := strconv.FormatFloat(3.14, 'f', 2, 64)

// ❌ Bad — fmt.Sprintf allocates
s := fmt.Sprintf("%d", 42)
```

### Avoid unnecessary string-to-byte conversions:

```go
// ✅ Good — use strings.Builder for concatenation
var b strings.Builder
for _, s := range parts {
    b.WriteString(s)
}
result := b.String()

// ❌ Bad — repeated concatenation allocates on every +
result := ""
for _, s := range parts {
    result += s
}
```

### Preallocate slices and maps when size is known:

```go
// ✅ Good — single allocation
users := make([]User, 0, len(ids))
for _, id := range ids {
    users = append(users, getUser(id))
}

// ✅ Good — map with capacity hint
lookup := make(map[string]User, len(users))

// ❌ Bad — repeated growing
var users []User // starts at 0, grows via doubling
```

### Use `sync.Pool` for frequently allocated, short-lived objects:

```go
var bufPool = sync.Pool{
    New: func() any {
        return new(bytes.Buffer)
    },
}

func process(data []byte) string {
    buf := bufPool.Get().(*bytes.Buffer)
    buf.Reset()
    defer func() {
        if buf.Cap() <= 64<<10 { // don't let one huge input pin memory in the pool
            bufPool.Put(buf)
        }
    }()

    buf.Write(data)
    return buf.String() // String copies, so returning it after Put is safe
}
```

## Hot Path Optimizations

### Avoid interface conversions in tight loops:

```go
// ✅ Good — concrete type in loop
func sum(vals []int64) int64 {
    var total int64
    for _, v := range vals {
        total += v
    }
    return total
}

// ❌ Bad — interface{} causes boxing/unboxing
func sum(vals []interface{}) int64 { ... }
```

### Avoid `reflect` in performance-critical paths:

If you need reflection-like behavior at scale, use code generation
(`go generate`, `stringer`, protocol buffers).

### Reduce pointer chasing:

```go
// ✅ Good — contiguous memory, cache-friendly
type Points struct {
    X []float64
    Y []float64
}

// ❌ Slower — pointer chasing per element
type Points []*Point
```

## Map Performance

```go
// ✅ Use capacity hints
m := make(map[string]int, expectedSize)

// ✅ For read-heavy concurrent access, use sync.Map
// But ONLY when keys are stable — sync.Map has higher overhead
// for writes than a mutex-protected map.

// ✅ For fixed key sets, consider using a slice with index mapping
// instead of a map.
```

## Memory retention

```go
// ❌ The 512-byte header keeps the whole 64 MB body alive
hdr := body[:512]

// ✅ Copy what you keep
hdr := slices.Clone(body[:512])
id := strings.Clone(line[:16]) // same for substrings of a huge string
```

Maps never shrink after deletes; the go-data-structures skill shows how to
rebuild one.

## Struct layout

```go
// 24 bytes: padding after a and after c
type bad struct {
    a bool
    b int64
    c bool
}

// 16 bytes: largest fields first
type good struct {
    b int64
    a bool
    c bool
}
```

Only worth it for structs held by the million in slices or maps. The
`fieldalignment` analyzer (`golang.org/x/tools/go/analysis/passes/fieldalignment`)
reports candidates; its `-fix` reorders fields and can drop comments, so
review the diff.

**False sharing:** counters written by different goroutines that sit on
the same 64-byte cache line serialize on the hardware. Shard per CPU, or
pad each hot counter to its own line, and confirm with `-cpu 1,4,8`.

## HTTP clients

```go
// One client for the process, built once.
func newClient() *http.Client {
    t := http.DefaultTransport.(*http.Transport).Clone() // keeps proxy, dialer, TLS defaults
    t.MaxIdleConns = 100
    t.MaxIdleConnsPerHost = 32 // default 2: concurrent calls to one host churn connections
    return &http.Client{
        Timeout:   10 * time.Second, // whole request, including reading the body
        Transport: t,
    }
}

resp, err := client.Do(req)
if err != nil {
    return err
}
defer resp.Body.Close()
// Reading to EOF lets the connection go back to the pool.
_, _ = io.Copy(io.Discard, io.LimitReader(resp.Body, 1<<20))
```

- `http.Get` and `http.DefaultClient` have no timeout: one stuck upstream
  holds goroutines forever.
- Build the client once. A client per request defeats connection reuse.

## Streaming instead of buffering

```go
// ❌ The whole body in memory, then a second copy while decoding
data, _ := io.ReadAll(r.Body)
_ = json.Unmarshal(data, &req)

// ✅ Decode straight from the stream, with a size cap
dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<20))
if err := dec.Decode(&req); err != nil { ... }
```

Use `io.Copy` to proxy bodies and files, and `bufio.Writer` for many
small writes to a file or socket (remember `Flush`).

## Batching

One round trip per item is the most common hidden cost: insert rows in
batches of hundreds (or `COPY` with pgx), call batch endpoints where an
API offers them, and drain channels into slices flushed on size or time.
