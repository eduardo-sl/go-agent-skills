#!/bin/bash
set -euo pipefail

# Validate all SKILL.md files in the repository
# Checks: frontmatter, line count, naming, description quality

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
SKILLS_DIR="$REPO_DIR/skills"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ERRORS=0
WARNINGS=0
CHECKED=0

error() {
    echo -e "  ${RED}✗ ERROR:${NC} $1"
    ERRORS=$((ERRORS + 1))
}

warn() {
    echo -e "  ${YELLOW}⚠ WARN:${NC} $1"
    WARNINGS=$((WARNINGS + 1))
}

ok() {
    echo -e "  ${GREEN}✓${NC} $1"
}

echo "Validating SKILL.md files..."
echo ""

for skill_file in $(find "$SKILLS_DIR" -name "SKILL.md" | sort); do
    skill_dir=$(dirname "$skill_file")
    skill_name=$(basename "$skill_dir")
    rel_path="${skill_file#$REPO_DIR/}"

    echo "[$skill_name] $rel_path"
    CHECKED=$((CHECKED + 1))

    # 1. Check frontmatter exists
    if ! head -1 "$skill_file" | grep -q "^---$"; then
        error "Missing YAML frontmatter (must start with ---)"
        continue
    fi

    # Extract frontmatter
    frontmatter=$(sed -n '/^---$/,/^---$/p' "$skill_file")

    # 2. Check name field exists and matches directory
    fm_name=$(echo "$frontmatter" | grep "^name:" | head -1 | sed 's/^name:[[:space:]]*//')
    if [[ -z "$fm_name" ]]; then
        error "Missing 'name' field in frontmatter"
    elif [[ "$fm_name" != "$skill_name" ]]; then
        error "Name mismatch: frontmatter='$fm_name' directory='$skill_name'"
    else
        ok "Name matches directory"
    fi

    # 3. Check description field exists
    if ! echo "$frontmatter" | grep -q "description:"; then
        error "Missing 'description' field in frontmatter"
    else
        desc_len=$(sed -n '/^description:/,/^user-invocable:/p' "$skill_file" | sed '$d' | wc -c)
        if [[ $desc_len -gt 1024 ]]; then
            error "Description is $desc_len chars (max 1024)"
        fi
        # Check description has trigger phrases
        desc=$(sed -n '/^description:/,/^---$/p' "$skill_file" | head -20)
        if echo "$desc" | grep -qi "trigger\|use when\|trigger examples"; then
            ok "Description has trigger phrases"
        else
            warn "Description should include trigger examples"
        fi

        # Check description has negative triggers
        if echo "$desc" | grep -qi "do not use\|don't use\|not for"; then
            ok "Description has negative triggers"
        else
            warn "Description should include 'Do NOT use for' guidance"
        fi
    fi

    # 4. Check version metadata
    if echo "$frontmatter" | grep -qE '^  version: "[0-9]+\.[0-9]+\.[0-9]+"$'; then
        ok "Has semver version metadata"
    else
        error "Missing 'metadata.version' (semver, quoted) in frontmatter"
    fi

    # 4b. Check author metadata
    if ! echo "$frontmatter" | grep -qE '^  author: .+'; then
        error "Missing 'metadata.author' in frontmatter"
    fi

    # 5. Check license
    if ! echo "$frontmatter" | grep -q "^license:"; then
        warn "Missing 'license' field in frontmatter"
    fi

    # 5b. Check user-invocable (boolean)
    if ! echo "$frontmatter" | grep -qE '^user-invocable: (true|false)$'; then
        error "Missing 'user-invocable' (true|false) in frontmatter"
    fi

    # 5c. Check compatibility (present, <= 500 chars per Agent Skills spec)
    compat=$(echo "$frontmatter" | grep "^compatibility:" | head -1 | sed 's/^compatibility:[[:space:]]*//')
    if [[ -z "$compat" ]]; then
        error "Missing 'compatibility' field in frontmatter"
    elif [[ ${#compat} -gt 500 ]]; then
        error "compatibility is ${#compat} chars (max 500)"
    else
        ok "Has compatibility (${#compat} chars)"
    fi

    # 5d. Check allowed-tools, and that review/audit skills stay read-only
    tools=$(echo "$frontmatter" | grep "^allowed-tools:" | head -1 | sed 's/^allowed-tools:[[:space:]]*//')
    if [[ -z "$tools" ]]; then
        error "Missing 'allowed-tools' field in frontmatter"
    else
        if [[ "$tools" == *"Bash(*"* || "$tools" == *"Bash)"* || "$tools" == "*" ]]; then
            error "allowed-tools grants unscoped Bash access"
        fi
        if [[ "$compat" == *"Read-only:"* ]] && [[ "$tools" == *"Write"* || "$tools" == *"Edit"* ]]; then
            error "Skill declares itself read-only but requests Write/Edit"
        fi
        ok "Has allowed-tools"
    fi

    # 6. Check line count
    line_count=$(wc -l < "$skill_file")
    if [[ $line_count -gt 500 ]]; then
        error "SKILL.md is $line_count lines (max 500). Move content to references/"
    elif [[ $line_count -gt 400 ]]; then
        warn "SKILL.md is $line_count lines (approaching 500 limit)"
    else
        ok "Line count: $line_count (under 500)"
    fi

    # 7. Check for trailing whitespace
    if grep -qn '[[:space:]]$' "$skill_file" 2>/dev/null; then
        warn "Trailing whitespace detected"
    fi

    # 8. Check name format (lowercase, hyphens only)
    if ! echo "$skill_name" | grep -qE "^[a-z][a-z0-9-]*$"; then
        error "Skill name must be lowercase with hyphens only: '$skill_name'"
    fi

    # 9. Check code fences have language tags (odd fences open a block)
    untagged=$(awk '/^```/{n++; if(n%2==1 && $0=="```") c++} END{print c+0}' "$skill_file")
    if [[ $untagged -gt 0 ]]; then
        error "$untagged code fence(s) missing a language tag"
    else
        ok "All code fences have language tags"
    fi

    # 10. Check header depth (max ###), ignoring lines inside code fences
    deep_headers=$(awk '/^```/{fence=!fence; next} !fence && /^####/{c++} END{print c+0}' "$skill_file")
    if [[ $deep_headers -gt 0 ]]; then
        warn "Headers deeper than ### found (guidelines allow max ###)"
    fi

    # 11. Check referenced files under references/ actually exist
    missing_refs=0
    while IFS= read -r ref; do
        if [[ ! -f "$skill_dir/$ref" ]]; then
            error "Referenced file does not exist: $ref"
            missing_refs=$((missing_refs + 1))
        fi
    done < <(grep -oE 'references/[a-z0-9./_-]+\.md' "$skill_file" | sort -u)
    if [[ $missing_refs -eq 0 ]]; then
        ok "All references/ links resolve"
    fi

    echo ""
done

# Validate _category.json files
echo "Validating category metadata..."
echo ""
for cat_file in $(find "$SKILLS_DIR" -name "_category.json" | sort); do
    cat_dir=$(dirname "$cat_file")
    cat_name=$(basename "$cat_dir")
    echo "[$cat_name] _category.json"

    # Check valid JSON
    if python3 -c "import json; json.load(open('$cat_file'))" 2>/dev/null; then
        ok "Valid JSON"
    else
        error "Invalid JSON in $cat_file"
    fi

    # Check required fields
    if python3 -c "
import json, sys
d = json.load(open('$cat_file'))
assert 'name' in d, 'missing name'
assert 'description' in d, 'missing description'
" 2>/dev/null; then
        ok "Has name and description"
    else
        error "Missing 'name' or 'description' in $cat_file"
    fi

    echo ""
done

# Summary
echo "========================================"
echo -e "Skills checked: ${CHECKED}"
echo -e "Errors:         ${RED}${ERRORS}${NC}"
echo -e "Warnings:       ${YELLOW}${WARNINGS}${NC}"
echo "========================================"

if [[ $ERRORS -gt 0 ]]; then
    echo ""
    echo -e "${RED}Validation failed with $ERRORS error(s).${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}All validations passed.${NC}"
