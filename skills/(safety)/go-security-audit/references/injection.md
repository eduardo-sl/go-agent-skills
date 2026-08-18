# Input Validation and Injection

Boundary validation and query construction. The SKILL.md sections state the
rules; this file has the code.

## Validate at the HTTP boundary

```go
// ✅ Good — validate before use
func (h *Handler) handleCreate(w http.ResponseWriter, r *http.Request) {
    // Limit body size
    r.Body = http.MaxBytesReader(w, r.Body, 1<<20) // 1 MB

    var req CreateRequest
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        respondError(w, http.StatusBadRequest, "invalid JSON")
        return
    }

    if err := validate.Struct(req); err != nil {
        respondError(w, http.StatusBadRequest, "validation failed")
        return
    }
    // proceed with validated data
}
```

## String sanitization

```go
// Sanitize HTML to prevent XSS
import "github.com/microcosm-cc/bluemonday"

p := bluemonday.UGCPolicy()
sanitized := p.Sanitize(userInput)

// Validate email format
import "net/mail"
_, err := mail.ParseAddress(email)

// Validate URLs
u, err := url.Parse(input)
if err != nil || (u.Scheme != "http" && u.Scheme != "https") {
    // reject
}
```

## Parameterized queries

```go
// ✅ Good — parameterized
row := db.QueryRowContext(ctx,
    "SELECT id, name FROM users WHERE email = $1", email)

// ✅ Good — with sqlx named params
query := "SELECT * FROM users WHERE name = :name AND age > :age"
rows, err := db.NamedQueryContext(ctx, query, map[string]interface{}{
    "name": name,
    "age":  minAge,
})

// ❌ CRITICAL — string concatenation = SQL injection
query := "SELECT * FROM users WHERE email = '" + email + "'"
query := fmt.Sprintf("SELECT * FROM users WHERE id = %s", id)
```

## Dynamic WHERE clauses

When the set of filters is not known at compile time, build the placeholder
list — never the values.

```go
// ✅ Good — safe dynamic query building
var conditions []string
var args []interface{}
argIdx := 1

if name != "" {
    conditions = append(conditions, fmt.Sprintf("name = $%d", argIdx))
    args = append(args, name)
    argIdx++
}

query := "SELECT * FROM users"
if len(conditions) > 0 {
    query += " WHERE " + strings.Join(conditions, " AND ")
}
```
