# Common Go Bugs

Bugs that compile, pass review, and produce wrong behavior. Search this
table by the symptom you see, then confirm with a minimal test.

## Control flow

| Symptom | Bug | Fix |
|---|---|---|
| Loop never exits after `break` | `break` inside `select` or `switch` leaves only that statement | Labeled `break outer` |
| Loop pegs a CPU core | `select` with `default` in a loop polls instead of blocking | Remove `default`, or block on a timer/channel |
| Busy loop after shutdown | Receiving from a closed channel returns the zero value immediately, forever | Use `v, ok := <-ch`; set the channel variable to `nil` once closed |
| Deferred cleanup never ran | `os.Exit` and `log.Fatal` skip deferred functions | Return an error to `main`; exit once there |
| Deferred log prints the wrong value | `defer f(x)` evaluates `x` at the `defer` | `defer func() { f(x) }()` |
| Handler writes twice, "superfluous WriteHeader" | Missing `return` after `http.Error` | Return immediately after writing an error |

## Values and types

| Symptom | Bug | Fix |
|---|---|---|
| `err != nil` is true but err prints `<nil>` | Typed nil pointer returned as `error` | Return the untyped `nil` (go-defensive-coding) |
| Changes to `v` in `for _, v := range s` are lost | `v` is a copy of the element | Index: `s[i].Field = x` |
| Two slices change together | `append` reused a shared backing array | Full slice expression `s[:n:n]` or `slices.Clone` |
| Value receiver does not satisfy an interface at runtime | Methods are on `*T`, a `T` was stored | Store `&T{}`; add `var _ I = (*T)(nil)` |
| `time.Time` values that look equal compare unequal | `==` also compares monotonic reading and location | `t1.Equal(t2)` |
| Large numbers off by one after JSON decode into `any` | JSON numbers become `float64` | Decode into concrete types, or `Decoder.UseNumber()` |
| JSON field silently empty | Field is unexported, or the tag is malformed | Export it; run `go vet` (`structtag`) |
| `strings.Trim(s, "abc")` eats too much | `Trim` removes a *set* of characters | `TrimPrefix` / `TrimSuffix` |
| String length or indexing wrong for non-ASCII | `len` and `s[i]` work in bytes | `utf8.RuneCountInString`, `for _, r := range s` |
| Value wraps around silently | Narrowing integer conversion | Range-check first (go-defensive-coding) |

## Concurrency and resources

| Symptom | Bug | Fix |
|---|---|---|
| `Wait` returns before work is done | `wg.Add` called inside the goroutine | `Add` before `go`, or `wg.Go` (Go 1.25+) |
| `fatal error: concurrent map writes` | Unsynchronized map shared between goroutines | Mutex, or ownership through a channel |
| Panic: send on closed channel | A receiver, or a second sender, closed the channel | Only the single sender closes |
| Panic in a goroutine kills the process despite middleware `recover` | `recover` works only in the panicking goroutine | Recover in that goroutine (go-concurrency-review) |
| Connection pool exhausted | `rows.Close()` or `resp.Body.Close()` missing on some path | `defer` the close right after the error check |
| Context leak warnings, timers piling up | `cancel` from `WithTimeout` never called | `defer cancel()`; `go vet` reports it (`lostcancel`) |
| `err` checked but the wrong one | `:=` in an inner scope shadowed the outer `err` | Assign with `=`; the `shadow` analyzer finds these |

## Filesystem and input

| Symptom | Bug | Fix |
|---|---|---|
| A path escapes the upload directory | `filepath.Join` does not prevent `../` traversal | `os.Root` (Go 1.24+) |
| Works on Linux, not Windows | Hardcoded `/` separators | `filepath.Join`; `path` only for URLs |
