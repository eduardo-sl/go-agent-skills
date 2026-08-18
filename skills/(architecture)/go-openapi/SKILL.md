---
name: go-openapi
description: >
  Spec-first REST development in Go with OpenAPI: generating server
  interfaces and clients with oapi-codegen, request validation middleware,
  RFC 9457 error bodies, contract testing, and detecting breaking API
  changes. Use when the API has or should have an OpenAPI document, when
  wiring code generation into the build, or when a hand-written handler has
  drifted from its published contract. Trigger examples: "OpenAPI", "swagger
  spec", "oapi-codegen", "generate a client from the spec", "validate
  requests against the schema", "breaking API change".
  Not for: handler structure and shutdown (go-api-design), gRPC and protobuf
  (go-grpc), GraphQL schemas and resolvers (go-graphql).
user-invocable: true
license: MIT
compatibility: Designed for Claude Code or similar AI coding agents working on Go projects. Requires the Go toolchain. oapi-codegen, oasdiff and a spec linter (vacuum or spectral) are installed on demand.
allowed-tools: Read Edit Write Glob Grep Bash(go:*) Bash(gofmt:*) Bash(oapi-codegen:*) Bash(oasdiff:*) Bash(vacuum:*)
metadata:
  author: eduardo-sl
  version: "1.0.1"
---

# Go OpenAPI

The spec is the source of truth. Types, routes, and clients are generated from
it — never hand-written alongside it, because two hand-maintained copies of a
contract diverge within one sprint.

## Operating Modes

- **Adopt** — the project has hand-written handlers and no spec, or a spec
  nobody generates from. Introduce generation without a rewrite.
- **Extend** — the pipeline exists. Change the spec, regenerate, implement.
- **Review** — check that handlers, spec, and published client agree, and
  that the change is not silently breaking.

## 1. Choose the Generator Once

| Tool | Use it when |
|---|---|
| `oapi-codegen` | Default. Types + server interface + client, works with `net/http`, chi, echo, gin |
| `ogen` | You want a fully generated, strictly validating server and can accept its opinions |
| `swaggo/swag` | Only for a legacy code-first project you are not converting — annotations generate the spec, so the spec cannot be reviewed before the code exists |

Do not mix. A project with both annotations and a checked-in spec has two
sources of truth again.

## 2. Wire Generation Into the Build

Pin the generator as a module tool (Go 1.24+), so every developer and CI run
uses the same version:

```bash
go get -tool github.com/oapi-codegen/oapi-codegen/v2/cmd/oapi-codegen
```

```yaml
# oapi-codegen.yaml
package: api
output: internal/api/openapi.gen.go
generate:
  models: true
  std-http-server: true   # Go 1.22+ ServeMux; use chi-server / echo-server if that is the router
  strict-server: true     # typed request/response structs instead of raw http.ResponseWriter
  embedded-spec: true     # lets the service serve its own spec
output-options:
  skip-prune: false
```

```go
//go:generate go tool oapi-codegen -config oapi-codegen.yaml ../../api/openapi.yaml
```

Commit generated files. Reviewers need to see the diff of a contract change,
and a build must not depend on a generator being installed.

CI must fail when they are stale:

```bash
go generate ./... && git diff --exit-code
```

## 3. Implement the Generated Interface

Strict mode gives typed requests and responses, so the compiler enforces the
contract.

```go
// Generated: type StrictServerInterface interface { GetUser(ctx, GetUserRequestObject) (GetUserResponseObject, error) }

type Server struct{ users UserStore }

var _ api.StrictServerInterface = (*Server)(nil) // compile-time compliance

func (s *Server) GetUser(ctx context.Context, req api.GetUserRequestObject) (api.GetUserResponseObject, error) {
    u, err := s.users.Find(ctx, req.Id)
    if errors.Is(err, ErrNotFound) {
        return api.GetUser404JSONResponse{Title: "user not found", Status: 404}, nil
    }
    if err != nil {
        return nil, fmt.Errorf("find user %s: %w", req.Id, err) // 500 via the error handler
    }
    return api.GetUser200JSONResponse{Id: u.ID, Email: u.Email}, nil
}
```

