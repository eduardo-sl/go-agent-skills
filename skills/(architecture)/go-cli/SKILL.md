---
name: go-cli
description: >
  Build command-line tools in Go: flag handling, subcommands, stdin/stdout
  discipline, exit codes, signal handling, and when Cobra/Viper earn their
  weight over the standard library. Use when: "build a CLI", "add a
  subcommand", "parse flags", "exit codes", "handle Ctrl+C", "cobra
  command", "read from stdin", "CLI UX".
  Not for: HTTP APIs (go-api-design), scaffolding (go-project-layout),
  service configuration (go-architecture-review).
user-invocable: true
license: MIT
compatibility: Designed for Claude Code or similar AI coding agents working on Go projects. Requires the Go toolchain.
allowed-tools: Read Edit Write Glob Grep Bash(go:*) Bash(gofmt:*)
metadata:
  author: eduardo-sl
  version: "1.1.1"
---

# Go CLI Design

A good CLI is a well-behaved Unix citizen: flags before magic, stdout
for data, stderr for diagnostics, exit codes that scripts can trust,
and Ctrl+C that actually stops it.

## 1. Structure: Testable main

```go
func main() {
    ctx, stop := signal.NotifyContext(context.Background(),
        os.Interrupt, syscall.SIGTERM)
    defer stop()

    if err := run(ctx, os.Args[1:], os.Stdin, os.Stdout, os.Stderr); err != nil {
        fmt.Fprintln(os.Stderr, "error:", err)
        os.Exit(1)
    }
}

func run(ctx context.Context, args []string, stdin io.Reader, stdout, stderr io.Writer) error {
    fs := flag.NewFlagSet("mytool", flag.ContinueOnError)
    fs.SetOutput(stderr)
    verbose := fs.Bool("v", false, "verbose output")
    out := fs.String("o", "-", "output file (- for stdout)")
    if err := fs.Parse(args); err != nil {
        return err
    }
    // ...
    _ = verbose
    _ = out
    return nil
}
```

- `signal.NotifyContext` makes Ctrl+C cancel the context — every
  long operation takes `ctx` and stops cleanly.
- `run` receives args and streams — tests call it directly with
  `strings.Reader`/`bytes.Buffer`, no subprocess needed.
- `os.Exit` only in `main` (it skips defers).

## 2. stdout vs stderr

- **stdout**: the program's output — data, results, the thing you pipe.
- **stderr**: logs, progress, warnings, usage errors.
- `--json` or detecting a pipe (`!term.IsTerminal(int(os.Stdout.Fd()))`)
  should silence decorations, never change the data.

```go
// ✅ Good — result to stdout, progress to stderr
fmt.Fprintf(stderr, "processed %d files\n", n)
fmt.Fprintln(stdout, result)

// ❌ Bad — mixing both into stdout breaks every pipe
fmt.Printf("processing...\ndone: %s\n", result)
```

## 3. Exit Codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Generic runtime failure |
| 2 | Usage error (bad flags/arguments) — flag package's convention |
| >2 | Tool-specific, documented meanings (e.g. grep's 1 = no match) |

Map errors to codes in one place (`main`), not scattered `os.Exit`
calls. If scripts will branch on distinct failures, define sentinel
errors and translate: `errors.Is(err, ErrNoMatch) → 1`.

## 4. Flags and Arguments

- Flags for options, positional args for the primary operands:
  `mytool -v convert input.yaml`, not `mytool --input=input.yaml`.
- Every flag has a usage string; `-h`/`-help` output is your primary UX.
- Accept `-` as "stdin/stdout" for file arguments.
- Defaults must be safe: destructive behavior behind explicit flags
  (`--force`), never default-on.
- Read secrets from env or files, never from flags (`ps` leaks argv).

## 5. Subcommands

Standard library, fine up to a handful of commands:

```go
switch fs.Arg(0) {
case "serve":
    return runServe(ctx, fs.Args()[1:], stdout, stderr)
case "migrate":
    return runMigrate(ctx, fs.Args()[1:], stdout, stderr)
default:
    fmt.Fprintln(stderr, usage)
    return fmt.Errorf("unknown command %q", fs.Arg(0))
}
```

Adopt **Cobra** when you need nested commands, generated help/completions,
and many flags — the structure pays for the dependency:

```go
var rootCmd = &cobra.Command{Use: "mytool", SilenceUsage: true}

var serveCmd = &cobra.Command{
    Use:   "serve",
    Short: "Start the server",
    RunE: func(cmd *cobra.Command, args []string) error {
        return serve(cmd.Context(), addr) // RunE returns errors; no os.Exit
    },
}

func init() {
    serveCmd.Flags().StringVar(&addr, "addr", ":8080", "listen address")
    rootCmd.AddCommand(serveCmd)
}
```

Cobra rules: always `RunE` (never `Run` + `os.Exit`), set
`SilenceUsage: true` so runtime errors don't dump help, pass
`cmd.Context()` down. Add Viper only when layered config
(flags > env > file) is a real requirement — for most tools
`flag` + `os.Getenv` is enough.

## 6. Output for Humans and Machines

- `--json` flag for machine consumption; table/text default for humans.
- Never emit ANSI colors when stdout is not a terminal or `NO_COLOR`
  is set.
- Progress bars/spinners go to stderr and only when it's a terminal.

## Verification Checklist

1. `run(ctx, args, stdin, stdout, stderr)` pattern — logic testable without subprocess
2. `signal.NotifyContext` wired; long operations respect ctx cancellation
3. Data on stdout, diagnostics on stderr — verified by piping
4. Exit codes: 0 success, 2 usage, documented codes otherwise; `os.Exit` only in main
5. Every flag has usage text; `-h` output reviewed
6. `-` accepted for stdin/stdout where files are taken
7. Destructive actions require explicit flags
8. No secrets via argv
9. Cobra (if used): RunE everywhere, SilenceUsage, context propagated
10. Colors/spinners disabled for non-TTY and NO_COLOR
