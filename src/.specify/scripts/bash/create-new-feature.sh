#!/usr/bin/env bash

set -e

JSON_MODE=false
DRY_RUN=false
SHORT_NAME=""
FEATURE_NUMBER=""
USE_TIMESTAMP=false
ARGS=()

i=1
while [ $i -le $# ]; do
    arg="${!i}"
    case "$arg" in
    --json)
        JSON_MODE=true
        ;;
    --dry-run)
        DRY_RUN=true
        ;;
    --short-name)
        if [ $((i + 1)) -gt $# ]; then
            echo 'Error: --short-name requires a value' >&2
            exit 1
        fi
        i=$((i + 1))
        next_arg="${!i}"
        if [[ "$next_arg" == --* ]]; then
            echo 'Error: --short-name requires a value' >&2
            exit 1
        fi
        SHORT_NAME="$next_arg"
        ;;
    --number)
        if [ $((i + 1)) -gt $# ]; then
            echo 'Error: --number requires a value' >&2
            exit 1
        fi
        i=$((i + 1))
        next_arg="${!i}"
        if [[ "$next_arg" == --* ]]; then
            echo 'Error: --number requires a value' >&2
            exit 1
        fi
        FEATURE_NUMBER="$next_arg"
        ;;
    --timestamp)
        USE_TIMESTAMP=true
        ;;
    --help | -h)
        echo "Usage: $0 [--json] [--dry-run] [--short-name <name>] [--number N] [--timestamp] <feature_description>"
        echo ""
        echo "Options:"
        echo "  --json              Output in JSON format"
        echo "  --dry-run           Compute feature slug and paths without creating files"
        echo "  --short-name <name> Provide a custom short name (2-4 words) for the feature slug"
        echo "  --number N          Specify feature number manually (overrides auto-detection)"
        echo "  --timestamp         Use timestamp prefix (YYYYMMDD-HHMMSS) instead of sequential numbering"
        echo "  --help, -h          Show this help message"
        echo ""
        echo "Examples:"
        echo "  $0 'Add user authentication system' --short-name 'user-auth'"
        echo "  $0 'Implement OAuth2 integration for API' --number 5"
        echo "  $0 --timestamp --short-name 'user-auth' 'Add user authentication'"
        exit 0
        ;;
    *)
        ARGS+=("$arg")
        ;;
    esac
    i=$((i + 1))
done

FEATURE_DESCRIPTION="${ARGS[*]}"
if [ -z "$FEATURE_DESCRIPTION" ]; then
    echo "Usage: $0 [--json] [--dry-run] [--short-name <name>] [--number N] [--timestamp] <feature_description>" >&2
    exit 1
fi

FEATURE_DESCRIPTION=$(echo "$FEATURE_DESCRIPTION" | xargs)
if [ -z "$FEATURE_DESCRIPTION" ]; then
    echo "Error: Feature description cannot be empty or contain only whitespace" >&2
    exit 1
fi

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

