# High-Throughput Logging

Worked examples for the SKILL.md High-Throughput Logging section.

`log/slog` is the right default for most services. But when benchmarks show
logging is a bottleneck (high-frequency hot paths, >100k log lines/sec),
consider zero-allocation loggers.

## When slog is not enough:

```go
// slog allocates per log call — fine for most services
slog.Info("request handled",
    slog.String("method", method),
    slog.Int("status", status),
)

// In hot paths where benchmarks prove logging is a bottleneck,
// use zap's zero-allocation core:
logger, _ := zap.NewProduction()
logger.Info("request handled",
    zap.String("method", method),
    zap.Int("status", status),
)
// zap avoids allocations by using a field pool and typed fields
```

## Decision tree:

| Scenario | Logger |
|---|---|
| General service logging | `log/slog` (stdlib, zero dependencies) |
| High-frequency hot path (>100k lines/sec) | `go.uber.org/zap` (zero-alloc) |
| Extreme throughput with JSON | `github.com/rs/zerolog` (zero-alloc JSON) |

## Best of both worlds — use zap as slog backend:

```go
// Use slog API everywhere, backed by zap's performance
zapLogger, _ := zap.NewProduction()
slogHandler := zapslog.NewHandler(zapLogger.Core(), nil)
logger := slog.New(slogHandler)

// Code uses standard slog API — can swap backend without changing callers
logger.Info("request handled",
    slog.String("method", method),
    slog.Int("status", status),
)
```

## Logging anti-patterns in hot paths:

```go
// ❌ Bad — logging inside tight loop
for _, item := range millions {
    slog.Info("processing item", slog.String("id", item.ID))
    process(item)
}

// ✅ Good — sample or batch log
for i, item := range millions {
    process(item)
    if i%10000 == 0 {
        slog.Info("progress", slog.Int("processed", i), slog.Int("total", len(millions)))
    }
}

// ✅ Good — log summary after loop
slog.Info("batch complete", slog.Int("count", len(millions)))
```

NEVER switch loggers without a benchmark proving the need.
`slog` is fast enough for the vast majority of Go services.
