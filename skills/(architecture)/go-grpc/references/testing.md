# Testing gRPC Services

In-memory tests over `bufconn`. The SKILL.md "Testing" section states the
rules; this file has the code.

## A real server and client, no network

```go
func newTestClient(t *testing.T, impl paymentv1.PaymentServiceServer) paymentv1.PaymentServiceClient {
    t.Helper()
    lis := bufconn.Listen(1 << 20)

    // Same interceptors as production, or the test skips auth and recovery.
    srv := grpc.NewServer(grpc.ChainUnaryInterceptor(recoveryInterceptor, authInterceptor))
    paymentv1.RegisterPaymentServiceServer(srv, impl)
    go srv.Serve(lis)
    t.Cleanup(srv.Stop)

    // NewClient resolves with "dns" by default; "passthrough" hands the
    // address straight to the dialer, which ignores it.
    conn, err := grpc.NewClient("passthrough:///bufnet",
        grpc.WithContextDialer(func(ctx context.Context, _ string) (net.Conn, error) {
            return lis.DialContext(ctx)
        }),
        grpc.WithTransportCredentials(insecure.NewCredentials()),
    )
    if err != nil {
        t.Fatal(err)
    }
    t.Cleanup(func() { conn.Close() })
    return paymentv1.NewPaymentServiceClient(conn)
}
```

## Assert on codes

```go
func TestCreatePayment_Duplicate(t *testing.T) {
    client := newTestClient(t, newServer(fakeStoreWith(existingPayment)))
    ctx, cancel := context.WithTimeout(t.Context(), 2*time.Second)
    defer cancel()

    _, err := client.CreatePayment(ctx, &paymentv1.CreatePaymentRequest{OrderId: "o-1"})
    if got := status.Code(err); got != codes.AlreadyExists {
        t.Fatalf("code = %v, want AlreadyExists", got)
    }
}
```

Exercising the generated client over `bufconn` tests serialization,
interceptors, metadata and status mapping — calling the handler method
directly tests none of them.
