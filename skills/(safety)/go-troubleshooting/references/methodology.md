# Debugging Method

How to get from a symptom to a root cause without guessing. SKILL.md
summarizes the loop; this file has the detail.

## The loop

1. **State expected vs actual** in one sentence each. A bug you cannot
   state precisely cannot be verified as fixed.
2. **Get the full evidence** — the whole panic, the whole log line with its
   trace ID, the exact input. Truncated stack traces hide the frame that
   matters.
3. **Reproduce in a test.** A failing test pins the bug, proves the fix,
   and stays as the regression guard. If it only fails in production,
   capture the input (request body, message, file) and replay it.
4. **Shrink the reproduction** until removing anything makes it pass.
5. **Form one hypothesis and test it** — change one thing, observe, keep or
   discard the hypothesis. Never stack changes.
6. **Find the cause, not the trigger.** Ask why the bad value existed, then
   why *that* happened, until you reach code that is wrong rather than code
   that received something wrong.
7. **Fix, then run the reproduction, the package tests and `-race`.**

## Trace before you blame

Before declaring a function buggy, find its callers (go-semantic-tools:
`gopls references`, call hierarchy) and check what they guarantee. A guard
clause upstream may make the "bug" unreachable — then the finding drops in
severity, and a short comment at the call site records why it is safe.

## When the cause is not in the code you are reading

```bash
# Which commit introduced it? Mark one good and one bad commit, then let git bisect.
git bisect start
git bisect bad HEAD
git bisect good v1.8.0
git bisect run go test -run 'TestTransfer$' ./internal/payments
```

Compare with an environment where it works: Go version (`go version -m
./bin/app`), module versions (`go list -m all`), `GOOS`/`GOARCH`, CGO,
environment variables, feature flags, and the data.

## Red flags in your own reasoning

Stop and go back to step 1 when you notice any of these:

- "Quick fix for now, investigate later" — later does not come.
- A fix you cannot explain ("maybe a nil check here helps").
- Several changes at once — whatever happens, you learn nothing.
- Each fix reveals a new problem — you are treating symptoms.
- Three failed fixes on the same bug — your mental model is wrong; reread
  the code and the evidence from scratch.
- Blaming the compiler, runtime or standard library before ruling out
  your own code — it is almost never Go.

## Escalating tools

Start with the cheapest tool that can answer the question: a focused
`t.Logf` or `slog.Debug` and one test run; then the race detector,
goroutine dumps and profiles; then delve; then execution traces. Each step
costs more setup and gives more detail.
