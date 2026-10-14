# Standard Library Migrations

Full before/after examples for the migrations summarized in SKILL.md.

## Contents

- log/slog (Go 1.21+)
- errors.Join (Go 1.20+)
- slices Package (Go 1.21+)
- maps Package (Go 1.21+)
- Range Over Integers (Go 1.22+)
- Range Over Function / Iterators (Go 1.23+)
- http.NewRequestWithContext (Go 1.13+, often missed)
- sync.WaitGroup.Go (Go 1.25+)
- errors.AsType (Go 1.26+)
- slog.NewMultiHandler (Go 1.26+)
- new(expr) (Go 1.26+)
- os.Root for path containment (Go 1.24+)
- unique and runtime.AddCleanup (Go 1.23-1.24)
- Loop variable shadow copies (Go 1.22+)
- math/rand/v2 and cmp.Or (Go 1.22+)
- ServeMux patterns (Go 1.22+)
- omitzero (Go 1.24+)
- Iterator-returning string helpers (Go 1.24+)
- x/crypto → standard library (Go 1.24+)
- Container-aware GOMAXPROCS (Go 1.25+)
- ReverseProxy.Rewrite (Go 1.20+, Director deprecated in 1.26)

## log/slog (Go 1.21+)

Replace `log`/`fmt.Printf` with structured logging:

```go
// ❌ Before
log.Printf("processing order %s for user %s", orderID, userID)

// ✅ After
slog.Info("processing order",
    slog.String("order_id", orderID),
    slog.String("user_id", userID),
)
```

Replace third-party loggers where slog is sufficient:

```go
// Before — zap
logger.Info("request completed",
    zap.String("method", method),
    zap.Int("status", status),
    zap.Duration("latency", elapsed),
)

// After — slog (if you don't need zap-specific features)
slog.Info("request completed",
    slog.String("method", method),
    slog.Int("status", status),
    slog.Duration("latency", elapsed),
)
```

Keep zap/zerolog if you need their performance characteristics for
high-throughput logging. For most services, slog is sufficient.

## errors.Join (Go 1.20+)

```go
// ❌ Before — manual error accumulation
var errMsgs []string
for _, item := range items {
    if err := validate(item); err != nil {
        errMsgs = append(errMsgs, err.Error())
    }
}
if len(errMsgs) > 0 {
    return fmt.Errorf("validation: %s", strings.Join(errMsgs, "; "))
}

// ✅ After — errors.Join preserves the error chain
var errs []error
for _, item := range items {
    if err := validate(item); err != nil {
        errs = append(errs, err)
    }
}
if err := errors.Join(errs...); err != nil {
    return fmt.Errorf("validation: %w", err)
}
```

`errors.Join` preserves the full error chain — `errors.Is` and
`errors.As` work on each individual error.

## slices Package (Go 1.21+)

```go
// ❌ Before — manual sort
sort.Slice(users, func(i, j int) bool {
    return users[i].Name < users[j].Name
})

// ✅ After — slices.SortFunc
slices.SortFunc(users, func(a, b User) int {
    return cmp.Compare(a.Name, b.Name)
})
```

```go
// ❌ Before — manual contains check
found := false
for _, v := range items {
    if v == target {
        found = true
        break
    }
}

// ✅ After
found := slices.Contains(items, target)
```

```go
// ❌ Before — manual index search
idx := -1
for i, v := range items {
    if v.ID == targetID {
        idx = i
        break
    }
}

// ✅ After
idx := slices.IndexFunc(items, func(item Item) bool {
    return item.ID == targetID
})
```

## maps Package (Go 1.21+)

```go
// ❌ Before — manual key collection
keys := make([]string, 0, len(m))
for k := range m {
    keys = append(keys, k)
}

// ✅ After
keys := slices.Collect(maps.Keys(m))
```

```go
// ❌ Before — manual map clone
clone := make(map[string]int, len(m))
for k, v := range m {
    clone[k] = v
}

// ✅ After
clone := maps.Clone(m)
```

