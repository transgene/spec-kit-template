#!/usr/bin/env bash
# Common functions and variables for all scripts

# Find repository root by searching upward for .specify directory
# This is the primary marker for spec-kit projects
find_specify_root() {
    local dir="${1:-$(pwd)}"
    # Normalize to absolute path to prevent infinite loop with relative paths
    # Use -- to handle paths starting with - (e.g., -P, -L)
    dir="$(cd -- "$dir" 2>/dev/null && pwd)" || return 1
    local prev_dir=""
    while true; do
        if [ -d "$dir/.specify" ]; then
            echo "$dir"
            return 0
        fi
        # Stop if we've reached filesystem root or dirname stops changing
        if [ "$dir" = "/" ] || [ "$dir" = "$prev_dir" ]; then
            break
        fi
        prev_dir="$dir"
        dir="$(dirname "$dir")"
    done
    return 1
}

# Get repository root from the nearest .specify directory.
get_repo_root() {
    local specify_root
    if specify_root=$(find_specify_root); then
        echo "$specify_root"
        return
    fi

    # Final fallback to script location.
    local script_dir="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    (cd "$script_dir/../../.." && pwd)
}

feature_state_file() {
    local repo_root="${1:-$(get_repo_root)}"
    echo "$repo_root/.specify/.current-feature"
}

