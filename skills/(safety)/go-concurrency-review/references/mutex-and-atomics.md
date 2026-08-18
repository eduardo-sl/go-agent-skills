# Mutexes, Atomics and sync.Once

Guarding shared state. The SKILL.md section states the rules; this file has
the code.

## Zero-value mutexes are valid:

```go
// ✅ Good — zero value works
type Cache struct {
    mu    sync.RWMutex
    items map[string]Item
}

// ❌ Bad — unnecessary pointer
type Cache struct {
    mu    *sync.RWMutex // never do this
}
```

## Mutex placement in struct:

```go
type SafeMap struct {
    mu sync.RWMutex // mutex guards the fields below
    items map[string]string
    count int
}
```

The mutex should appear directly above the field(s) it protects,
with a comment indicating the relationship.

## Lock scope should be minimal:

```go
// ✅ Good — minimal lock scope
func (c *Cache) Get(key string) (Item, bool) {
    c.mu.RLock()
    item, ok := c.items[key]
    c.mu.RUnlock()
    return item, ok
}

// ✅ Also good — defer for methods that return early
func (c *Cache) GetOrCreate(key string) Item {
    c.mu.Lock()
    defer c.mu.Unlock()

    if item, ok := c.items[key]; ok {
        return item
    }
    item := newItem(key)
    c.items[key] = item
    return item
}
```

## Never copy mutexes:

```go
// ❌ BLOCKER — copying a mutex copies its lock state
cache2 := *cache1 // this copies the mutex!
```

## 4. Atomic Operations

Use `sync/atomic` or `go.uber.org/atomic` for simple counters and flags:

```go
// ✅ Good — type-safe atomics
import "go.uber.org/atomic"

type Server struct {
    running atomic.Bool
    reqCount atomic.Int64
}

func (s *Server) HandleRequest() {
    s.reqCount.Inc()
    // ...
}
```

## sync.Once for lazy initialization

```go
type Client struct {
    initOnce sync.Once
    conn     *grpc.ClientConn
}

func (c *Client) getConn() *grpc.ClientConn {
    c.initOnce.Do(func() {
        c.conn = dial()
    })
    return c.conn
}
```
