#!/usr/bin/env bash

set -e

# Parse command line arguments
JSON_MODE=false
FEATURE_SLUG_OVERRIDE=""
ARGS=()

while [ $# -gt 0 ]; do
    case "$1" in
    --json)
        JSON_MODE=true
        ;;
    --feature)
        shift
        if [[ -z "${1:-}" ]] || [[ "$1" == --* ]]; then
            echo "ERROR: --feature requires a slug value." >&2
            exit 1
        fi
        FEATURE_SLUG_OVERRIDE="$1"
        ;;
    --help | -h)
        echo "Usage: $0 [--json] [--feature <slug>]"
        echo "  --json    Output results in JSON format"
        echo "  --feature Resolve paths for the given feature slug"
        echo "  --help    Show this help message"
        exit 0
        ;;
    *)
        ARGS+=("$1")
        ;;
    esac
    shift
done

# Get script directory and load common functions
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Get all paths and variables from common functions.
_paths_output=$(get_feature_paths "$FEATURE_SLUG_OVERRIDE") || {
    echo "ERROR: Failed to resolve feature paths" >&2
    exit 1
}
eval "$_paths_output"
unset _paths_output

if [[ -n "$FEATURE_SLUG_OVERRIDE" ]]; then
    write_current_feature "$FEATURE_SLUG_OVERRIDE" "$REPO_ROOT"
fi

# Ensure the feature directory exists
mkdir -p "$FEATURE_DIR"

# Copy plan template if it exists
TEMPLATE=$(resolve_template "plan-template" "$REPO_ROOT") || true
if [[ -n "$TEMPLATE" ]] && [[ -f "$TEMPLATE" ]]; then
    cp "$TEMPLATE" "$IMPL_PLAN"
    echo "Copied plan template to $IMPL_PLAN"
else
    echo "Warning: Plan template not found"
    # Create a basic plan file if template doesn't exist
    touch "$IMPL_PLAN"
fi

# Output results
if $JSON_MODE; then
    if has_jq; then
        jq -cn \
            --arg feature_spec "$FEATURE_SPEC" \
            --arg impl_plan "$IMPL_PLAN" \
            --arg feature_dir "$FEATURE_DIR" \
            --arg feature_slug "$FEATURE_SLUG" \
            --arg feature_name "$FEATURE_NAME" \
            '{FEATURE_SPEC:$feature_spec,IMPL_PLAN:$impl_plan,FEATURE_DIR:$feature_dir,FEATURE_SLUG:$feature_slug,FEATURE_NAME:$feature_name}'
    else
        printf '{"FEATURE_SPEC":"%s","IMPL_PLAN":"%s","FEATURE_DIR":"%s","FEATURE_SLUG":"%s","FEATURE_NAME":"%s"}\n' \
            "$(json_escape "$FEATURE_SPEC")" "$(json_escape "$IMPL_PLAN")" "$(json_escape "$FEATURE_DIR")" "$(json_escape "$FEATURE_SLUG")" "$(json_escape "$FEATURE_NAME")"
    fi
else
    echo "FEATURE_SPEC: $FEATURE_SPEC"
    echo "IMPL_PLAN: $IMPL_PLAN"
    echo "FEATURE_DIR: $FEATURE_DIR"
    echo "FEATURE_SLUG: $FEATURE_SLUG"
    echo "FEATURE_NAME: $FEATURE_NAME"
fi
