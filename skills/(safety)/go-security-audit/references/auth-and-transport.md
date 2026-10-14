# Auth, Secrets and Transport

Passwords, JWTs, authorization middleware, secret handling, TLS, headers and
rate limiting. The SKILL.md sections state the rules; this file has the code.

## Contents

- Password hashing
- JWT validation
- Authorization middleware
- Secrets
- Security headers
- Cookies
- CSRF (Go 1.25+)
- CORS
- TLS configuration
- Rate limiting

## Password hashing

```go
import "golang.org/x/crypto/bcrypt"

// Hash password
hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)

// Verify password — constant-time comparison built in
err := bcrypt.CompareHashAndPassword(hash, []byte(password))
```

## JWT validation

```go
// ✅ Always validate:
// 1. Signature (algorithm must match expectation)
// 2. Expiration (exp claim)
// 3. Issuer (iss claim)
// 4. Audience (aud claim)

// ❌ CRITICAL — never disable signature verification
// ❌ CRITICAL — never accept "alg": "none"
// ❌ CRITICAL — never hardcode signing keys in source code
```

## Authorization middleware

```go
func RequireRole(role string) func(http.Handler) http.Handler {
    return func(next http.Handler) http.Handler {
        return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
            user := UserFromContext(r.Context())
            if user == nil || !user.HasRole(role) {
                http.Error(w, "forbidden", http.StatusForbidden)
                return
            }
            next.ServeHTTP(w, r)
        })
    }
}
```

## Secrets

```go
// ✅ Good — from environment
dbURL := os.Getenv("DATABASE_URL")

// ✅ Good — from secrets manager
secret, err := secretsManager.GetSecret(ctx, "api-key")

// ❌ CRITICAL
const apiKey = "EXAMPLE-NOT-A-REAL-KEY" // hardcoded secret
```

### Use `.gitignore`:

```text
.env
*.pem
*.key
credentials.json
```

### Scan for leaked secrets:

```bash
# Use gitleaks in CI
gitleaks detect --source=. --verbose
```

## Security headers

```go
func SecurityHeaders(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        w.Header().Set("X-Content-Type-Options", "nosniff")
        w.Header().Set("X-Frame-Options", "DENY")
        w.Header().Set("Content-Security-Policy", "default-src 'self'")
        w.Header().Set("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
        w.Header().Set("X-XSS-Protection", "0") // modern browsers handle this
        next.ServeHTTP(w, r)
    })
}
```

## Cookies

```go
http.SetCookie(w, &http.Cookie{
    Name:     "__Host-session", // __Host-: Secure, Path=/, no Domain — cannot be set by a subdomain
    Value:    sessionID,         // opaque, from crypto/rand; never user data
    Path:     "/",
    Secure:   true,              // HTTPS only
    HttpOnly: true,              // invisible to JavaScript (XSS cannot read it)
    SameSite: http.SameSiteLaxMode,
    MaxAge:   int((8 * time.Hour).Seconds()),
})
```

Rotate the session ID on login and privilege change (session fixation).

## CSRF (Go 1.25+)

```go
cop := http.NewCrossOriginProtection()
if err := cop.AddTrustedOrigin("https://admin.example.com"); err != nil {
    return err
}
srv := &http.Server{Handler: cop.Handler(mux)}
```

It rejects non-safe cross-origin browser requests using `Sec-Fetch-Site`
(and `Origin` vs `Host`), and always allows GET, HEAD and OPTIONS — so
those methods must never change state.

## CORS

- Allowlist exact origins; never reflect the request's `Origin` blindly.
- `Access-Control-Allow-Origin: *` is incompatible with credentials — and
  a wildcard on an authenticated API is a finding even without them.
- CORS relaxes the browser's protection. It is not an access control on
  the server.

## TLS configuration

```go
// ✅ Raise the floor; let Go choose the suites
tlsConfig := &tls.Config{
    MinVersion: tls.VersionTLS12, // tls.VersionTLS13 if every client supports it
}

srv := &http.Server{
    TLSConfig: tlsConfig,
    // ...
}

// ❌ Stale hardening
tlsConfig := &tls.Config{
    CipherSuites: []uint16{ /* RSA-only list: breaks ECDSA certificates */ },
    PreferServerCipherSuites: true, // deprecated and ignored since Go 1.18
}
```

Go's defaults already drop RSA key exchange (Go 1.22) and 3DES (Go 1.23),
and enable the hybrid post-quantum `X25519MLKEM768` key exchange (Go 1.24).
TLS 1.3 suites cannot be configured at all. Set `CipherSuites` only when a
named compliance regime requires a specific list, and record which one.

## Rate limiting

```go
import "golang.org/x/time/rate"

type client struct {
    lim      *rate.Limiter
    lastSeen time.Time
}

type RateLimiter struct {
    mu      sync.Mutex
    clients map[string]*client
    rate    rate.Limit
    burst   int
}

func (rl *RateLimiter) Allow(key string) bool {
    rl.mu.Lock()
    defer rl.mu.Unlock()

    c, ok := rl.clients[key]
    if !ok {
        c = &client{lim: rate.NewLimiter(rl.rate, rl.burst)}
        rl.clients[key] = c
    }
    c.lastSeen = time.Now()
    return c.lim.Allow()
}

// Evict drops clients idle longer than ttl. Call it from a ticker owned by
// the server's lifecycle. Without eviction the map gains one entry per
// distinct key forever.
func (rl *RateLimiter) Evict(ttl time.Duration) {
    rl.mu.Lock()
    defer rl.mu.Unlock()

    for k, c := range rl.clients {
        if time.Since(c.lastSeen) > ttl {
            delete(rl.clients, k)
        }
    }
}
```

A per-key limiter map with no eviction is itself a denial-of-service
vector: an attacker who rotates source addresses or tokens grows it until
the process runs out of memory.

- Key on the authenticated identity, or on `r.RemoteAddr`. Trust
  `X-Forwarded-For` only when a proxy you control sets it.
- Apply rate limiting to auth endpoints, public APIs, and any
  resource-intensive operations.
