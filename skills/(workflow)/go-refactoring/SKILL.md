---
name: go-refactoring
description: >
  Safe refactoring workflow for Go: behavior-preserving steps, compiler-checked
  renames, extracting packages, breaking circular dependencies, and strangler
  migrations — always behind green tests.
  Use when: "refactor this", "rename across the codebase", "extract a package",
  "break this circular dependency", "split this god package", "migrate callers",
  "clean up without changing behavior".
  Do NOT use for: deciding the target architecture (use go-architecture-review),
  adopting new language features (use go-modernize), or performance rewrites
  (use go-performance-review).
license: MIT
metadata:
  version: "1.0.0"
---

# Go Refactoring Workflow

A refactor changes structure, never behavior. The definition of done is
mechanical: same tests pass before and after every step, and every step
is small enough to revert alone.

## 1. The Loop

1. **Baseline:** `go build ./... && go test ./...` must be green before
   touching anything. If tests are missing around the target code,
   write characterization tests FIRST — they pin current behavior,
   even if that behavior looks wrong.
2. **One transformation** from the catalog below.
3. **Verify:** build + tests + `go vet ./...`.
4. **Commit.** Never mix a refactor commit with a behavior change —
   reviewers can skim a `refactor:` commit; they must scrutinize a
   mixed one.
5. Repeat.

If step 3 fails and the fix isn't obvious in a minute, revert the step
rather than debugging a half-applied transformation.

## 2. Renames — Let Tools Do Them

```bash
# Preferred: gopls (understands types, interfaces, embedding)
gopls rename -w internal/service/user.go:#offset newName

# Module path or package import path changes:
# update go.mod, then rewrite imports mechanically
find . -name '*.go' -exec sed -i 's|github.com/acme/old|github.com/acme/new|g' {} +
go build ./...   # the compiler is the reviewer
```

Never rename an exported identifier of a published library without a
deprecation cycle: add the new name, mark the old one
`// Deprecated: use NewName.`, delete in the next major version.

## 3. Extract Package

Moving code out of a god package, in compiler-checked steps:

1. Create the new package; **move one type and its methods** (`gopls`
   or cut/paste), leaving everything else.
2. In the old package, add type aliases so nothing breaks:
   `type User = user.User` (aliases, `=`, not definitions).
3. Build. Migrate importers to the new path in batches; build each batch.
4. Delete the aliases when no importer remains.

This keeps every commit green with an arbitrarily large caller base.

## 4. Break a Circular Dependency

Packages `a → b` and `b → a` won't compile; near-cycles show up as
god packages. Three escapes, in order of preference:

1. **Extract the shared core:** both `a` and `b` actually depend on a
   type — move it to a third package `c` that imports nothing.
2. **Invert with an interface:** if `store` calls back into `service`,
   define the callback interface IN `store` (consumer side) and let
   `service` implement it. The arrow flips at compile time.
3. **Merge:** if two packages can't be described without each other,
   they were one package all along.

## 5. Change a Function Signature Safely

For exported functions with many callers:

```go
// Step 1 — add the new form alongside the old
func (s *Service) ProcessCtx(ctx context.Context, id string) error { ... }

// Step 2 — old form delegates; mark deprecated
// Deprecated: use ProcessCtx.
func (s *Service) Process(id string) error {
    return s.ProcessCtx(context.Background(), id)
}

// Step 3 — migrate callers batch by batch, building each batch
// Step 4 — delete the old form (same module) or keep until next major (library)
```

Inside a single module, prefer atomic signature changes when the
compiler can find every caller for you: change it, then chase the
build errors — that's the compiler enumerating your TODO list.

## 6. Strangler Migration for Subsystems

Replacing a subsystem (old store, legacy client) too big for one PR:

1. Define the consumer-side interface the callers actually need.
2. Make the OLD implementation satisfy it; wire callers to the interface.
3. Build the new implementation behind the same interface; test both
   implementations against one shared conformance test suite.
4. Switch the wiring in the composition root (one line, one commit,
   trivially revertible). Feature-flag it if risk warrants.
5. Delete the old implementation in its own commit.

## 7. What Is NOT a Refactor

- "While I'm here" bug fixes — separate commit before or after.
- Reordering struct fields used with positional literals, changing
  exported error strings callers match on, changing JSON tags —
  these are behavior changes wearing refactor clothes.
- Rewrites without tests. If you can't pin behavior first, you're not
  refactoring; you're gambling.

## Verification Checklist

1. Baseline build + tests green before the first change
2. Characterization tests added where coverage was missing
3. Each commit is one transformation; `refactor:` commits contain no behavior change
4. Renames done via gopls/compiler, not find-and-replace on identifiers
5. Package extractions used type aliases to stay green mid-flight
6. No new dependency cycles (`go build ./...` proves it)
7. Public API changes follow the deprecation cycle
8. `go vet ./...` and the full test suite pass at every commit, not just the last
9. git log reads as a sequence of safe, revertible steps
