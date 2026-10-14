# gopls MCP Server and Code Actions

The SKILL.md sections "Pick the Interface" and "Refactoring Code Actions"
state when to use these; this file has the setup and commands.

## The MCP server (gopls v0.20+)

```bash
gopls mcp                  # stdio; register this command with the agent harness
gopls mcp -instructions    # print the workflow gopls recommends to agents
```

Registering it with Claude Code:

```bash
claude mcp add gopls -- gopls mcp
```

Other MCP-capable harnesses take the same command (`gopls mcp`) in their
own MCP configuration file.

| Tool | Use it to |
|---|---|
| `go_workspace` | Learn whether this is a module, a `go.work` workspace or GOPATH — first call of a session |
| `go_search` | Fuzzy-find a type, function or variable by name |
| `go_file_context` | See what a file uses from the rest of its package, right after reading it |
| `go_package_api` | Read a package's exported API without opening its files |
| `go_symbol_references` | Every reference to a symbol, before changing it |
| `go_diagnostics` | Build and analysis errors for the files just edited |
| `go_vulncheck` | Reachable known vulnerabilities, after `go.mod` changes |

The server only sees files saved to disk.

## The edit loop gopls recommends

1. Read: `go_workspace`, `go_search`, `go_file_context`, `go_package_api`.
2. `go_symbol_references` on every definition you are about to change, and
   read the referencing files.
3. Make all the planned edits, call sites included.
4. `go_diagnostics` on every edited file; fix and repeat until clean.
5. `go_vulncheck` if `go.mod` changed.
6. `go test` on the changed packages only — not `./...` on every pass.

## Code actions from the CLI

```bash
# List the actions available for a range
gopls codeaction internal/order/service.go:42:2-58:3

# Preview, then apply, a specific kind
gopls codeaction -kind=refactor.extract.function -exec -diff internal/order/service.go:42:2-58:3
gopls codeaction -kind=refactor.extract.function -exec -write internal/order/service.go:42:2-58:3
```

| Kind | Does |
|---|---|
| `refactor.extract.function`, `.method`, `.variable`, `.constant` | Extract the selection |
| `refactor.extract.toNewFile` | Move declarations to a new file |
| `refactor.inline.call` | Inline a call, keeping argument side effects in temporaries |
| `refactor.rewrite.fillStruct`, `.fillSwitch` | Fill a literal's fields / a switch's cases |
| `refactor.rewrite.invertIf`, `.removeUnusedParam` | Invert an `if`/`else`; drop an unused parameter at every call site |
| `source.organizeImports` | Add and remove imports |

Only one action executes per invocation. Extract and inline are
best-effort: diff the result and check comments survived. Generated files
marked `DO NOT EDIT` get no actions.

## Gotchas

- Results reflect the build configuration of the file you query. A
  reference that only exists in `foo_windows.go` does not show up from a
  Linux query — set `GOOS`/`-tags` (via `GOFLAGS`) to match.
- Call hierarchy follows static calls only. Calls through interfaces and
  function values need `references` and `implementation` as well.
