# Metrics with OpenTelemetry / Prometheus

Metric definitions and HTTP instrumentation. The SKILL.md section states the
rules; this file has the code.

## Package-level definitions

```go
var (
    requestDuration = promauto.NewHistogramVec(
        prometheus.HistogramOpts{
            Name:    "http_request_duration_seconds",
            Help:    "Duration of HTTP requests in seconds.",
            Buckets: prometheus.DefBuckets,
        },
        []string{"method", "path", "status"},
    )

    requestsTotal = promauto.NewCounterVec(
        prometheus.CounterOpts{
            Name: "http_requests_total",
            Help: "Total number of HTTP requests.",
        },
        []string{"method", "path", "status"},
    )
)
```

## HTTP middleware

```go
func MetricsMiddleware(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        start := time.Now()
        ww := &responseWriter{ResponseWriter: w, statusCode: http.StatusOK}

        next.ServeHTTP(ww, r)

        // r.Pattern (Go 1.23+) is the matched ServeMux pattern, e.g.
        // "GET /users/{id}" — bounded, unlike r.URL.Path ("/users/42").
        // It is set when this middleware wraps the ServeMux directly.
        route := r.Pattern
        if route == "" {
            route = "unmatched"
        }
        duration := time.Since(start).Seconds()
        status := strconv.Itoa(ww.statusCode)

        requestDuration.WithLabelValues(r.Method, route, status).Observe(duration)
        requestsTotal.WithLabelValues(r.Method, route, status).Inc()
    })
}
```

With chi, read `chi.RouteContext(r.Context()).RoutePattern()` after
`next.ServeHTTP` instead.

## Cardinality

```go
// ✅ Good — bounded label values
requestsTotal.WithLabelValues(r.Method, routePattern, status)

// ❌ Bad — unbounded cardinality (user IDs, request IDs)
requestsTotal.WithLabelValues(r.Method, r.URL.Path, userID)
```
