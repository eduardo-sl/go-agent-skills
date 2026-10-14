# Go 1.27 Migrations

Before/after examples for the Go 1.27 rows of the feature table. Every
change here needs `go 1.27` (or later) in `go.mod`; raising the directive
is a separate step — see `version-bump.md`.

## Contents

- Generic methods
- Promoted fields as struct literal keys
- `strings.CutLast` and `bytes.CutLast`
- `url.URL.Clone` and `url.Values.Clone`
- `big.Int.Divide`
- Standard library `uuid`
- `encoding/json`: the v2 engine and the v2 API
- Testing: `synctest.Sleep` and `httptest.NewTestServer`
- Diagnostics and tooling

## Generic methods

A method may now declare its own type parameters.

```go
type List[T any] struct{ items []T }

// ❌ Before — a package-level helper detached from the type it serves
func MapList[T, U any](l *List[T], f func(T) U) []U { /* ... */ }

// ✅ Go 1.27+ — scoped to the receiver
func (l *List[T]) Map[U any](f func(T) U) []U {
    out := make([]U, 0, len(l.items))
    for _, v := range l.items {
        out = append(out, f(v))
    }
    return out
}
```

Interface methods still cannot declare type parameters, and a generic
method never satisfies an interface method. Keep the package-level function
when the operation must be part of an interface contract.
`(*rand.Rand).N` in `math/rand/v2` is the standard library's own example.

## Promoted fields as struct literal keys

```go
type Base struct{ ID string }
type User struct {
    Base
    Name string
}

// ❌ Before
u := User{Base: Base{ID: "u-1"}, Name: "Ann"}

// ✅ Go 1.27+ — a promoted field can be keyed directly
u := User{ID: "u-1", Name: "Ann"}
```

## `strings.CutLast` and `bytes.CutLast`

```go
// ❌ Before — index arithmetic, easy to get the offset wrong
if i := strings.LastIndex(path, "/"); i >= 0 {
    dir, file := path[:i], path[i+1:]
    // ...
}

// ✅ Go 1.27+
if dir, file, ok := strings.CutLast(path, "/"); ok {
    // ...
}
```

`CutLast(s, sep string) (before, after string, found bool)` mirrors
`strings.Cut`; `bytes.CutLast` is the `[]byte` twin.

## `url.URL.Clone` and `url.Values.Clone`

```go
// ❌ Before — url.Values is map[string][]string; a map copy shares the slices
clone := url.Values{}
for k, v := range q {
    clone[k] = append([]string(nil), v...)
}

// ✅ Go 1.27+ — deep copies
clone := q.Clone()
u2 := u.Clone() // deep copy of every *url.URL field
```

## `big.Int.Divide`

```go
// ❌ Before — floor division by hand
q, r := new(big.Int).QuoRem(x, y, new(big.Int))
if r.Sign() != 0 && (r.Sign() < 0) != (y.Sign() < 0) {
    q.Sub(q, big.NewInt(1))
}

// ✅ Go 1.27+ — rounding mode: big.Trunc, big.Floor, big.Round, big.Ceil
q, r := new(big.Int).Divide(x, y, new(big.Int), big.Floor)
```

## Standard library `uuid`

```go
import "uuid"

id := uuid.NewV7()          // time-ordered: index-friendly primary keys
token := uuid.NewV4()       // random
parsed, err := uuid.Parse(s)
```

Keep `github.com/google/uuid` (or `gofrs/uuid`) when the code needs
name-based v3/v5 UUIDs, or relies on the library's `sql.Scanner` /
`driver.Valuer` methods — the stdlib type implements text marshaling only.
`go mod why -m github.com/google/uuid` shows who still needs it.

## `encoding/json`: the v2 engine and the v2 API

Two separate decisions:

1. **Free, no code change.** `encoding/json` now runs on the v2
   implementation. Behavior is preserved, unmarshaling is markedly faster,
   but **error text may differ** — tests that assert on JSON error strings
   need updating. `GOEXPERIMENT=nojsonv2` is a temporary escape hatch, not
   a steady state.
2. **Adopting the `encoding/json/v2` API changes semantics.** Migrate per
   call site, with tests against real payloads:

| Behavior | v1 `encoding/json` | `encoding/json/v2` |
|---|---|---|
| Duplicate object names | Last one wins | Rejected (`jsontext.AllowDuplicateNames`) |
| Invalid UTF-8 | Replaced with U+FFFD | Rejected (`jsontext.AllowInvalidUTF8`) |
| Field name matching | Case-insensitive | Case-sensitive (`MatchCaseInsensitiveNames`) |
| Nil slice / nil map | `null` | `[]` / `{}` (`FormatNilSliceAsNull`, `FormatNilMapAsNull`) |
| `omitempty` | Omits `false`, `0`, `""`, nil, empty slices/maps | Omits values that encode as empty JSON (`null`, `""`, `{}`, `[]`); `omitzero` for Go zero values |
| `[N]byte` | Array of numbers | Base64 string |
| `time.Duration` | Integer nanoseconds | Error unless `json.FormatDurationAsNano` is set |

```go
import jsonv2 "encoding/json/v2"

// Stream straight from the body — no intermediate []byte
if err := jsonv2.UnmarshalRead(r.Body, &req); err != nil {
    // ...
}
```

Use `encoding/json/jsontext` (`Encoder`, `Decoder`, `Token`, `Value`) for
token-level work instead of `json.RawMessage` juggling.

## Testing: `synctest.Sleep` and `httptest.NewTestServer`

```go
func TestRetryBackoff(t *testing.T) {
    synctest.Test(t, func(t *testing.T) {
        // In-memory network, compatible with the bubble; cleanup is registered on t.
        srv := httptest.NewTestServer(t, flakyHandler())

        go client.RunWithRetry(t.Context(), srv.Client())

        // ❌ Before: time.Sleep(2 * time.Second); synctest.Wait()
        synctest.Sleep(2 * time.Second) // ✅ advance the fake clock and let the bubble settle
        // assert on the number of attempts...
    })
}
```

`NewTestServer(t testing.TB, h http.Handler)` needs no `Start` and no
`Close`; its client reaches the server whatever host the URL names.
`httptest.NewServer` binds a real socket and cannot run inside a bubble.

## Diagnostics and tooling

- **Goroutine leak profile is GA** — `/debug/pprof/goroutineleak` and
  `pprof.Lookup("goroutineleak")`. Drop `GOEXPERIMENT=goroutineleakprofile`.
- **`go fix` modernizers** — new `atomictypes`, `embedlit`,
  `slicesbackward`, `unsafefuncs`; `waitgroup` is now `waitgroupgo`;
  `fmtappendf` is gone. Run `go fix ./...` after the upgrade.
- **`go doc`** — `go doc example.com/pkg@v1.2.3` reads a version not in
  `go.mod`; `-ex` lists executable examples.
- **`crypto/tls`** — `Config.Rand` is deprecated; deterministic tests use
  `testing/cryptotest.SetGlobalRandom`. New `crypto/mldsa` (FIPS 204), and
  `MLKEM1024` is available via `Config.CurvePreferences`.
- **`hash/maphash`** — `Hasher` and `ComparableHasher` give custom hash
  tables and Bloom filters a standard hashing contract.
- **`database/sql`** — `ConvertAssign` and `driver.RowsColumnScanner` are
  for driver authors, not application code.