Rules:

- Assert `var _ api.StrictServerInterface = (*Server)(nil)`. Adding an
  endpoint to the spec then becomes a compile error, not a 404 in staging.
- Return a typed response for every documented status. Return a Go `error`
  only for the undocumented failure path.
- Never edit `*.gen.go`. Every change starts in the YAML.

## 4. Validate Requests Against the Spec

Generated types check shape, not constraints. `minLength`, `pattern`,
`enum`, and `required` on query parameters are enforced only if you add the
validation middleware.

```go
spec, err := api.GetSwagger()
if err != nil {
    return fmt.Errorf("load spec: %w", err)
}
spec.Servers = nil // otherwise the server URL must match exactly

mux := http.NewServeMux()
handler := nethttpmiddleware.OapiRequestValidator(spec)(mux)
```

This rejects malformed input at the boundary with a 400 before any handler
runs. Keep domain validation in the domain — the middleware enforces the
contract, not the business rules.

## 5. Errors: RFC 9457 Problem Details

Define one error schema and reference it from every failure response.

```yaml
components:
  schemas:
    Problem:
      type: object
      required: [type, title, status]
      properties:
        type:   { type: string, format: uri, default: "about:blank" }
        title:  { type: string }
        status: { type: integer }
        detail: { type: string }
        instance: { type: string }
```

Serve it as `application/problem+json`. Never return a bare string, and never
put an internal error message in `detail` — log the wrapped error, return a
stable, safe title.

## 6. Versioning and Breaking Changes

Detect breaking changes mechanically; reviewers miss them.

```bash
go install github.com/oasdiff/oasdiff@latest
oasdiff breaking api/openapi.yaml.base api/openapi.yaml --fail-on ERR
```

Run it in CI against the spec on the main branch. Breaking, in practice:
removing an endpoint or field, narrowing a type, adding a required request
field or a required response field the client must understand, changing a
status code, removing an enum value from a response.

Additive changes are safe. Version the path (`/v2/...`) only when a break is
unavoidable, and keep the previous version serving until clients have moved.

## 7. Contract Testing

The spec is only a contract if something fails when the implementation
disagrees.

```go
func TestGetUser_MatchesSpec(t *testing.T) {
    spec, err := api.GetSwagger()
    require.NoError(t, err)
    spec.Servers = nil

    srv := httptest.NewServer(newTestHandler(t, spec))
    t.Cleanup(srv.Close)

    // Generated client — if the spec changed, this stops compiling
    c, err := api.NewClientWithResponses(srv.URL)
    require.NoError(t, err)

    resp, err := c.GetUserWithResponse(t.Context(), "u-1")
    require.NoError(t, err)
    require.Equal(t, http.StatusOK, resp.StatusCode())
    require.Equal(t, "u-1", resp.JSON200.Id)
}
```

Use the generated client in tests, not a hand-rolled `http.NewRequest`. It
turns contract drift into a compile failure.

## 8. Keep the Spec Reviewable

```bash
vacuum lint -d api/openapi.yaml     # or: spectral lint, redocly lint
```

- One file per API, under `api/`, checked in, reviewed like code.
- Every operation has an `operationId` — it becomes the Go method name.
- Every schema has a `description`; it becomes the godoc on the generated type.
- Split large specs with `$ref` to `components/`, not by generating fragments.

## Verification Checklist

1. Exactly one source of truth: a checked-in spec, no annotation generator alongside it
2. The generator is pinned via the `go.mod` tool directive
3. Generated files are committed and CI fails on `go generate` + `git diff --exit-code`
4. `var _ api.StrictServerInterface = (*Server)(nil)` present
5. No hand edits in `*.gen.go`
6. Request validation middleware installed and covered by a 400 test
7. Errors use a single `Problem` schema, served as `application/problem+json`
8. `oasdiff breaking` runs in CI against the base spec
9. At least one test drives the generated client against the real handler
10. The spec lints clean and every operation has an `operationId`
