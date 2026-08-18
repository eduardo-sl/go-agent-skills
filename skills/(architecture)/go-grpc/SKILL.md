---
name: go-grpc
description: >
  gRPC services in Go beyond the basics: proto design, status codes and error
  details, interceptors, deadlines, streaming, health checks, and graceful
  shutdown.
  Use when: "gRPC service", "proto design", "gRPC error handling",
  "interceptor", "gRPC streaming", "gRPC deadline", "grpc health check",
  "gRPC status codes".
  Do NOT use for: REST/HTTP handler design (use go-api-design), protobuf-agnostic
  API layering (use go-architecture-review), or TLS hardening details
  (use go-security-audit).
user-invocable: true
license: MIT
compatibility: Designed for Claude Code or similar AI coding agents working on Go projects. Requires the Go toolchain. Requires protoc or buf for code generation.
allowed-tools: Read Edit Write Glob Grep Bash(go:*) Bash(gofmt:*) Bash(protoc:*) Bash(buf:*)
metadata:
  author: eduardo-sl
  version: "1.1.0"
---

# Go gRPC Services

gRPC's contract-first model only pays off if the contract is treated as
an API: versioned packages, deliberate error codes, deadlines
everywhere, and interceptors for everything cross-cutting.

## 1. Proto Design Rules

```protobuf
syntax = "proto3";

package payment.v1;                            // version IN the package
option go_package = "github.com/acme/payment-service/gen/payment/v1;paymentv1";

service PaymentService {
  rpc CreatePayment(CreatePaymentRequest) returns (CreatePaymentResponse);
}

message CreatePaymentRequest {                 // one request/response pair
  string order_id = 1;                         // per RPC, always — even if
  int64 amount_cents = 2;                      // empty today
}

message CreatePaymentResponse {
  Payment payment = 1;
}
```

- Version in the package (`payment.v1`); breaking change = `payment.v2`.
- Never reuse or renumber field tags; `reserved 3, 7;` deleted ones.
- Dedicated Request/Response messages per RPC — adding a field later is
  free; changing a shared message breaks every RPC using it.
- Generate with buf or a pinned protoc in `make generate`; commit
  generated code so builds don't depend on toolchain drift.

## 2. Errors: Status Codes, Not Strings

Return `status.Error`, mapping domain errors in ONE place:

```go
func (s *Server) CreatePayment(ctx context.Context, req *pb.CreatePaymentRequest) (*pb.CreatePaymentResponse, error) {
    p, err := s.svc.Create(ctx, toDomain(req))
    if err != nil {
        return nil, toStatus(err)
    }
    return &pb.CreatePaymentResponse{Payment: fromDomain(p)}, nil
}

func toStatus(err error) error {
    switch {
    case errors.Is(err, domain.ErrNotFound):
        return status.Error(codes.NotFound, "payment not found")
    case errors.Is(err, domain.ErrDuplicate):
        return status.Error(codes.AlreadyExists, "payment already exists")
    case errors.Is(err, context.DeadlineExceeded):
        return status.Error(codes.DeadlineExceeded, "timed out")
    default:
        return status.Error(codes.Internal, "internal error") // no details leak
    }
}
```

Code semantics that matter: `InvalidArgument` (bad request regardless
of state), `FailedPrecondition` (bad state), `NotFound`, `AlreadyExists`,
`Unauthenticated` vs `PermissionDenied`, `Unavailable` (retryable),
`Internal` (bug). Clients read codes with `status.FromError(err)` —
never parse messages.

## 3. Deadlines Are Mandatory

```go
// Client — every call gets a deadline
ctx, cancel := context.WithTimeout(ctx, 2*time.Second)
defer cancel()
resp, err := client.CreatePayment(ctx, req)

// Server — check before expensive work
if err := ctx.Err(); err != nil {
    return nil, status.FromContextError(err).Err()
}
```

The server inherits the client's deadline through the context. Pass
`ctx` into every downstream call (DB, other RPCs) so cancellation
propagates end to end.

## 4. Interceptors for Cross-Cutting Concerns

Handlers stay business-only; recovery, auth, logging, metrics live in
interceptors:

```go
srv := grpc.NewServer(
    grpc.ChainUnaryInterceptor(
        recoveryInterceptor,   // outermost: panic → codes.Internal
        loggingInterceptor,
        authInterceptor,
    ),
)

func loggingInterceptor(ctx context.Context, req any,
    info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (any, error) {
    start := time.Now()
    resp, err := handler(ctx, req)
    slog.InfoContext(ctx, "rpc",
        slog.String("method", info.FullMethod),
        slog.Duration("duration", time.Since(start)),
        slog.String("code", status.Code(err).String()),
    )
    return resp, err
}
```

Order matters: recovery first (outermost), then observability, then
auth. Streaming RPCs need the parallel `StreamInterceptor` versions.

## 5. Streaming

- **Server streaming** for large result sets: `stream.Send` in a loop,
  return non-nil error to abort with a status.
- **Client/bidi streaming** only when the protocol truly needs it —
  each open stream holds a goroutine and flow-control state.
- Always terminate on `ctx.Done()`:

```go
func (s *Server) WatchPayments(req *pb.WatchRequest, stream pb.PaymentService_WatchPaymentsServer) error {
    for {
        select {
        case <-stream.Context().Done():
            return status.FromContextError(stream.Context().Err()).Err()
        case ev := <-s.events:
            if err := stream.Send(toProto(ev)); err != nil {
                return err
            }
        }
    }
}
```

## 6. Production Server Setup

```go
lis, err := net.Listen("tcp", cfg.Addr)
if err != nil {
    return fmt.Errorf("listen: %w", err)
}

srv := grpc.NewServer(grpc.ChainUnaryInterceptor(...))
pb.RegisterPaymentServiceServer(srv, server)

healthSrv := health.NewServer() // grpc.health.v1 — load balancers need it
healthpb.RegisterHealthServer(srv, healthSrv)
reflection.Register(srv)        // grpcurl/debugging; gate on non-prod if policy requires

go func() {
    <-ctx.Done()
    stopped := make(chan struct{})
    go func() { srv.GracefulStop(); close(stopped) }()
    select {
    case <-stopped:                 // in-flight RPCs finished
    case <-time.After(10 * time.Second):
        srv.Stop()                  // force after grace period
    }
}()

return srv.Serve(lis)
```

## Verification Checklist

1. Proto packages versioned (`*.v1`); no tag reuse; `reserved` for removals
2. Dedicated Request/Response message per RPC
3. Generated code produced by a pinned tool (buf/protoc) and committed
4. All handler errors are `status.Error` with semantically correct codes
5. `codes.Internal` responses never leak internal error text
6. Every client call has a deadline; ctx propagated through all layers
7. Recovery, logging, auth implemented as chained interceptors (unary + stream)
8. Streams select on `stream.Context().Done()`
9. Health service registered; graceful stop with forced fallback
10. `grpcurl` smoke test (or generated client test) passes against the running server
