---
name: go-project-layout
description: >
  Scaffold new Go projects and services: directory structure, cmd/ and internal/
  conventions, when to use a flat layout, module naming, and main package wiring.
  Use when: "new Go project", "scaffold a service", "create project structure",
  "start a Go module", "how do I organize a new service", "set up folder structure".
  Do NOT use for: reviewing an existing architecture (use go-architecture-review),
  dependency injection wiring details (use go-dependency-injection), or
  CI pipeline setup (use go-ci).
license: MIT
metadata:
  version: "1.0.0"
---

# Go Project Layout

Structure follows size. The biggest layout mistake in Go is copying a
microservice skeleton for a 500-line tool — or growing a 50-package
service inside a flat directory. Match the layout to the project.

## 1. Pick the Layout by Project Size

| Project | Layout |
|---|---|
| Small tool, single binary, <5 files | Flat: everything in package `main` at the root |
| Library for others to import | Root package named after the module, `internal/` for helpers |
| Service with one binary | `cmd/<name>/main.go` + `internal/` packages |
| Multiple binaries sharing code | `cmd/<name1>/`, `cmd/<name2>/` + `internal/` |

Never start with empty `pkg/`, `api/`, `docs/`, `build/` directories
"for later". Add structure when the code demands it, not before.

## 2. Module Naming

```bash
# ✅ Good — repository path, lowercase
go mod init github.com/acme/payment-service

# ❌ Bad — not fetchable, uppercase, or vanity without DNS
go mod init PaymentService
go mod init payment_service
```

The last path element should match what users will see: for a library,
it becomes the default import name.

## 3. Service Layout (the default for APIs and workers)

```text
payment-service/
├── cmd/
│   └── payment-api/
│       └── main.go         # flag/env parsing, wiring, Run() — nothing else
├── internal/
│   ├── domain/             # core types, business rules; zero external deps
│   ├── service/            # use cases orchestrating domain + stores
│   ├── store/              # data access implementations (postgres/, redis/)
│   ├── handler/            # HTTP/gRPC adapters
│   └── config/             # config loading and validation
├── migrations/             # if the service owns a database
├── go.mod
├── Makefile
└── README.md
```

Rules:

- `internal/` by default — the compiler enforces that nobody outside the
  module imports it. Promote to a public package only on demand.
- `pkg/` only when external consumers exist AND the module also has
  private code. When in doubt, don't create it.
- Dependencies point inward: `handler → service → domain ← store`.
  `domain` imports neither `store` nor `handler`.

## 4. Thin main, Runnable Run

Keep `main.go` to wiring plus a delegating call, so the app is testable:

```go
func main() {
    if err := run(context.Background(), os.Args[1:], os.Getenv); err != nil {
        fmt.Fprintln(os.Stderr, err)
        os.Exit(1)
    }
}

func run(ctx context.Context, args []string, getenv func(string) string) error {
    cfg, err := config.Load(getenv)
    if err != nil {
        return fmt.Errorf("load config: %w", err)
    }

    db, err := store.Open(ctx, cfg.DatabaseURL)
    if err != nil {
        return fmt.Errorf("open db: %w", err)
    }
    defer db.Close()

    svc := service.New(store.NewUserRepo(db))
    srv := handler.NewServer(cfg.Addr, svc)
    return srv.ListenAndServe(ctx)
}
```

- `os.Exit` appears exactly once, in `main`.
- `run` takes its dependencies (`args`, `getenv`) so tests can call it.
- No `init()` functions for wiring — explicit construction order only.

## 5. Library Layout

```text
retry/
├── retry.go            # package retry — the API, in the root
├── retry_test.go
├── backoff.go          # same package, split by topic
├── internal/
│   └── clock/          # implementation details users must not import
├── examples_test.go    # Example* functions shown in godoc
└── go.mod
```

- The root directory IS the package. No `src/`, no `lib/`.
- One package per concept. Resist `util`, `common`, `helpers` — name
  packages after what they provide (`retry`, `clock`, `httpsign`).

## 6. Naming Rules for Directories and Packages

- Package name == directory name, short, lowercase, no underscores:
  `store/postgres`, not `store/postgres_impl`.
- Don't stutter: `payment.Service`, not `payment.PaymentService`.
- Binary names in `cmd/` are user-facing: `cmd/payment-api`,
  hyphenated is fine (directory only holds package `main`).

## 7. Files That Belong at the Root

- `go.mod`, `go.sum`, `README.md`, `LICENSE`, `Makefile`,
  `.golangci.yml`, `Dockerfile` (single-binary projects).
- Do NOT create: `src/` (un-idiomatic), `vendor/` (unless the team
  explicitly vendors), one-file packages like `types/` or `models/`
  that become dumping grounds.

## Scaffolding Procedure

1. Ask/decide: tool, library, or service? How many binaries?
2. `go mod init <repo-path>`.
3. Create only the directories the first feature needs.
4. Write `main.go` with the thin-main pattern above.
5. Add `Makefile` targets: `build`, `test`, `lint`.
6. Verify: `go build ./...` and `go vet ./...` pass on the skeleton.

## Verification Checklist

1. Layout matches project size — no empty scaffolding directories
2. Module path is the fetchable repository path
3. All non-public packages live under `internal/`
4. `main.go` is thin: parse, wire, call `run`, exit
5. `os.Exit` only in `main`; no wiring in `init()`
6. Dependencies flow inward; `domain` has zero infrastructure imports
7. No `util`/`common`/`helpers`/`models` grab-bag packages
8. Package names match directories, lowercase, no stutter
9. `go build ./...` passes on the fresh skeleton
