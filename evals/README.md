# Skill Evaluations

A skill that does not change what the agent produces is a skill that costs
context for nothing. These evals exist to tell the difference.

## Method

Each case is a prompt plus assertions about the answer. Run the same suite
twice — once with the skills installed, once without — and compare.

```bash
# With the skills installed in the target project
scripts/run-evals.py --cmd 'claude -p "{prompt}"' --label with-skills

# In a project without them
scripts/run-evals.py --cmd 'claude -p "{prompt}"' --label baseline
```

The delta is the number that matters. A suite that scores 95% both ways is
telling you the model already knew; either the cases are too easy or the
skill is redundant.

```bash
scripts/run-evals.py --dry-run                      # print prompts, run nothing
scripts/run-evals.py --skill go-defensive-coding    # one suite
scripts/run-evals.py --cmd '...' --json > out.json  # machine-readable
```

`--cmd` takes any agent CLI. `{prompt}` is substituted into the command; if
it is absent, the prompt is written to the process's stdin instead.

## Case format

`evals/cases/<skill-name>.json`:

```json
{
  "skill": "go-defensive-coding",
  "cases": [
    {
      "id": "short-kebab-id",
      "prompt": "What the user would actually type.",
      "expect_all": ["regex that must match", "another"],
      "expect_none": ["regex that must not match"],
      "case_sensitive": false
    }
  ]
}
```

- `expect_all` — every pattern must match the answer. Assert the *behaviour*,
  not the wording: `slices\.Clone|copy\(` rather than a full sentence.
- `expect_none` — the anti-pattern the skill exists to prevent.
- Patterns are Python regexes, case-insensitive unless `case_sensitive` is set.

## Writing good cases

- Write the prompt as a user would type it, not as a quiz.
- Assert one behaviour per case, so a failure names the gap.
- Include at least one case that fails without the skill. A case the base
  model already passes measures nothing.
- Keep `expect_none` for genuine anti-patterns; do not use it to enforce
  phrasing.

## Results

Results are not committed. They depend on the model, its version, and the
day. Record the model and date alongside any number you publish.
