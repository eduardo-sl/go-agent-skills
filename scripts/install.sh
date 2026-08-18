#!/bin/bash
set -euo pipefail

# go-agent-skills installer
# Usage: ./scripts/install.sh [PROJECT_DIR] [--agent AGENT] [--global] [--symlink] [--dry-run] [--yes]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
SKILLS_DIR="$REPO_DIR/skills"

# Defaults
PROJECT_DIR=""
AGENT=""
GLOBAL=false
USE_SYMLINK=false
DRY_RUN=false
ASSUME_YES=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

usage() {
    cat <<EOF
Usage: $(basename "$0") [PROJECT_DIR] [OPTIONS]

Install Go agent skills to your project or globally.

Arguments:
  PROJECT_DIR          Target project directory (default: current directory)

Options:
  --agent AGENT        Target agent: claude, cursor, copilot, codex, windsurf
  --global             Install to user home (global, all projects)
  --symlink            Use symlinks instead of copy (stays in sync with repo)
  --dry-run            Print what would be installed, change nothing
  -y, --yes            Do not prompt before replacing existing skills
  -h, --help           Show this help

Examples:
  $(basename "$0") ~/projects/my-go-app --agent claude
  $(basename "$0") --agent cursor --symlink
  $(basename "$0") --global --agent claude
  $(basename "$0") --global --agent claude --dry-run
  $(basename "$0")                              # interactive mode
EOF
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --agent)   AGENT="$2"; shift 2 ;;
        --global)  GLOBAL=true; shift ;;
        --symlink) USE_SYMLINK=true; shift ;;
        --dry-run) DRY_RUN=true; shift ;;
        -y|--yes)  ASSUME_YES=true; shift ;;
        -h|--help) usage ;;
        -*)        echo -e "${RED}Unknown option: $1${NC}"; usage ;;
        *)         PROJECT_DIR="$1"; shift ;;
    esac
done

# Default project dir
if [[ -z "$PROJECT_DIR" ]]; then
    PROJECT_DIR="$(pwd)"
fi
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"

# Agent → directory mapping
get_skills_dir() {
    local agent="$1"
    local global="$2"
    local project="$3"

    case "$agent" in
        claude)
            if [[ "$global" == "true" ]]; then
                echo "$HOME/.claude/skills"
            else
                echo "$project/.claude/skills"
            fi
            ;;
        cursor)
            if [[ "$global" == "true" ]]; then
                echo "$HOME/.cursor/skills"
            else
                echo "$project/.cursor/skills"
            fi
            ;;
        copilot)
            if [[ "$global" == "true" ]]; then
                echo "$HOME/.github/skills"
            else
                echo "$project/.github/skills"
            fi
            ;;
        codex)
            if [[ "$global" == "true" ]]; then
                echo "$HOME/.agents/skills"
            else
                echo "$project/.agents/skills"
            fi
            ;;
        windsurf)
            if [[ "$global" == "true" ]]; then
                echo "$HOME/.windsurf/skills"
            else
                echo "$project/.windsurf/skills"
            fi
            ;;
        *)
            echo ""
            ;;
    esac
}

# Interactive agent selection
if [[ -z "$AGENT" ]]; then
    echo -e "${CYAN}Select your agent:${NC}"
    echo "  1) Claude Code"
    echo "  2) Cursor"
    echo "  3) GitHub Copilot"
    echo "  4) Codex (OpenAI)"
    echo "  5) Windsurf"
    echo ""
    read -rp "Choice [1-5]: " choice

    case "$choice" in
        1) AGENT="claude" ;;
        2) AGENT="cursor" ;;
        3) AGENT="copilot" ;;
        4) AGENT="codex" ;;
        5) AGENT="windsurf" ;;
        *) echo -e "${RED}Invalid choice${NC}"; exit 1 ;;
    esac
fi

TARGET_DIR=$(get_skills_dir "$AGENT" "$GLOBAL" "$PROJECT_DIR")
if [[ -z "$TARGET_DIR" ]]; then
    echo -e "${RED}Unknown agent: $AGENT${NC}"
    exit 1
fi

# Collect the skills to install
SKILL_DIRS=()
for category_dir in "$SKILLS_DIR"/*/; do
    for skill_dir in "$category_dir"*/; do
        # Skip _category.json entries (not directories with SKILL.md)
        [[ ! -f "$skill_dir/SKILL.md" ]] && continue
        SKILL_DIRS+=("$skill_dir")
    done
done

if [[ ${#SKILL_DIRS[@]} -eq 0 ]]; then
    echo -e "${RED}No skills found under $SKILLS_DIR${NC}"
    exit 1
fi

echo ""
echo -e "${CYAN}Installing Go skills to: ${NC}$TARGET_DIR"
echo -e "${CYAN}Method: ${NC}$(if $USE_SYMLINK; then echo 'symlink'; else echo 'copy'; fi)"
echo ""

# Warn about skills that will be replaced
REPLACING=()
for skill_dir in "${SKILL_DIRS[@]}"; do
    target="$TARGET_DIR/$(basename "$skill_dir")"
    [[ -e "$target" || -L "$target" ]] && REPLACING+=("$(basename "$skill_dir")")
done

if [[ ${#REPLACING[@]} -gt 0 ]]; then
    echo -e "${YELLOW}${#REPLACING[@]} existing skill(s) will be replaced:${NC}"
    printf '  %s\n' "${REPLACING[@]}"
    echo ""
    if ! $DRY_RUN && ! $ASSUME_YES; then
        read -rp "Continue? [y/N]: " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 1; }
        echo ""
    fi
fi

if $DRY_RUN; then
    echo -e "${CYAN}Dry run — nothing was written.${NC}"
    printf '  would install %s\n' "${SKILL_DIRS[@]##*/skills/}"
    exit 0
fi

mkdir -p "$TARGET_DIR"

SKILL_COUNT=0
for skill_dir in "${SKILL_DIRS[@]}"; do
    skill_name=$(basename "$skill_dir")
    target="$TARGET_DIR/$skill_name"

    # Only ever remove a path we are about to own, inside TARGET_DIR
    if [[ -e "$target" || -L "$target" ]]; then
        if [[ "$target" != "$TARGET_DIR/"* || -z "$skill_name" ]]; then
            echo -e "${RED}Refusing to remove unexpected path: $target${NC}"
            exit 1
        fi
        rm -rf "$target"
    fi

    if $USE_SYMLINK; then
        ln -sfn "$(realpath "$skill_dir")" "$target"
    else
        cp -r "$skill_dir" "$target"
    fi

    echo -e "  ${GREEN}✓${NC} $skill_name"
    SKILL_COUNT=$((SKILL_COUNT + 1))
done

echo ""
echo -e "${GREEN}Done!${NC} Installed ${SKILL_COUNT} skills for ${AGENT}."

if ! $GLOBAL; then
    echo ""
    echo -e "${YELLOW}Tip:${NC} Add the skills directory to .gitignore if you don't want"
    echo "to commit them to your project repository."
fi
