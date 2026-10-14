# File Organization

Worked examples for SKILL.md sections 6 and 7.

## Grouping and Ordering

Group related declarations:

```go
const (
    _defaultPort    = 8080
    _defaultTimeout = 30 * time.Second
)

var (
    _validTypes  = map[string]bool{"json": true, "xml": true}
    _defaultUser = User{Name: "guest"}
)
```

Function ordering within a file:
1. Constants and variables
2. `New()` / constructor functions
3. Exported methods (sorted by importance, not alphabetically)
4. Unexported methods
5. Helper functions

Receiver methods should appear immediately after the type declaration.

## Line Length

Soft limit of 99 characters. Break long function signatures:

```go
func (s *Store) CreateUser(
    ctx context.Context,
    name string,
    email string,
    opts ...CreateOption,
) (*User, error) {
```
