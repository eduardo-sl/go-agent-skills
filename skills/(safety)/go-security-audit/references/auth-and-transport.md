# Auth, Secrets and Transport

Passwords, JWTs, authorization middleware, secret handling, TLS, headers and
rate limiting. The SKILL.md sections state the rules; this file has the code.

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

## TLS configuration

```go
tlsConfig := &tls.Config{
    MinVersion: tls.VersionTLS12,
    CipherSuites: []uint16{
        tls.TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,
        tls.TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,
    },
    PreferServerCipherSuites: true,
}

srv := &http.Server{
    TLSConfig: tlsConfig,
    // ...
}
```

## Rate limiting

```go
import "golang.org/x/time/rate"

type RateLimiter struct {
    limiters sync.Map
    rate     rate.Limit
    burst    int
}

func (rl *RateLimiter) Allow(key string) bool {
    limiter, _ := rl.limiters.LoadOrStore(key,
        rate.NewLimiter(rl.rate, rl.burst))
    return limiter.(*rate.Limiter).Allow()
}
```

Apply rate limiting to auth endpoints, public APIs, and any resource-intensive operations.