validate_feature_slug() {
    local feature_slug="$1"

    [[ -n "$feature_slug" ]] || return 1

    if [[ "$feature_slug" =~ ^[0-9]{3,}-[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
        return 0
    fi

    if [[ "$feature_slug" =~ ^[0-9]{8}-[0-9]{6}-[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
        return 0
    fi

    return 1
}

read_current_feature() {
    local repo_root="${1:-$(get_repo_root)}"
    local state_file
    state_file="$(feature_state_file "$repo_root")"

    if [[ -f "$state_file" ]]; then
        local feature_slug
        feature_slug="$(tr -d '[:space:]' <"$state_file")"
        if validate_feature_slug "$feature_slug"; then
            echo "$feature_slug"
            return 0
        fi
        echo "ERROR: Invalid feature slug stored in $state_file: $feature_slug" >&2
        return 1
    fi

    return 1
}

write_current_feature() {
    local feature_slug="$1"
    local repo_root="${2:-$(get_repo_root)}"

    if ! validate_feature_slug "$feature_slug"; then
        echo "ERROR: Invalid feature slug: $feature_slug" >&2
        return 1
    fi

    printf '%s\n' "$feature_slug" >"$(feature_state_file "$repo_root")"
}

resolve_active_feature() {
    local explicit_feature="${1:-}"
    local repo_root
    repo_root="$(get_repo_root)"

    if [[ -n "$explicit_feature" ]]; then
        if ! validate_feature_slug "$explicit_feature"; then
            echo "ERROR: Invalid feature slug: $explicit_feature" >&2
            return 1
        fi
        echo "$explicit_feature"
        return 0
    fi

    if read_current_feature "$repo_root"; then
        return 0
    fi

    echo "ERROR: Active feature is not set. Pass --feature <slug> or create/select a feature first." >&2
    return 1
}

get_feature_dir() { echo "$1/specs/$2"; }

get_feature_paths() {
    local explicit_feature="${1:-}"
    local repo_root=$(get_repo_root)
    local current_feature
    if ! current_feature=$(resolve_active_feature "$explicit_feature"); then
        return 1
    fi

    local feature_dir
    feature_dir=$(get_feature_dir "$repo_root" "$current_feature")
    if [[ ! -d "$feature_dir" ]]; then
        echo "ERROR: Feature directory not found: $feature_dir" >&2
        return 1
    fi

    local feature_spec="$feature_dir/spec.md"
    local feature_name
    feature_name=$(grep -m1 '^# Feature Specification: ' "$feature_spec" 2>/dev/null | sed 's/^# Feature Specification: //')
    if [[ -z "$feature_name" ]]; then
        feature_name="$current_feature"
    fi

    printf 'REPO_ROOT=%q\n' "$repo_root"
    printf 'FEATURE_SLUG=%q\n' "$current_feature"
    printf 'FEATURE_NAME=%q\n' "$feature_name"
    printf 'FEATURE_DIR=%q\n' "$feature_dir"
    printf 'FEATURE_SPEC=%q\n' "$feature_spec"
    printf 'IMPL_PLAN=%q\n' "$feature_dir/plan.md"
    printf 'TASKS=%q\n' "$feature_dir/tasks.md"
    printf 'RESEARCH=%q\n' "$feature_dir/research.md"
    printf 'DATA_MODEL=%q\n' "$feature_dir/data-model.md"
    printf 'QUICKSTART=%q\n' "$feature_dir/quickstart.md"
    printf 'CONTRACTS_DIR=%q\n' "$feature_dir/contracts"
}

# Check if jq is available for safe JSON construction
has_jq() {
    command -v jq >/dev/null 2>&1
}

# Escape a string for safe embedding in a JSON value (fallback when jq is unavailable).
# Handles backslash, double-quote, and JSON-required control character escapes (RFC 8259).
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\t'/\\t}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\b'/\\b}"
    s="${s//$'\f'/\\f}"
    # Escape any remaining U+0001-U+001F control characters as \uXXXX.
    # (U+0000/NUL cannot appear in bash strings and is excluded.)
    # LC_ALL=C ensures ${#s} counts bytes and ${s:$i:1} yields single bytes,
    # so multi-byte UTF-8 sequences (first byte >= 0xC0) pass through intact.
    local LC_ALL=C
    local i char code
    for ((i = 0; i < ${#s}; i++)); do
        char="${s:$i:1}"
        printf -v code '%d' "'$char" 2>/dev/null || code=256
        if ((code >= 1 && code <= 31)); then
            printf '\\u%04x' "$code"
        else
            printf '%s' "$char"
        fi
    done
}

check_file() { [[ -f "$1" ]] && echo "  ✓ $2" || echo "  ✗ $2"; }
check_dir() { [[ -d "$1" && -n $(ls -A "$1" 2>/dev/null) ]] && echo "  ✓ $2" || echo "  ✗ $2"; }

# Resolve a template name to a file path using the priority stack:
#   1. .specify/templates/overrides/
#   2. .specify/presets/<preset-id>/templates/ (sorted by priority from .registry)
#   3. .specify/extensions/<ext-id>/templates/
#   4. .specify/templates/ (core)
resolve_template() {
    local template_name="$1"
    local repo_root="$2"
    local base="$repo_root/.specify/templates"

    # Priority 1: Project overrides
    local override="$base/overrides/${template_name}.md"
    [ -f "$override" ] && echo "$override" && return 0

    # Priority 2: Installed presets (sorted by priority from .registry)
    local presets_dir="$repo_root/.specify/presets"
    if [ -d "$presets_dir" ]; then
        local registry_file="$presets_dir/.registry"
        if [ -f "$registry_file" ] && command -v python3 >/dev/null 2>&1; then
            # Read preset IDs sorted by priority (lower number = higher precedence).
            # The python3 call is wrapped in an if-condition so that set -e does not
            # abort the function when python3 exits non-zero (e.g. invalid JSON).
            local sorted_presets=""
            if sorted_presets=$(SPECKIT_REGISTRY="$registry_file" python3 -c "
import json, sys, os
try:
    with open(os.environ['SPECKIT_REGISTRY']) as f:
        data = json.load(f)
    presets = data.get('presets', {})
    for pid, meta in sorted(presets.items(), key=lambda x: x[1].get('priority', 10)):
        print(pid)
except Exception:
    sys.exit(1)
" 2>/dev/null); then
                if [ -n "$sorted_presets" ]; then
                    # python3 succeeded and returned preset IDs — search in priority order
                    while IFS= read -r preset_id; do
                        local candidate="$presets_dir/$preset_id/templates/${template_name}.md"
                        [ -f "$candidate" ] && echo "$candidate" && return 0
                    done <<<"$sorted_presets"
                fi
                # python3 succeeded but registry has no presets — nothing to search
            else
                # python3 failed (missing, or registry parse error) — fall back to unordered directory scan
                for preset in "$presets_dir"/*/; do
                    [ -d "$preset" ] || continue
                    local candidate="$preset/templates/${template_name}.md"
                    [ -f "$candidate" ] && echo "$candidate" && return 0
                done
            fi
        else
            # Fallback: alphabetical directory order (no python3 available)
            for preset in "$presets_dir"/*/; do
                [ -d "$preset" ] || continue
                local candidate="$preset/templates/${template_name}.md"
                [ -f "$candidate" ] && echo "$candidate" && return 0
            done
        fi
    fi

    # Priority 3: Extension-provided templates
    local ext_dir="$repo_root/.specify/extensions"
    if [ -d "$ext_dir" ]; then
        for ext in "$ext_dir"/*/; do
            [ -d "$ext" ] || continue
            # Skip hidden directories (e.g. .backup, .cache)
            case "$(basename "$ext")" in .*) continue ;; esac
            local candidate="$ext/templates/${template_name}.md"
            [ -f "$candidate" ] && echo "$candidate" && return 0
        done
    fi

    # Priority 4: Core templates
    local core="$base/${template_name}.md"
    [ -f "$core" ] && echo "$core" && return 0

    # Template not found in any location.
    # Return 1 so callers can distinguish "not found" from "found".
    # Callers running under set -e should use: TEMPLATE=$(resolve_template ...) || true
    return 1
}
