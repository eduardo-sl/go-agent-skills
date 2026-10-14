# GoReleaser Configuration and Release Workflow

A complete setup for SKILL.md section 4: build, archive, checksum, SBOM,
sign, attest. Action and tool versions are a snapshot — let Dependabot
keep them current.

## Contents

- `.goreleaser.yaml`
- Release workflow
- Local dry run
- Libraries

## `.goreleaser.yaml`

```yaml
version: 2

before:
  hooks:
    - go mod tidy
    - go mod verify

builds:
  - id: api
    main: ./cmd/api
    binary: api
    env:
      - CGO_ENABLED=0
    flags:
      - -trimpath
    ldflags:
      - -s -w
      - -X main.version={{.Version}}
      - -X main.commit={{.Commit}}
      - -X main.date={{.CommitDate}}      # commit time, not build time
    mod_timestamp: "{{ .CommitTimestamp }}" # reproducible file times
    goos: [linux, darwin, windows]
    goarch: [amd64, arm64]

archives:
  - formats: [tar.gz]
    format_overrides:
      - goos: windows
        formats: [zip]
    files:
      - LICENSE
      - README.md

checksum:
  name_template: checksums.txt

sboms:
  - artifacts: archive          # one SPDX SBOM per archive, via syft

signs:
  - cmd: cosign
    signature: "${artifact}.sigstore.json"
    args:
      - sign-blob
      - "--bundle=${signature}"
      - "${artifact}"
      - "--yes"
    artifacts: checksum         # sign checksums.txt; it covers every archive

changelog:
  use: github
  groups:
    - title: Features
      regexp: '^.*?feat(\(.+\))??!?:.+$'
      order: 0
    - title: Bug fixes
      regexp: '^.*?fix(\(.+\))??!?:.+$'
      order: 1
    - title: Other
      order: 999
```

## Release workflow

```yaml
# .github/workflows/release.yml
name: release
on:
  push:
    tags: ["v*"]

permissions:
  contents: write           # create the GitHub release
  id-token: write           # OIDC identity for keyless cosign and attestations
  attestations: write       # store the provenance attestation
  artifact-metadata: write  # required by actions/attest

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
        with:
          fetch-depth: 0     # full history for the changelog
      - uses: actions/setup-go@v7
        with:
          go-version-file: go.mod
      - uses: sigstore/cosign-installer@v4
      - uses: anchore/sbom-action/download-syft@v0  # puts syft on PATH for `sboms`
      - uses: goreleaser/goreleaser-action@v7
        with:
          version: "~> v2"
          args: release --clean
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
      - uses: actions/attest@v4
        with:
          subject-checksums: dist/checksums.txt   # provenance for every archive
```

Pin third-party actions by commit SHA (the go-ci skill explains why).
Artifact attestations are free for public repositories; private ones need
GitHub Enterprise Cloud.

## Local dry run

```bash
goreleaser check
goreleaser release --snapshot --clean --skip=sign,sbom   # nothing is published
ls dist/
go version -m dist/api_linux_amd64_v1/api
```

## Libraries

A library has nothing to build. Its release is the tag: push `v1.4.0`,
let the module proxy pick it up, and use GoReleaser (or a plain GitHub
release) only for the changelog. For `v2+`, the module path in `go.mod`
must end in `/v2` before tagging.
