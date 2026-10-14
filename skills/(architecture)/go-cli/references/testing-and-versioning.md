# Testing, Versioning and Completions

Worked examples for the SKILL.md sections 7-9.

## Contents

- Exit code mapping in main
- Golden-file tests of `run`
- End-to-end scripts with testscript
- Version information
- Shell completions with Cobra

## Exit code mapping in main

```go
func main() {
    ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
    defer stop()
    go func() {
        <-ctx.Done()
        stop() // restore default handling: a second Ctrl+C kills immediately
    }()

    err := run(ctx, os.Args[1:], os.Stdin, os.Stdout, os.Stderr)
    switch {
    case err == nil, errors.Is(err, flag.ErrHelp):
        os.Exit(0) // -h is not a failure
    case errors.As(err, new(*usageError)):
        fmt.Fprintln(os.Stderr, err)
        os.Exit(2)
    case errors.Is(err, context.Canceled):
        os.Exit(130) // 128 + SIGINT, what shells expect after Ctrl+C
    default:
        fmt.Fprintln(os.Stderr, "error:", err)
        os.Exit(1)
    }
}

// usageError marks bad flags or arguments; run wraps fs.Parse errors in it.
type usageError struct{ err error }

func (e *usageError) Error() string { return e.err.Error() }
func (e *usageError) Unwrap() error { return e.err }
```

## Golden-file tests of `run`

```go
var update = flag.Bool("update", false, "rewrite golden files")

func TestConvert(t *testing.T) {
    var stdout, stderr bytes.Buffer
    err := run(t.Context(), []string{"convert", "testdata/in.yaml"}, nil, &stdout, &stderr)
    if err != nil {
        t.Fatalf("run: %v\nstderr: %s", err, stderr.String())
    }
    golden := filepath.Join("testdata", t.Name()+".golden")
    if *update {
        os.WriteFile(golden, stdout.Bytes(), 0o644)
    }
    want, _ := os.ReadFile(golden)
    if !bytes.Equal(stdout.Bytes(), want) {
        t.Errorf("stdout mismatch; run go test -update and review the diff")
    }
}
```

## End-to-end scripts with testscript

`github.com/rogpeppe/go-internal/testscript` runs `.txtar` scripts that
invoke the real binary — the format the Go command uses for its own tests:

```text
# testdata/script/convert.txtar
exec mytool convert in.yaml
stdout '"name": "demo"'
! stderr .

! exec mytool convert missing.yaml
stderr 'no such file'

-- in.yaml --
name: demo
```

## Version information

```go
func version() string {
    info, ok := debug.ReadBuildInfo()
    if !ok {
        return "unknown"
    }
    rev := ""
    for _, s := range info.Settings {
        if s.Key == "vcs.revision" {
            rev = s.Value
        }
    }
    // Go 1.24+: Main.Version comes from the VCS tag (or a pseudo-version)
    // when built from a checkout; older toolchains report "(devel)".
    return fmt.Sprintf("%s (%s, %s)", info.Main.Version, rev, info.GoVersion)
}
```

`go install example.com/mytool@v1.2.3` also records the version. When a
release tool builds from an archive without VCS metadata, inject it with
`-ldflags "-X main.version=$VERSION"`.

## Shell completions with Cobra

```go
// Cobra adds `mytool completion bash|zsh|fish|powershell` automatically.
cmd.ValidArgsFunction = func(cmd *cobra.Command, args []string, toComplete string) ([]cobra.Completion, cobra.ShellCompDirective) {
    return listProfiles(), cobra.ShellCompDirectiveNoFileComp // dynamic values
}
```
