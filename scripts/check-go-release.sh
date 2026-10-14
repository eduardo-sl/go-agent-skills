#!/bin/bash
set -euo pipefail

# Reports whether go-modernize covers the latest stable Go release.
# Exit 0: covered. Exit 1: not covered (message on stdout). Exit 2: lookup failed.
#
# Coverage means the feature table in go-modernize/SKILL.md has a row for
# the release ("| 1.27+ |") — the table is the skill's index of what it
# teaches, so a release without a row is a release the skill ignores.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
TABLE="$REPO_DIR/skills/(code-quality)/go-modernize/SKILL.md"

if ! json=$(curl -fsSL --max-time 30 'https://go.dev/dl/?mode=json'); then
    echo "could not fetch the Go release list from go.dev"
    exit 2
fi

# The first entry is the newest stable release, e.g. "go1.27.2".
latest=$(printf '%s' "$json" | python3 -c 'import json, sys; print(json.load(sys.stdin)[0]["version"])')
minor=$(printf '%s' "$latest" | sed -E 's/^go([0-9]+\.[0-9]+).*/\1/')

if grep -qF "| ${minor}+ |" "$TABLE"; then
    echo "go-modernize covers Go ${minor} (latest release: ${latest})"
    exit 0
fi

echo "Go ${minor} (${latest}) is out, but the go-modernize feature table has no ${minor}+ row."
exit 1
