# Errors, Authorization and Testing

Worked examples for SKILL.md sections 5-7.

## Error presenter

```go
srv.SetErrorPresenter(func(ctx context.Context, e error) *gqlerror.Error {
    err := graphql.DefaultErrorPresenter(ctx, e)

    var domainErr *domain.ValidationError
    if errors.As(e, &domainErr) {
        err.Message = domainErr.Message
        err.Extensions = map[string]any{"code": "VALIDATION_FAILED"}
        return err
    }

    slog.ErrorContext(ctx, "graphql resolver failed", "error", e)
    err.Message = "internal server error" // stable, safe
    err.Extensions = map[string]any{"code": "INTERNAL"}
    return err
})
```

## Field authorization directive

```graphql
directive @hasRole(role: Role!) on FIELD_DEFINITION

type User {
  id: ID!
  email: String! @hasRole(role: ADMIN)
}
```

```go
cfg.Directives.HasRole = func(ctx context.Context, obj any, next graphql.Resolver, role model.Role) (any, error) {
    if !auth.FromContext(ctx).HasRole(role) {
        return nil, gqlerror.Errorf("access denied")
    }
    return next(ctx)
}
```

## Testing

Build the server under test the way production builds it. `NewDefaultServer`
is deprecated: gqlgen documents it as unsuitable for production, and a test
against it exercises transports and caches you do not ship.

```go
func TestUserQuery(t *testing.T) {
    srv := handler.New(generated.NewExecutableSchema(cfg))
    srv.AddTransport(transport.POST{})
    c := client.New(srv)

    var resp struct {
        User struct{ ID, Email string }
    }
    c.MustPost(`{ user(id: "u-1") { id email } }`, &resp)

    require.Equal(t, "u-1", resp.User.ID)
}
```

Assert the query count for any resolver with a dataloader — that is the only
way an N+1 regression fails a build rather than a dashboard:

```go
require.Equal(t, 2, db.QueryCount(), "expected batched loads, got N+1")
```
