#!/bin/sh
# extract-session.sh — Find and output Copilot CLI session data.
#
# Usage: extract-session.sh <query>
#
# Query modes:
#   <uuid>        Direct path lookup in session-state
#   <branch>      Search session-store.db (query contains '/')
#   latest        Most recently modified session
#
# Requires: sqlite3 (for branch lookups only)

set -e

SESSION_STATE_DIR="$HOME/.copilot/session-state"
SESSION_STORE_DB="$HOME/.copilot/session-store.db"

usage() {
    echo "Usage: $(basename "$0") <query>" >&2
    echo "" >&2
    echo "  <query> can be:" >&2
    echo "    <uuid>       — direct session ID lookup" >&2
    echo "    <branch>     — branch name (e.g. george/fix-issue-42)" >&2
    echo "    latest       — most recently modified session" >&2
    exit 1
}

die() {
    echo "error: $1" >&2
    exit 1
}

# Parse a value from workspace.yaml using grep/sed.
# Handles simple top-level "key: value" lines only.
yaml_value() {
    _file="$1"
    _key="$2"
    if [ ! -f "$_file" ]; then
        echo ""
        return
    fi
    # Match "key: value", strip the key and colon, trim leading/trailing whitespace and quotes
    sed -n "s/^${_key}:[[:space:]]*//p" "$_file" | sed 's/^["'"'"']//;s/["'"'"']$//' | head -1
}

# Emit JSON output for a resolved session.
emit_json() {
    _session_id="$1"
    _events_path="$2"
    _session_dir="$3"

    _workspace_file="$_session_dir/workspace.yaml"
    _cwd="$(yaml_value "$_workspace_file" "cwd")"
    _repository="$(yaml_value "$_workspace_file" "repository")"
    _branch="$(yaml_value "$_workspace_file" "branch")"
    _summary="$(yaml_value "$_workspace_file" "summary")"

    # Escape backslashes and double quotes in summary for valid JSON
    _summary="$(printf '%s' "$_summary" | sed 's/\\/\\\\/g; s/"/\\"/g')"

    printf '{\n'
    printf '  "session_id": "%s",\n' "$_session_id"
    printf '  "events_path": "%s",\n' "$_events_path"
    printf '  "workspace": {\n'
    printf '    "cwd": "%s",\n' "$_cwd"
    printf '    "repository": "%s",\n' "$_repository"
    printf '    "branch": "%s",\n' "$_branch"
    printf '    "summary": "%s"\n' "$_summary"
    printf '  }\n'
    printf '}\n'
}

# Resolve a session ID to its events.jsonl, verify it exists, and emit JSON.
resolve_session() {
    _sid="$1"
    _dir="$SESSION_STATE_DIR/$_sid"
    _events="$_dir/events.jsonl"

    if [ ! -d "$_dir" ]; then
        die "session directory not found: $_dir"
    fi
    if [ ! -f "$_events" ]; then
        die "events.jsonl not found in session: $_dir"
    fi

    emit_json "$_sid" "$_events" "$_dir"
}

# --- Argument parsing ---

if [ $# -ne 1 ] || [ -z "$1" ]; then
    usage
fi

query="$1"

# --- Detect query mode ---

is_uuid() {
    # Match 8-4-4-4-12 hex pattern
    echo "$1" | grep -qE '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
}

if [ "$query" = "latest" ]; then
    # --- Latest mode ---
    if [ ! -d "$SESSION_STATE_DIR" ]; then
        die "session state directory not found: $SESSION_STATE_DIR"
    fi

    # Find the most recently modified events.jsonl
    latest_events=""
    latest_mtime=0

    for events_file in "$SESSION_STATE_DIR"/*/events.jsonl; do
        # Guard against no matches (glob returns the pattern literally)
        [ -f "$events_file" ] || continue

        # stat -f %m is macOS, stat -c %Y is Linux; try both
        mtime="$(stat -f %m "$events_file" 2>/dev/null || stat -c %Y "$events_file" 2>/dev/null || echo 0)"
        if [ "$mtime" -gt "$latest_mtime" ]; then
            latest_mtime="$mtime"
            latest_events="$events_file"
        fi
    done

    if [ -z "$latest_events" ]; then
        die "no sessions found in $SESSION_STATE_DIR"
    fi

    # Extract session ID from path: .../session-state/<uuid>/events.jsonl
    session_id="$(basename "$(dirname "$latest_events")")"
    resolve_session "$session_id"

elif is_uuid "$query"; then
    # --- UUID mode ---
    resolve_session "$query"

elif echo "$query" | grep -q '/'; then
    # --- Branch mode ---
    if [ ! -f "$SESSION_STORE_DB" ]; then
        die "session store database not found: $SESSION_STORE_DB (branch lookups require session-store.db)"
    fi

    if ! command -v sqlite3 >/dev/null 2>&1; then
        die "sqlite3 is required for branch lookups but was not found in PATH"
    fi

    session_id="$(sqlite3 "$SESSION_STORE_DB" \
        "SELECT id FROM sessions WHERE branch = '$(printf '%s' "$query" | sed "s/'/''/g")' ORDER BY created_at DESC LIMIT 1;" 2>/dev/null)"

    if [ -z "$session_id" ]; then
        die "no session found for branch: $query"
    fi

    resolve_session "$session_id"

else
    die "unrecognized query: '$query' (expected a UUID, branch name with '/', or 'latest')"
fi
