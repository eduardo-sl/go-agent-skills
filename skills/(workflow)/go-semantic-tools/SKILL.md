---
name: go-semantic-tools
description: >
  Navigate and analyze Go codebases semantically with the toolchain instead
  of text search: gopls via its MCP server or CLI (references,
  implementations, call hierarchy, rename, extract/inline code actions,
  diagnostics), go list for the dependency graph, go doc for APIs. Use when:
  "find all callers", "who implements this interface", "where is this used",
  "trace the dependency graph", "explore this codebase", "find usages before
  changing", "map the module".
  Not for: performing the refactor (go-refactoring), judging the
  architecture (go-architecture-review), writing documentation
  (go-documentation).
user-invocable: true
license: MIT
compatibility: Designed for Claude Code or similar AI coding agents working on Go projects. Requires the Go toolchain. Requires gopls (go install golang.org/x/tools/gopls@latest); v0.20+ for the MCP server.
allowed-tools: Read Edit Write Glob Grep Bash(go:*) Bash(gofmt:*) Bash(gopls:*)
metadata:
  author: eduardo-sl
  version: "1.2.0"
---

# Go Semantic Tools

grep finds strings; the toolchain finds meaning. Method names repeat
across types, interfaces are satisfied implicitly, and dot-imports lie
to text search. Before changing shared code, get the truth from tools
that understand types.

Detailed reference material, loaded on demand:

- `references/mcp-and-code-actions.md` — `gopls mcp` setup and tools, the
  read/edit loop, CLI code actions, build-tag gotchas.

Read a reference file only when the summary below is not enough.

## 0. Pick the Interface

| Interface | Prefer it when |
|---|---|
| gopls MCP server (`gopls mcp`, v0.20+) | Working as an agent — tools take symbol names and file paths, not cursor positions |
| The harness's built-in LSP integration, if enabled | You already have a position, and want diagnostics pushed after every edit |
| `gopls` CLI (below) | Scripts and one-off checks; the Go team documents it as a debugging interface |

With the MCP server, follow its loop: `go_symbol_references` before
changing a definition, `go_diagnostics` after every edit until clean,
`go_vulncheck` after `go.mod` changes, then `go test` on the changed
packages only. Setup and the tool list: `references/mcp-and-code-actions.md`.

## 1. Choose the Tool

| Question | Command |
|---|---|
| Where is this symbol used? | `gopls references file.go:LINE:COL` |
| Where is it defined? | `gopls definition file.go:LINE:COL` |
| Who implements this interface? / which interfaces does this type satisfy? | `gopls implementation file.go:LINE:COL` |
| Who calls this function (transitively)? | `gopls call_hierarchy file.go:LINE:COL` |
| What's in this package's API? | `go doc ./internal/service` / `go doc pkg Symbol` |
| Which packages exist / depend on what? | `go list ./...`, `go list -deps`, `go list -json` |
| Find a symbol by name across the module | `gopls workspace_symbol Name` |
| Symbols in one file | `gopls symbols file.go` |

Positions are `file.go:line:column` (1-based). Get line/column from a
prior search or `gopls symbols`. All gopls commands run from within the
module and need a warm build cache — run `go build ./...` once first.

## 2. Standard Investigation Flows

### Before changing a function

```bash
gopls references internal/service/user.go:42:6   # every call site, typed
gopls call_hierarchy internal/service/user.go:42:6
```

Text search for `Process(` would surface every type's `Process`;
`references` returns only this one's call sites — including usages via
interfaces and embeddings that grep cannot see.

### Mapping an interface

```bash
# On the interface name: all implementations
gopls implementation internal/store/store.go:15:6

# On a method of a concrete type: interfaces it satisfies
gopls implementation internal/store/postgres/user.go:30:18
```

Run this before adding a method to an interface — every implementation
listed will break.

### Understanding the dependency graph

```bash
go list ./...                                    # all packages
go list -f '{{.ImportPath}} -> {{join .Imports " "}}' ./... # direct edges
go list -deps ./cmd/api | grep myorg             # everything a binary pulls in
go list -json ./internal/service | jq .Imports   # machine-readable
```

Use this to verify layering claims ("domain imports nothing") instead
of trusting directory names.

### Exploring an unfamiliar API

```bash
go doc ./internal/payments            # package overview
go doc ./internal/payments Gateway    # one symbol, with doc comment
go doc -all ./internal/payments       # full API surface
```

Prefer this to opening files: it shows the exported contract without
implementation noise.

## 3. Semantic Rename

```bash
gopls rename -w internal/service/user.go:42:6 ProcessOrder
```

Renames the symbol everywhere it's referenced — through interfaces,
embedding, and test packages. Never rename an identifier with
find-and-replace; `UserID` the field and `UserID` the local variable
are different symbols with the same spelling.

## 4. Diagnostics Without an Editor

```bash
gopls check ./internal/...   # type errors + analyzer findings per file
go vet ./...                 # the vet suite standalone
```

`gopls check` surfaces the same diagnostics an IDE user sees — run it
when reviewing code you haven't opened in an editor.

## 5. Refactoring Code Actions

```bash
gopls codeaction internal/order/service.go:42:2-58:3                     # list
gopls codeaction -kind=refactor.extract.function -exec -diff \
    internal/order/service.go:42:2-58:3                                  # preview
```

Extract (function, method, variable, constant, to new file), inline call,
fill struct/switch, invert `if`, remove an unused parameter at every call
site — each type-aware, unlike a hand edit. Diff before writing; extract
and inline are best-effort with comments.

## 6. When grep Is Still Right

- String literals: log messages, SQL, config keys, error text.
- Comments, TODOs, documentation.
- Code that doesn't compile yet — gopls needs a type-checkable package;
  grep works on broken trees.
- Quick existence checks ("is this env var referenced anywhere?").

Rule of thumb: identifiers → gopls; literals and prose → grep.

## Verification Checklist

1. Call sites enumerated with `gopls references` (not grep) before changing any shared symbol
2. Interface changes preceded by `gopls implementation` on the interface
3. Renames performed with `gopls rename -w`, never text replacement
4. Layering assumptions verified with `go list` import data
5. Unfamiliar packages explored via `go doc` before reading implementations
6. `gopls check` / `go vet` run when reviewing without an editor
7. grep reserved for literals, comments, and non-compiling code
8. Diagnostics checked after every edit (MCP `go_diagnostics` or `gopls check`)
9. Cross-platform symbols queried with the matching `GOOS`/build tags
