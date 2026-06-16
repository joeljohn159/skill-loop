#!/usr/bin/env bash
# LAYER 3 — CAPTURE.  Lightweight, ZERO-LLM signal capture.  Always exits 0.
#
# Wired to several hook groups (it branches on hook_event_name + tool_name):
#   PostToolUse  Write|Edit|MultiEdit  -> record write baseline (for later
#                                         correction detection) + flag dep-manifest edits
#   PostToolUse  Bash                  -> NEW_PATTERN (installs), APPROVAL (clean git),
#                                         FAILURE (errored command / failed tests)
#   PostToolUseFailure (any tool)      -> FAILURE
#
# Pure heuristics. False positives are fine — the gated REFLECT pass filters
# them. CORRECTION + manifest-drift are finalised at reflect time by hashing,
# because the user edits files between turns, outside Claude's tools.

SL_TAG="capture"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$SCRIPT_DIR/../lib/common.sh" 2>/dev/null || exit 0

INPUT="$(cat 2>/dev/null)"
[ -n "$INPUT" ] || exit 0
[ "$(sl_cfg capture on)" = "off" ] && exit 0

SL_SESSION="$(sl_json_get "$INPUT" .session_id)"; SL_SESSION="${SL_SESSION:-unknown}"
EVENT="$(sl_json_get "$INPUT" .hook_event_name)"
TOOL="$(sl_json_get "$INPUT" .tool_name)"

# Collapse text to a short single-line excerpt.
excerpt() { printf '%s' "$1" | tr '\n\t' '  ' | cut -c1-200; }

# --- file edits: record baseline + dependency-manifest signal ---------------
case "$TOOL" in
  Write|Edit|MultiEdit)
    FILE="$(sl_json_get "$INPUT" .tool_input.file_path)"
    if [ -n "$FILE" ]; then
      sl_record_write "$FILE"
      case "$(basename "$FILE")" in
        package.json|requirements*.txt|pyproject.toml|go.mod|Cargo.toml|Gemfile|pubspec.yaml|build.gradle|build.gradle.kts|*.csproj|composer.json)
          sl_emit_signal NEW_PATTERN "$FILE" "dependency manifest edited" "" 1 ;;
      esac
    fi
    ;;
esac

# --- skill usage: surface when Claude actually invokes a skill ---------------
# Invoking a skill is a call to the built-in `Skill` tool, so PostToolUse sees it.
if [ "$TOOL" = "Skill" ] && [ "$EVENT" = "PostToolUse" ]; then
  name="$(sl_json_get "$INPUT" .tool_input.skill)"
  [ -n "$name" ] || name="$(sl_json_get "$INPUT" .tool_input.name)"
  [ -n "$name" ] && sl_event SKILL "used: $name"
fi

# --- Bash command analysis (only on the success event; failures handled below)
if [ "$TOOL" = "Bash" ] && [ "$EVENT" = "PostToolUse" ]; then
  CMD="$(sl_json_get "$INPUT" .tool_input.command)"
  RESP="$(sl_json_get "$INPUT" .tool_response)"
  ERRFLAG="$(sl_json_get "$INPUT" .tool_response.is_error)"   # true if present and errored

  errored=0
  [ "$ERRFLAG" = "true" ] && errored=1
  if printf '%s' "$RESP" | grep -Eqi 'npm ERR!|Traceback \(most recent call last\)|AssertionError|\bFAILED\b|^FAIL |[0-9]+ (failed|failing)|command not found|fatal: |error: |panic: |Exception in thread|exit (status|code) [1-9]'; then
    errored=1
  fi

  # NEW_PATTERN — a tool/library being added to the project.
  if printf '%s' "$CMD" | grep -Eq '(npm|pnpm|yarn)[[:space:]]+(install|add|i)[[:space:]]|pip3?[[:space:]]+install[[:space:]]|poetry[[:space:]]+add[[:space:]]|go[[:space:]]+get[[:space:]]|cargo[[:space:]]+add[[:space:]]|gem[[:space:]]+install[[:space:]]|bundle[[:space:]]+add[[:space:]]|brew[[:space:]]+install[[:space:]]|apt(-get)?[[:space:]]+install[[:space:]]'; then
    sl_emit_signal NEW_PATTERN "" "package/tool installed" "$(excerpt "$CMD")" 1
  fi

  # FAILURE — command/test errored.
  if [ "$errored" = "1" ]; then
    sl_emit_signal FAILURE "" "command failed: $(excerpt "$CMD")" "$(excerpt "$RESP")" 2
  # APPROVAL — a clean commit / merge / push / PR (only when it did NOT error).
  elif printf '%s' "$CMD" | grep -Eq '\bgit[[:space:]]+(commit|merge|push)\b|\bgh[[:space:]]+pr[[:space:]]+(merge|create)\b'; then
    sl_emit_signal APPROVAL "" "clean: $(excerpt "$CMD")" "$(excerpt "$RESP")" 1
  fi
fi

# --- explicit tool failure event -------------------------------------------
if [ "$EVENT" = "PostToolUseFailure" ]; then
  FILE="$(sl_json_get "$INPUT" .tool_input.file_path)"
  RESP="$(sl_json_get "$INPUT" .tool_response)"
  sl_emit_signal FAILURE "$FILE" "$TOOL tool failed" "$(excerpt "$RESP")" 2
fi

exit 0
