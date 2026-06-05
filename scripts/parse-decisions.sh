#!/bin/sh
# parse-decisions.sh — Pre-process Copilot CLI events.jsonl to extract decision-relevant events.
#
# Reduces a full event log to only the events that capture user intent, assistant
# reasoning, tool executions, and context compaction summaries. Output is simplified
# JSONL suitable for LLM ingestion without hitting context limits.
#
# Usage:
#   parse-decisions.sh <events.jsonl path> [--max-output-chars N]
#
# Default max output: 200000 chars (~50K tokens).

set -e

# ---------------------------------------------------------------------------
# Dependency check
# ---------------------------------------------------------------------------
if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required but not found. Install it with: brew install jq" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
INPUT_FILE=""
MAX_OUTPUT_CHARS=200000

while [ $# -gt 0 ]; do
  case "$1" in
    --max-output-chars)
      if [ -z "$2" ] || echo "$2" | grep -q '^-'; then
        echo "Error: --max-output-chars requires a numeric argument" >&2
        exit 1
      fi
      MAX_OUTPUT_CHARS="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: parse-decisions.sh <events.jsonl> [--max-output-chars N]"
      echo ""
      echo "Pre-process Copilot CLI events to extract decision-relevant events."
      echo "Writes simplified JSONL to stdout."
      echo ""
      echo "Options:"
      echo "  --max-output-chars N   Max chars of output (default: 200000)"
      echo "  -h, --help             Show this help"
      exit 0
      ;;
    -*)
      echo "Error: Unknown option: $1" >&2
      exit 1
      ;;
    *)
      if [ -z "$INPUT_FILE" ]; then
        INPUT_FILE="$1"
      else
        echo "Error: Unexpected argument: $1" >&2
        exit 1
      fi
      shift
      ;;
  esac
done

if [ -z "$INPUT_FILE" ]; then
  echo "Error: No input file specified." >&2
  echo "Usage: parse-decisions.sh <events.jsonl> [--max-output-chars N]" >&2
  exit 1
fi

if [ ! -f "$INPUT_FILE" ]; then
  echo "Error: File not found: $INPUT_FILE" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Main jq filter
# ---------------------------------------------------------------------------
# Decision-relevant event types and their extraction logic:
#
#   user.message              → user's request/direction
#   assistant.message         → reasoning, explanations, tool requests
#   tool.execution_start      → what tool was invoked with what args
#   tool.execution_complete   → tool result (truncated)
#   session.compaction_complete → context window decision summaries
#   skill.invoked             → what capabilities were loaded
#   subagent.started          → agent delegation
#   subagent.completed        → agent delegation result
#
# Dropped (not decision-relevant):
#   assistant.turn_start, session.start, session.model_change,
#   session.workspace_file_changed, hook.start, hook.end,
#   system.notification, session.shutdown

JQ_FILTER='
# Truncate a string to N chars, appending marker if cut
def truncate(n):
  if (. | length) > n then .[0:n] + "... [truncated]"
  else . end;

# Truncate all string values in an object to N chars
def truncate_values(n):
  if type == "object" then
    to_entries | map(
      if .value | type == "string" then .value = (.value | truncate(n))
      else . end
    ) | from_entries
  elif type == "string" then truncate(n)
  else . end;

# Check if assistant content contains decision breadcrumb markers
def has_breadcrumbs:
  if type == "string" then test("\\*\\*🔀 Decision #")
  else false end;

# --- Per-event extraction ---

if .type == "user.message" then
  {
    type: "user.message",
    timestamp: .timestamp,
    content: (.data.content // "")
  }

elif .type == "assistant.message" then
  {
    type: "assistant.message",
    timestamp: .timestamp,
    content: (.data.content // ""),
    tool_requests: (
      if .data.toolRequests then
        [ .data.toolRequests[] | {
            name: (.toolName // .name // "unknown"),
            args: ((.arguments // .args // {}) | truncate_values(1000))
          }
        ]
      else null end
    )
  }
  # Add breadcrumb flag if present
  | if .content | has_breadcrumbs then . + { has_breadcrumbs: true } else . end
  # Remove null tool_requests
  | if .tool_requests == null then del(.tool_requests) else . end

elif .type == "tool.execution_start" then
  {
    type: "tool.start",
    timestamp: .timestamp,
    tool: (.data.toolName // "unknown"),
    args: ((.data.arguments // {}) | truncate_values(1000))
  }

elif .type == "tool.execution_complete" then
  {
    type: "tool.complete",
    timestamp: .timestamp,
    tool: (.data.toolName // "unknown"),
    success: (.data.success // false),
    output: (
      (if .data.result.content then
        (.data.result.content | if type == "string" then . else tostring end)
      elif .data.result then
        (.data.result | if type == "string" then . else tostring end)
      else "" end) | truncate(500)
    )
  }

elif .type == "session.compaction_complete" then
  {
    type: "session.compaction_complete",
    timestamp: .timestamp,
    summary: (
      (.data.summary // .data.content // (.data | tostring)) | truncate(500)
    )
  }

elif .type == "skill.invoked" then
  {
    type: "skill.invoked",
    timestamp: .timestamp,
    skill: (.data.skillName // .data.name // "unknown")
  }

elif .type == "subagent.started" then
  {
    type: "subagent.started",
    timestamp: .timestamp,
    agent: (.data.agentName // .data.name // .data.agent_type // "unknown")
  }

elif .type == "subagent.completed" then
  {
    type: "subagent.completed",
    timestamp: .timestamp,
    agent: (.data.agentName // .data.name // .data.agent_type // "unknown")
  }

else
  # Drop all other event types
  empty

end
'

# ---------------------------------------------------------------------------
# Process events with output size tracking
# ---------------------------------------------------------------------------
# We pipe through jq for filtering, then use awk to enforce the max output
# chars limit. This avoids loading the entire file into memory.

jq -c "$JQ_FILTER" "$INPUT_FILE" | awk -v max="$MAX_OUTPUT_CHARS" '
BEGIN { total = 0 }
{
  line_len = length + 1  # +1 for newline
  if (total + line_len > max) {
    printf "{\"type\":\"truncated\",\"message\":\"Output truncated at %d chars. Earlier events prioritized.\"}\n", total
    exit 0
  }
  print
  total += line_len
}
'
