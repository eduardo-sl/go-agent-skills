# Security Gates, Dependency Updates and AI Review

Workflow snippets for the SKILL.md sections 7-9. Action major versions in
these snippets are a snapshot; let Dependabot keep them current.

## Contents

- Static analysis: CodeQL and gosec
- Dependabot for modules and actions
- Pinning third-party actions
- Repository and workflow hardening
- Container image scanning
- AI-assisted review

## Static analysis: CodeQL and gosec

```yaml
  codeql:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      security-events: write   # upload results to the Security tab
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-go@v7
        with:
          go-version-file: go.mod
      - uses: github/codeql-action/init@v4
        with:
          languages: go
          queries: security-extended
      - uses: github/codeql-action/autobuild@v4
      - uses: github/codeql-action/analyze@v4

  gosec:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      security-events: write
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-go@v7
        with:
          go-version-file: go.mod
      # gosec pinned as a module tool: go get -tool github.com/securego/gosec/v2/cmd/gosec
      - run: go tool gosec -no-fail -fmt sarif -out gosec.sarif ./...
      - uses: github/codeql-action/upload-sarif@v4
        with:
          sarif_file: gosec.sarif
```

`-no-fail` keeps the job green while findings land in the Security tab;
drop it once the baseline is clean so new findings fail the PR.

## Dependabot for modules and actions

```yaml
# .github/dependabot.yml
version: 2
updates:
  - package-ecosystem: gomod
    directory: /
    schedule:
      interval: weekly
    groups:
      minor-and-patch:
        update-types: [minor, patch]   # one PR a week, not twenty
  - package-ecosystem: github-actions
    directory: /
    schedule:
      interval: weekly
    groups:
      actions:
        patterns: ["*"]
```

Major versions arrive as separate PRs on purpose — they are the ones that
need a changelog read. Renovate is the alternative when the repository
also needs Dockerfile or Makefile version bumps.

## Pinning third-party actions

```yaml
# A tag can be moved to malicious code; a commit SHA cannot.
- uses: golangci/golangci-lint-action@<40-character-commit-sha> # v9
```

Pin every action you do not own by SHA, with the version in a comment —
Dependabot updates SHA pins and keeps the comment in sync.

## Repository and workflow hardening

- `permissions: contents: read` at the top of every workflow; grant
  `security-events: write` or `pull-requests: write` per job, not globally.
- Never run code from a fork's PR in a workflow that has secrets:
  `pull_request_target` plus a checkout of the PR head is the classic
  credential theft.
- Branch protection on `main`: required status checks (build, lint, test,
  govulncheck), at least one review, no force pushes.
- Secret scanning and push protection on; secrets in environments with
  required reviewers for deploy jobs.

## Container image scanning

```yaml
      - run: docker build -t app:${{ github.sha }} .
      - uses: aquasecurity/trivy-action@<commit-sha> # pin by SHA, like every third-party action
        with:
          image-ref: app:${{ github.sha }}
          severity: CRITICAL,HIGH
          exit-code: "1"
          ignore-unfixed: true
```

Image size and base image choice belong to the go-binary-size skill.

## AI-assisted review

An AI reviewer loaded with these skills catches what linters cannot:
missing error context, goroutines without an exit, layering violations.

```yaml
name: ai-review
on:
  pull_request:
    types: [opened, synchronize]
permissions:
  contents: read
  pull-requests: write
jobs:
  review:
    # Secrets are not exposed to fork PRs; skip them instead of failing.
    if: github.event.pull_request.head.repo.full_name == github.repository
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
        with:
          fetch-depth: 0
      - name: Install Go skills
        run: |
          git clone --depth 1 https://github.com/eduardo-sl/go-agent-skills /tmp/go-agent-skills
          /tmp/go-agent-skills/scripts/install.sh . --agent claude --yes
      - uses: anthropics/claude-code-action@v1   # Claude Code; other agents have their own actions
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          prompt: |
            Review this pull request with the go-code-review skill. Report
            findings as inline comments with severity; do not modify files.
```

Treat the AI reviewer as an additional reviewer, never as a required
check that can merge on its own.
