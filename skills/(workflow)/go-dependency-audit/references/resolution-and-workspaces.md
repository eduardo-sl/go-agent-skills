# Resolving Conflicts, Workspaces and Tool Dependencies

Worked examples for the SKILL.md "Resolving Version Problems" section.

## Minimal version selection in one paragraph

Each module states the minimum version of each dependency it needs. Go
builds with the **highest of those minimums** — never "latest". So adding
a dependency can silently raise the version of a module you already use;
`go mod graph | grep 'github.com/shared/lib@'` shows who asked for what.

## `replace`, `exclude`, `retract`

```go
// go.mod (application)

// Temporary fork with a fix — always with an issue link and a removal plan
// TODO(#1234): drop once upstream releases the fix
replace github.com/foo/bar => github.com/myorg/bar v1.4.1-fix.1

// Never select a known-broken version, even if something requires it
exclude github.com/foo/bar v1.5.0
```

```go
// go.mod (a library you publish)

// Tell every consumer not to use versions you released by mistake
retract (
    v1.3.0           // published with a data-loss bug
    [v1.2.0, v1.2.3] // built against the wrong API
)
```

`replace` and `exclude` only apply in the main module — they do nothing
for people who import your library. `retract` is how a library speaks to
its consumers.

## Workspaces for local multi-module work

```bash
go work init ./service ./lib     # go.work: build service against the local lib
go work use ./another
go work sync
```

Keep `go.work` out of version control for ad-hoc local work (`.gitignore`
it); commit it only in a monorepo where every developer builds the same
set of modules together. It replaces committed `replace => ../lib`
directives.

## Tool dependencies (Go 1.24+)

```bash
go get -tool golang.org/x/vuln/cmd/govulncheck   # recorded in go.mod as a tool
go tool govulncheck ./...                       # same version for everyone
go get -tool golang.org/x/vuln/cmd/govulncheck@latest   # deliberate upgrade
```

This replaces the `tools.go` blank-import file. Tool dependencies count
toward the module graph, so audit them like any other dependency.
