# Mutexes, Atomics and Other sync Primitives

Guarding shared state. The SKILL.md section states the rules; this file has
the code.

## Contents

- Zero-value mutexes are valid
- Mutex placement in struct
- Lock scope should be minimal
- Never copy mutexes
- Atomic operations
- sync.Once for lazy initialization
- RWMutex pitfalls
- sync.Map — two cases only
- sync.Pool
- singleflight — collapse duplicate calls

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

## Atomic operations

Use the typed atomics in `sync/atomic` (Go 1.19+) for counters and flags.
They cannot be read non-atomically by mistake, and `go vet`'s `copylocks`
flags a copied one.

```go
type Server struct {
    running  atomic.Bool
    reqCount atomic.Int64
}

func (s *Server) HandleRequest() {
    s.reqCount.Add(1)
    // ...
}

// ❌ Bad — a plain int64 with atomic.AddInt64 at some call sites and a
// bare read at others is a data race the type system cannot catch
```

A third-party atomics package adds nothing the standard library lacks
since Go 1.19; the go-modernize skill lists the migration.

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

## RWMutex pitfalls

- **No upgrade.** Taking `Lock` while holding `RLock` deadlocks: the
  writer waits for all readers, including you. Release the read lock,
  take the write lock, and re-check the condition.
- **No recursive read locks.** A blocked `Lock` stops new readers, so a
  goroutine that calls `RLock` twice deadlocks once a writer queues
  between the two calls.
- **Not automatically faster.** With short critical sections a plain
  `Mutex` usually wins; reach for `RWMutex` when reads dominate and the
  read section does real work. Confirm with a benchmark under `-cpu=1,4,8`.

## sync.Map — two cases only

The documentation names the two workloads it is built for: keys written
once and read many times (a cache that only grows), and goroutines reading
and writing disjoint key sets. Anything else — frequent overwrites, the
need for a length, range-and-delete — is a `map` guarded by a mutex, which
is also typed.

## sync.Pool

```go
var bufPool = sync.Pool{New: func() any { return new(bytes.Buffer) }}

func render(v any) ([]byte, error) {
    buf := bufPool.Get().(*bytes.Buffer)
    buf.Reset() // a pooled object arrives with its previous contents
    defer func() {
        if buf.Cap() <= 64<<10 { // don't let one huge payload pin memory forever
            bufPool.Put(buf)
        }
    }()
    if err := json.NewEncoder(buf).Encode(v); err != nil {
        return nil, err
    }
    return bytes.Clone(buf.Bytes()), nil // the buffer goes back to the pool; copy out
}
```

- The pool may drop objects at any GC; never store anything you need to
  get back.
- Add a pool only when a profile shows the allocation on the hot path.

## singleflight — collapse duplicate calls

```go
var group singleflight.Group

func (c *Cache) Get(ctx context.Context, key string) (*Item, error) {
    if it, ok := c.lookup(key); ok {
        return it, nil
    }
    v, err, _ := group.Do(key, func() (any, error) {
        // The first caller's ctx runs the call for everyone. Detach it so one
        // client disconnecting does not fail every waiter, and bound it.
        ctx, cancel := context.WithTimeout(context.WithoutCancel(ctx), 5*time.Second)
        defer cancel()
        return c.load(ctx, key)
    })
    if err != nil {
        return nil, err
    }
    return v.(*Item), nil
}
```

Use `DoChan` when each waiter must still honor its own context.
