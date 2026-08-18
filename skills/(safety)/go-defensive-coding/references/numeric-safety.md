# Numeric Conversion, Overflow, and Comparison

Loaded on demand from `go-defensive-coding`.

## Conversion truncates, silently

Go's numeric conversions never panic and never report loss. Every narrowing
conversion is a potential silent corruption.

```go
var big int64 = 1 << 40
fmt.Println(int32(big)) // 0 — the high bits are simply gone

var neg int = -1
fmt.Println(uint32(neg)) // 4294967295
```

### Where this bites in real code

- `int32(len(s))` in a protocol encoder, on input larger than 2 GiB
- `int(header.Length)` on a 32-bit build, from an attacker-controlled field
- `uint(index - 1)` when `index` is 0
- `int8(userSuppliedInt)` for an enum or status code

`gosec` reports these as **G115**. Treat every G115 hit as a real finding
unless the value is provably bounded at the call site.

### Range-check helper

```go
func toInt32(v int64) (int32, error) {
    if v > math.MaxInt32 || v < math.MinInt32 {
        return 0, fmt.Errorf("value %d out of int32 range", v)
    }
    return int32(v), nil
}
```

For unsigned targets, check the negative case too:

```go
func toUint32(v int) (uint32, error) {
    if v < 0 || v > math.MaxUint32 {
        return 0, fmt.Errorf("value %d out of uint32 range", v)
    }
    return uint32(v), nil
}
```

Alternatively keep the wide type end to end. A conversion you never perform
cannot truncate.

## Arithmetic overflow

Signed overflow wraps; it does not panic and it is not undefined.

```go
var x int32 = math.MaxInt32
x++ // -2147483648
```

Detect it after the fact for addition and multiplication:

```go
// Addition: the sign flipped in a way it should not have
sum := a + b
if (b > 0 && sum < a) || (b < 0 && sum > a) {
    return 0, errors.New("integer overflow")
}

// Multiplication: verify by dividing back
if a != 0 {
    p := a * b
    if p/a != b {
        return 0, errors.New("integer overflow")
    }
}
```

Common sources: byte-count accumulation, `capacity * elementSize`, exponential
backoff doublings, and Unix timestamps in milliseconds on 32-bit types.

## Division

```go
// Integer division by zero panics
n := total / count // panic if count == 0

// ✅ Guard input-derived divisors
if count == 0 {
    return 0, errors.New("count must be non-zero")
}
```

Float division by zero does not panic:

```go
fmt.Println(1.0 / 0.0)  // +Inf
fmt.Println(-1.0 / 0.0) // -Inf
fmt.Println(0.0 / 0.0)  // NaN
```

An `Inf` or `NaN` then propagates through every downstream computation and
usually surfaces far from the cause, often as `NaN` in a metric or as
`json: unsupported value: NaN` at the serialisation boundary.

```go
if math.IsNaN(v) || math.IsInf(v, 0) {
    return fmt.Errorf("invalid result %v", v)
}
```

## Float comparison

Binary floats cannot represent most decimals exactly.

```go
fmt.Println(0.1+0.2 == 0.3) // false
```

Compare with a tolerance chosen for the domain:

```go
const eps = 1e-9

func almostEqual(a, b float64) bool {
    return math.Abs(a-b) <= eps
}
```

For values spanning many orders of magnitude, use a relative tolerance:

```go
func closeEnough(a, b, relTol float64) bool {
    if a == b {
        return true // handles both being ±Inf
    }
    return math.Abs(a-b) <= relTol*math.Max(math.Abs(a), math.Abs(b))
}
```

`NaN` is not equal to itself, so `almostEqual(math.NaN(), math.NaN())` is
false — check `math.IsNaN` explicitly when NaN is a legitimate input.

## Never use floats for money

```go
// ❌ Rounding error accumulates per operation
type Order struct{ TotalUSD float64 }

// ✅ Integer minor units
type Order struct{ TotalCents int64 }
```

If the domain needs arbitrary precision or decimal semantics (tax rates,
currency conversion), use `math/big.Rat` or a dedicated decimal package, and
say in the type name which unit is stored.

## Time comparison

`time.Time` contains a wall clock, a monotonic reading, and a location.
`==` compares all three; two logically identical instants can differ.

```go
// ❌ May be false for the same instant
if t1 == t2 { ... }

// ✅
if t1.Equal(t2) { ... }
```

Use `Before`/`After` for ordering, and `time.Since(start)` for durations —
it uses the monotonic clock and is immune to NTP steps. A duration computed
as `time.Now().Sub(t)` where `t` was round-tripped through JSON has lost its
monotonic reading and can go backwards.

Truncate before comparing timestamps that crossed a serialisation boundary
with lower resolution:

```go
if got.Truncate(time.Millisecond).Equal(want.Truncate(time.Millisecond)) { ... }
```

## Parsing input

`strconv.Atoi` returns `int`, whose width is platform-dependent. When the
value must fit a specific type, parse into it directly:

```go
// ✅ Parses and range-checks in one step
port, err := strconv.ParseUint(s, 10, 16)
if err != nil {
    return fmt.Errorf("invalid port %q: %w", s, err)
}
```

The `bitSize` argument makes `ParseInt`/`ParseUint`/`ParseFloat` return an
`ErrRange` error instead of a truncated value.

## Enforcement

```bash
gosec -include=G115 ./...        # integer conversion overflow
golangci-lint run --enable=durationcheck,gosec
go test -run TestOverflow -race ./...
```

Write a fuzz target for any parser that converts between numeric widths:

```go
func FuzzParseHeader(f *testing.F) {
    f.Add([]byte{0, 0, 0, 1})
    f.Fuzz(func(t *testing.T, data []byte) {
        _, _ = ParseHeader(data) // must not panic
    })
}
```
