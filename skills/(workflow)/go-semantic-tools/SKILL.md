---
name: go-semantic-tools
description: >
  Navigate and analyze Go codebases semantically with the toolchain instead of
  text search: gopls (references, implementations, call hierarchy, rename),
  go list for the dependency graph, and go doc for APIs.
  Use when: "find all callers", "who implements this interface", "where is this
  used", "trace the dependency graph", "explore this codebase", "find usages
  before changing", "map the module".
  Do NOT use for: performing the refactor itself (use go-refactoring),
  judging the architecture found (use go-architecture-review), or
  documentation writing (use go-documentation).
user-invocable: true
license: MIT
compatibility: Designed for Claude Code or similar AI coding agents working on Go projects. Requires the Go toolchain. Requires gopls (go install golang.org/x/tools/gopls@latest).
allowed-tools: Read Edit Write Glob Grep Bash(go:*) Bash(gofmt:*) Bash(gopls:*)
metadata:
  author: eduardo-sl
  version: "1.1.0"
---

# Go Semantic Tools

grep finds strings; the toolchain finds meaning. Method names repeat
across types, interfaces are satisfied implicitly, and dot-imports lie
to text search. Before changing shared code, get the truth from tools
that understand types.

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

## 5. When grep Is Still Right

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
