# Containers and Memory Behaviour

Worked examples for SKILL.md sections 7-9.

## Contents

- Priority queue with `container/heap`
- LRU cache: map + `container/list`
- Reclaiming map memory
- `weak.Pointer` cache (Go 1.24+)

## Priority queue with `container/heap`

```go
type Job struct {
    ID       string
    Priority int
}

// jobQueue implements heap.Interface; the heap package owns the ordering.
type jobQueue []*Job

func (q jobQueue) Len() int           { return len(q) }
func (q jobQueue) Less(i, j int) bool { return q[i].Priority > q[j].Priority } // max-heap
func (q jobQueue) Swap(i, j int)      { q[i], q[j] = q[j], q[i] }
func (q *jobQueue) Push(x any)        { *q = append(*q, x.(*Job)) }
func (q *jobQueue) Pop() any {
    old := *q
    n := len(old)
    j := old[n-1]
    old[n-1] = nil // let the GC reclaim the popped job
    *q = old[:n-1]
    return j
}

q := &jobQueue{}
heap.Push(q, &Job{ID: "a", Priority: 2}) // call heap.Push, never q.Push
next := heap.Pop(q).(*Job)
```

Top-K, schedulers and Dijkstra are all this shape: O(log n) push/pop,
O(1) peek at `(*q)[0]`.

## LRU cache: map + `container/list`

```go
type LRU[K comparable, V any] struct {
    cap   int
    ll    *list.List            // front = most recently used
    items map[K]*list.Element   // element.Value is entry[K, V]
}

type entry[K comparable, V any] struct {
    key K
    val V
}

func (c *LRU[K, V]) Get(k K) (V, bool) {
    if el, ok := c.items[k]; ok {
        c.ll.MoveToFront(el)
        return el.Value.(entry[K, V]).val, true
    }
    var zero V
    return zero, false
}

func (c *LRU[K, V]) Put(k K, v V) {
    if el, ok := c.items[k]; ok {
        el.Value = entry[K, V]{k, v}
        c.ll.MoveToFront(el)
        return
    }
    c.items[k] = c.ll.PushFront(entry[K, V]{k, v})
    if c.ll.Len() > c.cap {
        oldest := c.ll.Back()
        c.ll.Remove(oldest)
        delete(c.items, oldest.Value.(entry[K, V]).key)
    }
}
```

Not safe for concurrent use; guard it with a mutex.

## Reclaiming map memory

```go
// A map that once held 10M entries keeps its buckets after delete or clear.
for k := range sessions {
    if expired(k) {
        delete(sessions, k)
    }
}

// Rebuild to release memory once most entries are gone:
sessions = maps.Clone(sessions) // sized for the current length
```

## `weak.Pointer` cache (Go 1.24+)

```go
// The cache never keeps a value alive on its own: once no one else holds
// the *Image, the GC may reclaim it and Value() returns nil.
type imageCache struct {
    mu sync.Mutex
    m  map[string]weak.Pointer[Image]
}

func (c *imageCache) Get(key string) *Image {
    c.mu.Lock()
    defer c.mu.Unlock()
    if wp, ok := c.m[key]; ok {
        if img := wp.Value(); img != nil {
            return img
        }
        delete(c.m, key) // collected; drop the stale entry
    }
    return nil
}
```