get_highest_from_specs() {
    local specs_root="$1"
    local highest=0

    if [ -d "$specs_root" ]; then
        for dir in "$specs_root"/*; do
            [ -d "$dir" ] || continue
            dirname=$(basename "$dir")
            if echo "$dirname" | grep -Eq '^[0-9]{3,}-' && ! echo "$dirname" | grep -Eq '^[0-9]{8}-[0-9]{6}-'; then
                number=$(echo "$dirname" | grep -Eo '^[0-9]+')
                number=$((10#$number))
                if [ "$number" -gt "$highest" ]; then
                    highest=$number
                fi
            fi
        done
    fi

    echo "$highest"
}

clean_feature_slug() {
    local name="$1"
    echo "$name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/-\+/-/g' | sed 's/^-//' | sed 's/-$//'
}

generate_feature_slug() {
    local description="$1"
    local stop_words="^(i|a|an|the|to|for|of|in|on|at|by|with|from|is|are|was|were|be|been|being|have|has|had|do|does|did|will|would|should|could|can|may|might|must|shall|this|that|these|those|my|your|our|their|want|need|add|get|set)$"
    local clean_name
    clean_name=$(echo "$description" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/ /g')

    local meaningful_words=()
    for word in $clean_name; do
        [ -z "$word" ] && continue
        if ! echo "$word" | grep -qiE "$stop_words"; then
            if [ ${#word} -ge 3 ]; then
                meaningful_words+=("$word")
            elif echo "$description" | grep -q "\b${word^^}\b"; then
                meaningful_words+=("$word")
            fi
        fi
    done

    if [ ${#meaningful_words[@]} -gt 0 ]; then
        local max_words=3
        if [ ${#meaningful_words[@]} -eq 4 ]; then max_words=4; fi

        local result=""
        local count=0
        for word in "${meaningful_words[@]}"; do
            if [ $count -ge $max_words ]; then break; fi
            if [ -n "$result" ]; then result="$result-"; fi
            result="$result$word"
            count=$((count + 1))
        done
        echo "$result"
    else
        local cleaned
        cleaned=$(clean_feature_slug "$description")
        echo "$cleaned" | tr '-' '\n' | grep -v '^$' | head -3 | tr '\n' '-' | sed 's/-$//'
    fi
}

REPO_ROOT=$(get_repo_root)
cd "$REPO_ROOT"

SPECS_ROOT="$REPO_ROOT/specs"
if [ "$DRY_RUN" != true ]; then
    mkdir -p "$SPECS_ROOT"
fi

if [ -n "$SHORT_NAME" ]; then
    FEATURE_SUFFIX=$(clean_feature_slug "$SHORT_NAME")
else
    FEATURE_SUFFIX=$(generate_feature_slug "$FEATURE_DESCRIPTION")
fi

if [ -z "$FEATURE_SUFFIX" ]; then
    echo "Error: Failed to generate a feature slug from the description" >&2
    exit 1
fi

if [ "$USE_TIMESTAMP" = true ] && [ -n "$FEATURE_NUMBER" ]; then
    >&2 echo "[specify] Warning: --number is ignored when --timestamp is used"
    FEATURE_NUMBER=""
fi

if [ "$USE_TIMESTAMP" = true ]; then
    FEATURE_NUM=$(date +%Y%m%d-%H%M%S)
    FEATURE_SLUG="${FEATURE_NUM}-${FEATURE_SUFFIX}"
else
    if [ -z "$FEATURE_NUMBER" ]; then
        HIGHEST=$(get_highest_from_specs "$SPECS_ROOT")
        FEATURE_NUMBER=$((HIGHEST + 1))
    fi

    FEATURE_NUM=$(printf "%03d" "$((10#$FEATURE_NUMBER))")
    FEATURE_SLUG="${FEATURE_NUM}-${FEATURE_SUFFIX}"
fi

MAX_FEATURE_LENGTH=244
if [ ${#FEATURE_SLUG} -gt $MAX_FEATURE_LENGTH ]; then
    PREFIX_LENGTH=$((${#FEATURE_NUM} + 1))
    MAX_SUFFIX_LENGTH=$((MAX_FEATURE_LENGTH - PREFIX_LENGTH))
    TRUNCATED_SUFFIX=$(echo "$FEATURE_SUFFIX" | cut -c1-"$MAX_SUFFIX_LENGTH")
    TRUNCATED_SUFFIX=$(echo "$TRUNCATED_SUFFIX" | sed 's/-$//')

    ORIGINAL_FEATURE_SLUG="$FEATURE_SLUG"
    FEATURE_SLUG="${FEATURE_NUM}-${TRUNCATED_SUFFIX}"

    >&2 echo "[specify] Warning: Feature slug exceeded the configured length limit"
    >&2 echo "[specify] Original: $ORIGINAL_FEATURE_SLUG (${#ORIGINAL_FEATURE_SLUG} bytes)"
    >&2 echo "[specify] Truncated to: $FEATURE_SLUG (${#FEATURE_SLUG} bytes)"
fi

if ! validate_feature_slug "$FEATURE_SLUG"; then
    echo "Error: Generated invalid feature slug: $FEATURE_SLUG" >&2
    exit 1
fi

FEATURE_DIR="$SPECS_ROOT/$FEATURE_SLUG"
SPEC_FILE="$FEATURE_DIR/spec.md"

if [ "$DRY_RUN" != true ]; then
    if [ -e "$FEATURE_DIR" ]; then
        echo "Error: Feature directory already exists: $FEATURE_DIR" >&2
        exit 1
    fi

    mkdir -p "$FEATURE_DIR"

    TEMPLATE=$(resolve_template "spec-template" "$REPO_ROOT") || true
    if [ -n "$TEMPLATE" ] && [ -f "$TEMPLATE" ]; then
        cp "$TEMPLATE" "$SPEC_FILE"
    else
        echo "Warning: Spec template not found; created empty spec file" >&2
        touch "$SPEC_FILE"
    fi

    write_current_feature "$FEATURE_SLUG" "$REPO_ROOT"
fi

if $JSON_MODE; then
    if command -v jq >/dev/null 2>&1; then
        if [ "$DRY_RUN" = true ]; then
            jq -cn \
                --arg feature_slug "$FEATURE_SLUG" \
                --arg feature_dir "$FEATURE_DIR" \
                --arg spec_file "$SPEC_FILE" \
                --arg feature_num "$FEATURE_NUM" \
                '{FEATURE_SLUG:$feature_slug,FEATURE_DIR:$feature_dir,SPEC_FILE:$spec_file,FEATURE_NUM:$feature_num,DRY_RUN:true}'
        else
            jq -cn \
                --arg feature_slug "$FEATURE_SLUG" \
                --arg feature_dir "$FEATURE_DIR" \
                --arg spec_file "$SPEC_FILE" \
                --arg feature_num "$FEATURE_NUM" \
                '{FEATURE_SLUG:$feature_slug,FEATURE_DIR:$feature_dir,SPEC_FILE:$spec_file,FEATURE_NUM:$feature_num}'
        fi
    else
        if [ "$DRY_RUN" = true ]; then
            printf '{"FEATURE_SLUG":"%s","FEATURE_DIR":"%s","SPEC_FILE":"%s","FEATURE_NUM":"%s","DRY_RUN":true}\n' "$(json_escape "$FEATURE_SLUG")" "$(json_escape "$FEATURE_DIR")" "$(json_escape "$SPEC_FILE")" "$(json_escape "$FEATURE_NUM")"
        else
            printf '{"FEATURE_SLUG":"%s","FEATURE_DIR":"%s","SPEC_FILE":"%s","FEATURE_NUM":"%s"}\n' "$(json_escape "$FEATURE_SLUG")" "$(json_escape "$FEATURE_DIR")" "$(json_escape "$SPEC_FILE")" "$(json_escape "$FEATURE_NUM")"
        fi
    fi
else
    echo "FEATURE_SLUG: $FEATURE_SLUG"
    echo "FEATURE_DIR: $FEATURE_DIR"
    echo "SPEC_FILE: $SPEC_FILE"
    echo "FEATURE_NUM: $FEATURE_NUM"
fi
