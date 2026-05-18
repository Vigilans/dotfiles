#!/usr/bin/env bash
# PreToolUse hook (matcher: Agent)
#
# Override the model a subagent uses based on environment variables.
#
# Env var naming: CLAUDE_CODE_SUBAGENT_<UPPER_NAME>_MODEL
#   - subagent_type is uppercased, hyphens replaced with underscores
#   - e.g. Explore         → CLAUDE_CODE_SUBAGENT_EXPLORE_MODEL
#          general-purpose  → CLAUDE_CODE_SUBAGENT_GENERAL_PURPOSE_MODEL
#          claude-code-guide → CLAUDE_CODE_SUBAGENT_CLAUDE_CODE_GUIDE_MODEL
#
# Fallback: CLAUDE_CODE_SUBAGENT_MODEL applies to all subagents
# that don't have a type-specific override.
#
# Set these in settings.json → env, or export them in your shell.

set -euo pipefail

INPUT=$(cat)

SUBAGENT_TYPE=$(printf '%s' "$INPUT" | jq -r '.tool_input.subagent_type // empty')

if [[ -z "$SUBAGENT_TYPE" ]]; then
  exit 0
fi

UPPER_NAME=$(printf '%s' "$SUBAGENT_TYPE" | tr '[:lower:]-' '[:upper:]_')
VAR_NAME="CLAUDE_CODE_SUBAGENT_${UPPER_NAME}_MODEL"

MODEL="${!VAR_NAME:-${CLAUDE_CODE_SUBAGENT_MODEL:-}}"

if [[ -z "$MODEL" ]]; then
  exit 0
fi

TOOL_INPUT=$(printf '%s' "$INPUT" | jq -c '.tool_input')
UPDATED=$(printf '%s' "$TOOL_INPUT" | jq -c --arg m "$MODEL" '.model = $m')

jq -nc --argjson input "$UPDATED" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    updatedInput: $input
  }
}'