## Range Over Integers (Go 1.22+)

```go
// ❌ Before
for i := 0; i < n; i++ {
    process(i)
}

// ✅ After
for i := range n {
    process(i)
}
```

## Range Over Function / Iterators (Go 1.23+)

Custom iterator with `iter.Seq2` that yields values and errors:

```go
// ✅ Iterator that yields filtered results
func (db *DB) ActiveUsers(ctx context.Context) iter.Seq2[User, error] {
    return func(yield func(User, error) bool) {
        rows, err := db.QueryContext(ctx, "SELECT id, name FROM users WHERE active = true")
        if err != nil {
            yield(User{}, fmt.Errorf("query active users: %w", err))
            return
        }
        defer rows.Close()

        for rows.Next() {
            var u User
            if err := rows.Scan(&u.ID, &u.Name); err != nil {
                if !yield(User{}, fmt.Errorf("scan user: %w", err)) {
                    return
                }
                continue
            }
            if !yield(u, nil) {
                return
            }
        }
        if err := rows.Err(); err != nil {
            yield(User{}, fmt.Errorf("iterate users: %w", err))
        }
    }
}

// Usage — clean range loop
for user, err := range db.ActiveUsers(ctx) {
    if err != nil {
        return fmt.Errorf("active users: %w", err)
    }
    process(user)
}
```

Standard library iterators — use them:

```go
// maps.Keys, maps.Values return iterators (Go 1.23+)
for key := range maps.Keys(m) {
    fmt.Println(key)
}

// slices.All, slices.Values, slices.Backward
for i, v := range slices.Backward(items) {
    fmt.Printf("%d: %v\n", i, v)
}
```

## http.NewRequestWithContext (Go 1.13+, often missed)

```go
// ❌ Before — request without context
req, err := http.NewRequest(http.MethodGet, url, nil)

// ✅ After — context propagated
req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
```

## sync.WaitGroup.Go (Go 1.25+)

```go
// ❌ Before — Add/Done must stay in sync by hand
var wg sync.WaitGroup
wg.Add(1)
go func() {
    defer wg.Done()
    work()
}()
wg.Wait()

// ✅ After
var wg sync.WaitGroup
wg.Go(work)
wg.Wait()
```

`errgroup.Group` is still the right choice when the goroutines return errors
or need a shared cancellation context. `wg.Go` replaces only the plain case.

## errors.AsType (Go 1.26+)

```go
// ❌ Before
var perr *fs.PathError
if errors.As(err, &perr) {
    return perr.Path
}

// ✅ After — no target variable, no double indirection to get wrong
if perr, ok := errors.AsType[*fs.PathError](err); ok {
    return perr.Path
}
```

## slog.NewMultiHandler (Go 1.26+)

```go
// ❌ Before — a hand-written handler forwarding to two others
type multiHandler struct{ a, b slog.Handler }

func (h multiHandler) Handle(ctx context.Context, r slog.Record) error {
    _ = h.a.Handle(ctx, r)
    return h.b.Handle(ctx, r)
}
// ... plus Enabled, WithAttrs and WithGroup, each easy to get wrong

// ✅ After
logger := slog.New(slog.NewMultiHandler(
    slog.NewJSONHandler(os.Stdout, nil),
    auditHandler,
))
```

## new(expr) (Go 1.26+)

```go
// ❌ Before — a temporary variable only to take its address
port := 8080
cfg := Config{Port: &port}

// ✅ After
cfg := Config{Port: new(8080)}
```

Useful for optional struct fields and protobuf-style pointer scalars. Do not
use it to hide a value that deserves a name.

## os.Root for path containment (Go 1.24+)

