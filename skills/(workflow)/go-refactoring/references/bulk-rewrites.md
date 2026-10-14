# Bulk Mechanical Rewrites

When the same change lands at dozens of sites, write the change once as a
tool input instead of editing each site. The SKILL.md "Bulk Mechanical
Rewrites" section says which tool to reach for; this file has examples.

## Escalation ladder

| Tool | Understands | Use for |
|---|---|---|
| `gofmt -r` | Syntax, single expressions | Pure expression rewrites with no type questions |
| `//go:fix inline` + `go fix` (Go 1.26+) | Types, call sites in every package | Migrating callers off a function, constant or package you own |
| `eg` (`golang.org/x/tools/cmd/eg`) | Types, by example | Type-aware rewrites of expressions you don't own |
| `gopatch` (`github.com/uber-go/gopatch`) | Statements, imports | Multi-statement patterns, adding/removing imports |
| A `go/analysis` analyzer with `SuggestedFixes` | Everything | Repeated, project-specific migrations worth testing with golden files |

## `gofmt -r`

```bash
# Preview with -d, apply with -w. Lower-case single letters are wildcards.
gofmt -r 'bytes.Compare(a, b) == 0 -> bytes.Equal(a, b)' -d ./internal
gofmt -r 'bytes.Compare(a, b) == 0 -> bytes.Equal(a, b)' -w ./internal
```

## `//go:fix inline` — migrations that ride along with the code

```go
// Deprecated: use ProcessCtx.
//
//go:fix inline
func (s *Service) Process(id string) error {
    return s.ProcessCtx(context.Background(), id)
}
```

```bash
go fix ./...   # s.Process("a") becomes s.ProcessCtx(context.Background(), "a")
```

The directive also works on constants and on wrappers that forward to a
new import path (`pkg` → `pkg/v2`). For a library, downstream modules get
the migration the next time they run `go fix` — no coordinated PRs. Express
the old API in terms of the new one, so the inlined form is exactly what a
human would have written.

## `eg` — example-based, type-checked

```go
// template.go
package template

import ("errors"; "fmt")

func before(s string) error { return errors.New(fmt.Sprintf("%s", s)) }
func after(s string) error  { return fmt.Errorf("%s", s) }
```

```bash
go run golang.org/x/tools/cmd/eg@latest -t template.go -w ./...
```

## After any bulk rewrite

```bash
gofmt -l . && go vet ./... && go build ./... && go test ./...
git diff --stat   # the count should match the number of sites you expected
```

Read a sample of the diff. A rewrite that touched more files than expected
matched something you did not intend.
