---
name: go-graphql
description: >
  Build GraphQL servers in Go with gqlgen: schema-first generation, resolver
  structure, the N+1 problem and dataloaders, complexity and depth limits,
  error presentation, field-level authorization, and testing resolvers. Use
  when implementing or reviewing a GraphQL API, when a query fans out into
  hundreds of database calls, or when deciding what a resolver may expose.
  Trigger examples: "GraphQL", "gqlgen", "resolver", "N+1 queries",
  "dataloader", "query complexity limit", "GraphQL schema".
  Not for: REST and OpenAPI (go-openapi), gRPC (go-grpc), general HTTP
  middleware and shutdown (go-api-design).
user-invocable: true
license: MIT
compatibility: Designed for Claude Code or similar AI coding agents working on Go projects. Requires the Go toolchain. gqlgen is installed as a module tool.
allowed-tools: Read Edit Write Glob Grep Bash(go:*) Bash(gofmt:*) Bash(gqlgen:*)
metadata:
  author: eduardo-sl
  version: "1.0.1"
---

# Go GraphQL

GraphQL moves query planning to the client. That is the feature and the
danger: one innocuous query can become ten thousand database round trips, and
one over-permissive field can leak another tenant's data. Both are solved at
the server, not in the schema review.

## 1. Schema-First with gqlgen

The `.graphql` schema is the source of truth. gqlgen generates models,
resolver stubs, and the execution layer from it.

```bash
go get -tool github.com/99designs/gqlgen
go tool gqlgen init      # once
go tool gqlgen generate  # after every schema change
```

```yaml
# gqlgen.yml — bind generated types to your own models
models:
  User:
    model: github.com/myorg/app/internal/domain.User
  ID:
    model:
      - github.com/99designs/gqlgen/graphql.ID
      - github.com/99designs/gqlgen/graphql.Int64
```

Bind domain types explicitly. Left to itself gqlgen generates a parallel set
of anaemic structs, and every resolver becomes a mapping function.

Commit generated code, and fail CI when it is stale:

```bash
go tool gqlgen generate && git diff --exit-code
```

Never edit `generated.go` or `models_gen.go`. `resolver.go` and the
`*.resolvers.go` files are yours.

## 2. Resolvers Stay Thin

A resolver translates a GraphQL request into a service call. It contains no
business logic and no SQL.

```go
func (r *queryResolver) User(ctx context.Context, id string) (*domain.User, error) {
    u, err := r.users.Find(ctx, id)
    if errors.Is(err, domain.ErrNotFound) {
        return nil, nil // nullable field: absent, not an error
    }
    if err != nil {
        return nil, fmt.Errorf("find user %s: %w", id, err)
    }
    return u, nil
}
```

Inject dependencies through the `Resolver` struct, never through package
globals:

```go
type Resolver struct {
    users  UserService
    orders OrderService
    loader *Loaders
}
```

Always propagate `ctx`. It carries the request deadline, the authenticated
principal, and the per-request dataloaders.

## 3. The N+1 Problem — the one that matters

A field resolver on a list type runs once per element.

```go
// ❌ 1 query for the orders, then N queries for the users
func (r *orderResolver) Customer(ctx context.Context, obj *domain.Order) (*domain.User, error) {
    return r.users.Find(ctx, obj.CustomerID)
}
```

Batch with a dataloader. It collects the keys requested within a short window
and issues one query.

```go
import "github.com/vikstrous/dataloadgen"

type Loaders struct {
    UserByID *dataloadgen.Loader[string, *domain.User]
}

func NewLoaders(s UserService) *Loaders {
    return &Loaders{
        UserByID: dataloadgen.NewLoader(func(ctx context.Context, ids []string) ([]*domain.User, []error) {
            return s.FindMany(ctx, ids) // ONE query for all ids
        }, dataloadgen.WithWait(time.Millisecond)),
    }
}

// ✅ 1 query for the orders, 1 for all customers
func (r *orderResolver) Customer(ctx context.Context, obj *domain.Order) (*domain.User, error) {
    return loadersFrom(ctx).UserByID.Load(ctx, obj.CustomerID)
}
```

Loaders are **per request**, installed by middleware. A process-wide loader
caches across users and leaks data between them.

```go
func withLoaders(svc UserService, next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        ctx := context.WithValue(r.Context(), loadersKey{}, NewLoaders(svc))
        next.ServeHTTP(w, r.WithContext(ctx))
    })
}
```

The batch function must return results **in the order of the keys it was
given**, with a nil entry and an error per missing key. Returning a shorter
slice silently misaligns every result.

## 4. Bound Every Query

A public GraphQL endpoint without limits is a denial-of-service endpoint.

```go
srv := handler.New(generated.NewExecutableSchema(cfg))
srv.AddTransport(transport.POST{})
srv.SetQueryCache(lru.New[*ast.QueryDocument](1000))
srv.Use(extension.FixedComplexityLimit(300))
srv.Use(extension.AutomaticPersistedQuery{Cache: lru.New[string](100)})
```

- **Complexity limit** — assign a cost per field, higher for list fields with
  a large `first`. Start at a number your slowest legitimate query fits under,
  then measure.
- **Depth** — recursive types (`user { orders { customer { orders ... } } }`)
  must be bounded. gqlgen has no built-in depth limit; enforce it in an
  operation middleware.
- **Pagination is mandatory** on every list field. A field returning an
  unbounded list is a schema bug.
- **Introspection** is only enabled if you install `extension.Introspection`.
  Do not install it in production, or gate it behind an authenticated role.
- **Persisted queries** let a public client send a hash instead of a document,
  so the server executes only queries you shipped.

Set `srv.AroundOperations` to enforce a per-operation timeout, and always run
behind an `http.Server` with `ReadTimeout` and `WriteTimeout` set.

## 5. Errors

GraphQL returns 200 with an `errors` array. Never leak internals into it.

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

Use `srv.SetRecoverFunc` to convert a resolver panic into an error instead of
killing the connection, and log it with the stack.

Remember the nullability rule: an error on a non-null field nulls out its
nearest nullable ancestor. Make a field non-null only when it can never
legitimately be absent.

## 6. Authorization Belongs on the Field

Object-level checks are not enough — a client can reach an object through
several paths.

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

Authenticate in HTTP middleware, before the GraphQL handler. Authorize in the
directive or the resolver, using the principal from the context — never from
a query argument.

## 7. Testing

```go
func TestUserQuery(t *testing.T) {
    c := client.New(handler.NewDefaultServer(generated.NewExecutableSchema(cfg)))

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

## Verification Checklist

1. Schema is the source of truth; generated files are committed and CI-checked
2. Generated types bind to domain models via `gqlgen.yml`
3. Resolvers contain no business logic and always propagate `ctx`
4. Every list-field resolver that fetches by ID goes through a dataloader
5. Dataloaders are constructed per request, never shared across requests
6. Batch functions return one result per key, in key order
7. A complexity limit and a depth bound are configured and tested
8. Every list field is paginated
9. Introspection is disabled or role-gated in production
10. An error presenter strips internal errors; a recover func is installed
11. Authorization is enforced per field, from the context principal
12. A test asserts the query count for at least one batched field