```go
// ❌ Before — manual traversal checks are easy to bypass
clean := filepath.Clean(userPath)
if strings.HasPrefix(clean, "..") {
    return errors.New("invalid path")
}
data, err := os.ReadFile(filepath.Join(baseDir, clean))

// ✅ After — the OS enforces containment, symlinks included
root, err := os.OpenRoot(baseDir)
if err != nil {
    return err
}
defer root.Close()
data, err := root.ReadFile(userPath) // cannot escape baseDir
```

## unique and runtime.AddCleanup (Go 1.23-1.24)

```go
// ✅ unique.Make deduplicates repeated values; Value() returns the canonical copy
h := unique.Make(hostname)          // unique.Handle[string], comparable, cheap
store[h] = conn                     // one string kept in memory, not one per entry

// ✅ AddCleanup replaces SetFinalizer: multiple cleanups, no resurrection,
//    and it works on objects that are part of a cycle
runtime.AddCleanup(obj, func(fd int) { syscall.Close(fd) }, obj.fd)
```

Reach for `unique` only where profiling shows duplicate values dominating the
heap — a config parser reading millions of rows, not a request handler.

## Loop variable shadow copies (Go 1.22+)

```go
// ❌ Before — needed only when go.mod said 1.21 or lower
for _, v := range items {
    v := v
    go func() { use(v) }()
}

// ✅ Go 1.22+ — each iteration already has its own v
for _, v := range items {
    go func() { use(v) }()
}
```

Delete the copies only after `go.mod` says `go 1.22` or later; the
semantics follow the module's `go` line, not the toolchain.

## math/rand/v2 and cmp.Or (Go 1.22+)

```go
n := rand.IntN(10)            // math/rand/v2: no Seed, no global lock
addr := cmp.Or(cfg.Addr, os.Getenv("ADDR"), ":8080") // first non-zero
```

Neither package is for secrets — use `crypto/rand`.

## ServeMux patterns (Go 1.22+)

```go
mux := http.NewServeMux()
mux.HandleFunc("GET /users/{id}", h.getUser)   // method + wildcard
mux.HandleFunc("POST /users", h.createUser)

func (h *Handler) getUser(w http.ResponseWriter, r *http.Request) {
    id := r.PathValue("id")
    // ...
}
```

Keep a third-party router when you use its middleware groups or
sub-routers; drop it when it only matched methods and path parameters.

## omitzero (Go 1.24+)

```go
type Event struct {
    // omitempty never omits a struct, so a zero time.Time encodes as
    // "0001-01-01T00:00:00Z". omitzero uses the Go zero value (or IsZero()).
    At time.Time `json:"at,omitzero"`
}
```

## Iterator-returning string helpers (Go 1.24+)

```go
for line := range strings.Lines(text) { ... }        // keeps the "\n"
for part := range strings.SplitSeq(csv, ",") { ... } // no []string allocation
```

## x/crypto → standard library (Go 1.24+)

| Before | After |
|---|---|
| `golang.org/x/crypto/sha3` | `crypto/sha3` |
| `golang.org/x/crypto/hkdf` | `crypto/hkdf` |
| `golang.org/x/crypto/pbkdf2` | `crypto/pbkdf2` |

The stdlib APIs differ slightly (they return errors and take the hash
constructor); compile, then read each call site. `crypto/rand.Text()`
returns a 26-character base32 token with 128 bits of entropy.

## Container-aware GOMAXPROCS (Go 1.25+)

```go
// ❌ Before — needed until Go 1.24
import _ "go.uber.org/automaxprocs"

// ✅ Go 1.25+ — the runtime reads the cgroup CPU limit itself; delete the import
```

## ReverseProxy.Rewrite (Go 1.20+, Director deprecated in 1.26)

```go
proxy := &httputil.ReverseProxy{
    Rewrite: func(pr *httputil.ProxyRequest) {
        pr.SetURL(target)  // routes and sets Host
        pr.SetXForwarded() // X-Forwarded-For/Host/Proto from the inbound request
    },
}
```

`Director` let hop-by-hop header handling strip headers the director had
just set; `Rewrite` runs after that cleanup.
