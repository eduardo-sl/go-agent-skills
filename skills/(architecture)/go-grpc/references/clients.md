# gRPC Clients

Connection setup, retries and keepalive. The SKILL.md "Clients" section
states the rules; this file has the code.

## One long-lived connection per target

```go
// grpc.NewClient replaces the deprecated Dial/DialContext. It connects
// lazily, on the first RPC, and the default resolver is "dns".
conn, err := grpc.NewClient("dns:///payments.internal:443",
    grpc.WithTransportCredentials(credentials.NewTLS(&tls.Config{MinVersion: tls.VersionTLS13})),
    grpc.WithDefaultServiceConfig(serviceConfig),
    grpc.WithKeepaliveParams(keepalive.ClientParameters{
        Time:    30 * time.Second, // ping an idle connection after this long
        Timeout: 10 * time.Second, // and drop it if the ping goes unanswered
    }),
)
if err != nil {
    return fmt.Errorf("payments client: %w", err)
}
defer conn.Close()

client := paymentv1.NewPaymentServiceClient(conn) // cheap; create freely
```

A `*grpc.ClientConn` multiplexes every RPC over HTTP/2 and reconnects by
itself. Create it once at startup and share it. A connection per request
pays a TCP+TLS handshake every time and defeats load balancing.

## Retries and load balancing via service config

```go
const serviceConfig = `{
  "loadBalancingConfig": [{"round_robin": {}}],
  "methodConfig": [{
    "name": [{"service": "payment.v1.PaymentService"}],
    "timeout": "2s",
    "retryPolicy": {
      "maxAttempts": 3,
      "initialBackoff": "0.1s",
      "maxBackoff": "1s",
      "backoffMultiplier": 2,
      "retryableStatusCodes": ["UNAVAILABLE"]
    }
  }]
}`
```

- Retry `UNAVAILABLE` only, and only for methods that are safe to repeat.
  Retrying `DEADLINE_EXCEEDED` multiplies load on a server that is already
  slow.
- `round_robin` spreads RPCs across every resolved backend; the default
  `pick_first` sends everything to one.
- Behind a Kubernetes `ClusterIP` service, DNS returns one virtual IP;
  use a headless service (or a mesh) for per-pod balancing.

## Keepalive must match on both sides

The server rejects pings more frequent than its enforcement policy
(default `MinTime` 5 minutes) and closes the connection with
`GOAWAY too_many_pings`. Configure the server to accept what clients send:

```go
srv := grpc.NewServer(
    grpc.KeepaliveEnforcementPolicy(keepalive.EnforcementPolicy{
        MinTime:             20 * time.Second, // below the client's 30s ping interval
        PermitWithoutStream: true,
    }),
    grpc.KeepaliveParams(keepalive.ServerParameters{
        MaxConnectionAge: 5 * time.Minute, // force reconnects so new pods get traffic
    }),
)
```

## Reading errors

```go
resp, err := client.CreatePayment(ctx, req)
switch status.Code(err) {
case codes.OK:
case codes.AlreadyExists:
    return ErrDuplicatePayment
case codes.Unavailable, codes.DeadlineExceeded:
    return fmt.Errorf("payments unavailable: %w", err) // caller may retry later
default:
    return fmt.Errorf("create payment: %w", err)
}
```
