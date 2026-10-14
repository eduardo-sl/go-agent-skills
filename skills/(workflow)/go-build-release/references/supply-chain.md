# SBOMs, Signatures and Provenance

How to produce, and how users verify, the artifacts in SKILL.md section 5.

## Contents

- SBOMs
- Keyless signing with cosign
- Verifying a release
- Provenance attestations
- Container images

## SBOMs

```bash
syft dir:. -o spdx-json > sbom.spdx.json          # from the source tree
syft ./dist/api_linux_amd64_v1/api -o cyclonedx-json > api.cdx.json  # from a binary
go version -m ./bin/api                            # the module list Go embedded itself
```

An SBOM generated from the binary lists what was actually linked; one from
the source tree also lists test-only and tool dependencies. Ship the
binary-derived one. `govulncheck -mode=binary ./bin/api` checks the same
binary for reachable known vulnerabilities.

## Keyless signing with cosign

In CI, cosign exchanges the job's OIDC token for a short-lived signing
certificate tied to the workflow identity, and records the signature in
the public transparency log. There is no private key to store or rotate.

```bash
# In the release job (needs `id-token: write`)
cosign sign-blob --yes --bundle checksums.txt.sigstore.json checksums.txt
```

## Verifying a release

Publish these commands in the release notes:

```bash
# 1. The checksums file was signed by this repository's release workflow
cosign verify-blob \
  --certificate-identity "https://github.com/acme/api/.github/workflows/release.yml@refs/tags/v1.4.0" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  --bundle checksums.txt.sigstore.json \
  checksums.txt

# 2. The archive you downloaded matches the signed checksums
sha256sum --check --ignore-missing checksums.txt

# 3. (Alternative) GitHub's provenance attestation for the archive
gh attestation verify api_1.4.0_linux_amd64.tar.gz --repo acme/api
```

Pin `--certificate-identity` to the exact workflow and tag. A regexp that
accepts any workflow in the organization accepts a compromised one too.

## Provenance attestations

`actions/attest` (v4; `attest-build-provenance` is now a wrapper around it)
creates a signed SLSA provenance statement: which repository, commit,
workflow and runner produced each artifact. Point it at GoReleaser's
`dist/checksums.txt` with `subject-checksums` to cover every archive in one
step. It requires `id-token: write`, `attestations: write` and
`artifact-metadata: write`.

## Container images

```bash
# ko: no Dockerfile, distroless base, multi-arch, SBOM attached, reproducible
KO_DOCKER_REPO=ghcr.io/acme ko build --bare --platform=linux/amd64,linux/arm64 ./cmd/api

# Sign and verify by digest — a tag can be repointed, a digest cannot
cosign sign --yes ghcr.io/acme/api@sha256:<digest>
cosign verify ghcr.io/acme/api@sha256:<digest> \
  --certificate-identity "https://github.com/acme/api/.github/workflows/release.yml@refs/tags/v1.4.0" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com"
```

With a Dockerfile instead of ko:

```dockerfile
FROM golang:1.27 AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download && go mod verify
COPY . .
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/api ./cmd/api

FROM gcr.io/distroless/static:nonroot
COPY --from=build /out/api /api
USER nonroot:nonroot
ENTRYPOINT ["/api"]
```
