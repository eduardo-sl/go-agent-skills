# Distributed Tracing with OpenTelemetry

Tracer setup, span creation, and telemetry shutdown. The SKILL.md section
states the rules; this file has the code.

## Tracer provider

```go
func initTracer(ctx context.Context, serviceName string) (*trace.TracerProvider, error) {
    exporter, err := otlptrace.New(ctx, otlptracehttp.NewClient())
    if err != nil {
        return nil, fmt.Errorf("create exporter: %w", err)
    }

    tp := trace.NewTracerProvider(
        trace.WithBatcher(exporter),
        trace.WithResource(resource.NewWithAttributes(
            semconv.SchemaURL,
            semconv.ServiceNameKey.String(serviceName),
        )),
    )
    otel.SetTracerProvider(tp)
    otel.SetTextMapPropagator(propagation.TraceContext{})

    return tp, nil
}
```

## Creating spans

```go
func (s *UserService) GetUser(ctx context.Context, id string) (*User, error) {
    ctx, span := otel.Tracer("user-service").Start(ctx, "GetUser")
    defer span.End()

    span.SetAttributes(attribute.String("user.id", id))

    user, err := s.store.FindByID(ctx, id)
    if err != nil {
        span.RecordError(err)
        span.SetStatus(codes.Error, err.Error())
        return nil, fmt.Errorf("get user %s: %w", id, err)
    }

    return user, nil
}
```

## Span naming

```go
// ✅ Good — operation name, not function name
ctx, span := tracer.Start(ctx, "GetUser")
ctx, span := tracer.Start(ctx, "db.query")
ctx, span := tracer.Start(ctx, "http.request")

// ❌ Bad — too verbose or too generic
ctx, span := tracer.Start(ctx, "github.com/myorg/myapp/internal/user.(*Service).GetUser")
ctx, span := tracer.Start(ctx, "doStuff")
```

## Propagating context

```go
// ✅ Good — context flows through
func (h *Handler) GetUser(w http.ResponseWriter, r *http.Request) {
    ctx := r.Context() // carries trace context from middleware
    user, err := h.service.GetUser(ctx, id)
    // ...
}

// ❌ Bad — trace context lost
func (h *Handler) GetUser(w http.ResponseWriter, r *http.Request) {
    user, err := h.service.GetUser(context.Background(), id) // breaks trace chain
    // ...
}
```

## Trace IDs in log entries

```go
func LogWithTrace(ctx context.Context, logger *slog.Logger) *slog.Logger {
    spanCtx := trace.SpanContextFromContext(ctx)
    if !spanCtx.IsValid() {
        return logger
    }
    return logger.With(
        slog.String("trace_id", spanCtx.TraceID().String()),
        slog.String("span_id", spanCtx.SpanID().String()),
    )
}

// Usage in handlers/services:
func (s *Service) Process(ctx context.Context) error {
    log := LogWithTrace(ctx, s.logger)
    log.Info("processing started") // log includes trace_id and span_id
    // ...
}
```

## Flushing on shutdown

Spans buffered by the batcher are lost if the process exits without a
shutdown call.

```go
func main() {
    ctx := context.Background()

    tp, err := initTracer(ctx, "my-service")
    if err != nil {
        log.Fatalf("init tracer: %v", err)
    }

    // Ensure all spans are flushed on shutdown
    defer func() {
        shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
        defer cancel()
        if err := tp.Shutdown(shutdownCtx); err != nil {
            log.Printf("tracer shutdown: %v", err)
        }
    }()

    // ... start server
}
```
