# Naming Before and After

Renames for every rule in SKILL.md, grouped by the mistake.

## Contents

- Packages
- Stuttering
- Initialisms and constants
- Getters, constructors and canonical methods
- Variables and receivers
- Interfaces and errors
- Enums and tests

## Packages

| Before | After | Why |
|---|---|---|
| `package utils` with `utils.FormatMoney` | `package money` with `money.Format` | The package names what it provides |
| `package models` holding every struct | Types live with the code that uses them (`order.Order`, `user.User`) | A grab-bag package couples everything to everything |
| `package user_service` | `package user` | No underscores; `service` adds nothing |
| `package orders` | `package order` | Singular, like `net/url`; `strings` and `bytes` are the rare exceptions |

## Stuttering

```go
// ❌ Before — every call site says it twice
package order

type OrderService struct{}
func NewOrderService() *OrderService
type OrderStatus int

// caller: order.NewOrderService(), order.OrderStatus

// ✅ After
package order

type Service struct{}
func NewService() *Service // or New() if Service is the package's main type
type Status int

// caller: order.NewService(), order.Status
```

## Initialisms and constants

```go
// ❌ Before
type HttpClient struct{ BaseUrl string; UserId int64 }
const MAX_RETRIES = 3
const Port8080 = 8080

// ✅ After
type HTTPClient struct{ BaseURL string; UserID int64 }
const MaxRetries = 3
const DefaultPort = 8080
```

Mixed-case initialisms are ambiguous at word boundaries (`HttpsUrl` —
`Https`+`Url`?) and disagree with the standard library (`http.ServeHTTP`,
`url.URL`). Within one identifier, a leading initialism takes the case of
the first letter: `urlParser` unexported, `URLParser` exported.

## Getters, constructors and canonical methods

```go
// ❌ Before
func (a *Account) GetBalance() Money
func (a *Account) BalanceSet(m Money)
func CreateAccount(owner string) *Account // in package account
func (a *Account) ToString() string
func ParseConfig(path string) *Config     // panics on error

// ✅ After
func (a *Account) Balance() Money
func (a *Account) SetBalance(m Money)
func New(owner string) *Account            // account.New("ann")
func (a *Account) String() string          // satisfies fmt.Stringer
func MustParseConfig(path string) *Config  // the name warns that it panics
```

`Close() error` on a type that does not release a resource, or a
`String()` that does I/O, breaks what every caller assumes those names
mean.

## Variables and receivers

```go
// ❌ Before
func (this *Server) Start() {}
func (srv *Server) Stop() {}          // receiver name differs per method

for index := 0; index < len(userSlice); index++ {
    currentUserObject := userSlice[index]
}

// ✅ After
func (s *Server) Start() {}
func (s *Server) Stop() {}

for i, u := range users {
    // ...
}
```

Wide scope earns a descriptive name; a three-line loop does not.

## Interfaces and errors

```go
// ❌ Before
type IUserRepository interface{ Find(id string) (*User, error) }
type UserFinderInterface interface{ Find(id string) (*User, error) }
var NotFound = errors.New("Not found.")
type ErrValidation struct{ Field string }

// ✅ After
type userFinder interface{ Find(id string) (*User, error) } // in the consumer package
var ErrNotFound = errors.New("user: not found")
type ValidationError struct{ Field string }
```

## Enums and tests

```go
// ❌ Before
const (
    Active = iota // zero value means "active" for an unset field
    Closed
)
func Test1(t *testing.T) {}
t.Run("Valid Input With Spaces", ...)

// ✅ After
type Status int

const (
    StatusUnknown Status = iota
    StatusActive
    StatusClosed
)
func TestParse(t *testing.T) {}
t.Run("trims surrounding spaces", ...)
```
