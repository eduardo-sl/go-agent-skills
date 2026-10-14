# Input Validation and Injection

Boundary validation and query construction. The SKILL.md sections state the
rules; this file has the code.

## Contents

- Validate at the HTTP boundary
- String sanitization
- Parameterized queries
- Dynamic WHERE clauses
- Command injection
- Server-side request forgery (SSRF)
- Path traversal
- Archives: zip slip and decompression bombs
- Templates and XSS
- Open redirects
- Log injection

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
rows, err := db.NamedQueryContext(ctx, query, map[string]any{
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
var args []any
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

## Command injection

```go
// ❌ CRITICAL — a shell parses the input: name = "x; rm -rf ~"
exec.Command("sh", "-c", "convert "+name+" out.png")

// ✅ No shell; arguments go straight to the program. "--" stops a value
// that starts with "-" from being read as a flag (argument injection).
cmd := exec.CommandContext(ctx, "convert", "--", name, "out.png")
```

Never let input choose the binary, and validate values that a tool will
interpret (URLs for `curl`, refs for `git`).

## Server-side request forgery (SSRF)

When the server fetches a URL the caller supplies, block private targets
at dial time — after DNS resolution, so a hostname pointing at
`169.254.169.254` (cloud metadata) is still caught:

```go
func ssrfSafeClient() *http.Client {
    dialer := &net.Dialer{
        Timeout: 5 * time.Second,
        Control: func(network, address string, _ syscall.RawConn) error {
            ap, err := netip.ParseAddrPort(address) // the resolved IP:port
            if err != nil {
                return err
            }
            ip := ap.Addr().Unmap()
            if ip.IsLoopback() || ip.IsPrivate() || ip.IsLinkLocalUnicast() ||
                ip.IsLinkLocalMulticast() || ip.IsMulticast() || ip.IsUnspecified() {
                return fmt.Errorf("blocked destination %s", ip)
            }
            return nil
        },
    }
    t := http.DefaultTransport.(*http.Transport).Clone()
    t.DialContext = dialer.DialContext
    t.Proxy = nil // a proxy would dial on our behalf and bypass Control
    return &http.Client{
        Timeout:   10 * time.Second,
        Transport: t, // redirects reuse the transport, so they are checked too
    }
}
```

Also accept only `http`/`https`, and add carrier-grade NAT (`100.64.0.0/10`)
and any internal ranges your network uses — `IsPrivate` does not cover them.

## Path traversal

```go
// ❌ "../../etc/passwd" walks out; a HasPrefix check misses symlinks and "/data2"
data, err := os.ReadFile(filepath.Join(baseDir, userPath))

// ✅ Go 1.24+: every operation is confined to baseDir, symlinks included
root, err := os.OpenRoot(baseDir)
if err != nil {
    return err
}
defer root.Close()
data, err := root.ReadFile(userPath)
```

Before Go 1.24, reject anything for which `filepath.IsLocal(userPath)` is
false — it still does not protect against symlinks inside the directory.

## Archives: zip slip and decompression bombs

```go
for _, f := range zr.File {
    if !filepath.IsLocal(f.Name) { // "../" or absolute entry names
        return fmt.Errorf("unsafe entry %q", f.Name)
    }
    if extracted += f.UncompressedSize64; extracted > maxTotal { // header can lie...
        return errors.New("archive too large")
    }
    rc, err := f.Open()
    if err != nil {
        return err
    }
    // ...so cap what is actually read as well
    _, err = io.Copy(dst, io.LimitReader(rc, maxEntry))
    rc.Close()
    if err != nil {
        return err
    }
}
```

Cap the entry count too, and apply `io.LimitReader` to every
`gzip.Reader`, which is a decompression bomb waiting for input.

## Templates and XSS

- `html/template` escapes by context (HTML, attribute, JS, URL);
  `text/template` escapes nothing — never use it to render HTML.
- `template.HTML(s)`, `template.JS(s)` and `template.URL(s)` switch the
  escaping off. They are only safe on values you produced, never on input.
- JSON APIs: set `Content-Type: application/json` and `nosniff`, so a
  browser never renders a response as HTML.

## Open redirects

```go
// ✅ Only same-site relative paths; "//evil.com" and "/\evil.com" are other hosts
func safeNext(next string) string {
    if strings.HasPrefix(next, "/") && !strings.HasPrefix(next, "//") &&
        !strings.Contains(next, "\\") {
        return next
    }
    return "/"
}
```

## Log injection

Input containing `\n` can forge extra lines in a text log. The slog JSON
handler escapes it; with text output, log user values with `%q` or as
`slog` attributes, never concatenated into the message.
