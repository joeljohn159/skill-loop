#!/usr/bin/env bash
# LAYER 2 — ENFORCE.  PostToolUse hook for Write|Edit|MultiEdit.  ZERO LLM.
#
# Runs the PROJECT's own formatter/linter --fix on the single file Claude just
# edited. This is the deterministic half of the "hard split": anything a tool
# can enforce is auto-fixed here and never becomes a skill. It NEVER blocks the
# session — always exits 0, logs problems to .skill-loop/skill-loop.log.
#
# Which formatter runs is decided by (1) an explicit override in
# .skill-loop/config (`format_cmd=<cmd with {file}>`, written by bootstrap), or
# (2) extension-based auto-detection that only ever invokes a tool that is
# actually installed (project-local node_modules/.bin first, then PATH).

SL_TAG="enforce"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$SCRIPT_DIR/../lib/common.sh" 2>/dev/null || exit 0

INPUT="$(cat 2>/dev/null)"
[ -n "$INPUT" ] || exit 0
SL_SESSION="$(sl_json_get "$INPUT" .session_id)"; SL_SESSION="${SL_SESSION:-unknown}"

# Disabled?  (config: enforce=off)
[ "$(sl_cfg enforce on)" = "off" ] && exit 0

FILE="$(sl_json_get "$INPUT" .tool_input.file_path)"
[ -n "$FILE" ] || exit 0
[ -f "$FILE" ] || exit 0

cd "$PROJECT_DIR" 2>/dev/null || true

# Resolve a node-based tool: project-local bin wins over global PATH.
node_bin() {
  local tool="$1"
  if [ -x "$PROJECT_DIR/node_modules/.bin/$tool" ]; then
    printf '%s' "$PROJECT_DIR/node_modules/.bin/$tool"
  elif command -v "$tool" >/dev/null 2>&1; then
    command -v "$tool"
  fi
}

run() { sl_event FORMAT "${1##*/} ${FILE##*/}"; sl_log "fmt: $*"; "$@" >>"$LOG" 2>&1 || sl_log "fmt non-zero ($?): $*"; }

# 1) Explicit override from bootstrap (most reliable).
OVERRIDE="$(sl_cfg format_cmd)"
if [ -n "$OVERRIDE" ]; then
  cmd="${OVERRIDE//\{file\}/$FILE}"
  sl_event FORMAT "${FILE##*/} (override)"
  sl_log "override fmt: $cmd"
  bash -c "$cmd" >>"$LOG" 2>&1 || sl_log "override fmt non-zero ($?)"
  exit 0
fi

# 2) Extension-based auto-detection — only runs installed tools.
ext="${FILE##*.}"
case "$ext" in
  js|jsx|ts|tsx|mjs|cjs|json|jsonc|css|scss|less|html|vue|svelte|md|markdown|yaml|yml|graphql)
    b="$(node_bin prettier)"; [ -n "$b" ] && run "$b" --write "$FILE"
    b="$(node_bin eslint)";   [ -n "$b" ] && case "$ext" in js|jsx|ts|tsx|mjs|cjs|vue|svelte) run "$b" --fix "$FILE" ;; esac
    ;;
  py)
    if command -v ruff >/dev/null 2>&1; then
      run ruff check --fix "$FILE"; run ruff format "$FILE"
    else
      command -v black >/dev/null 2>&1 && run black -q "$FILE"
      command -v isort >/dev/null 2>&1 && run isort "$FILE"
    fi
    ;;
  go)   command -v gofmt >/dev/null 2>&1 && run gofmt -w "$FILE"
        command -v goimports >/dev/null 2>&1 && run goimports -w "$FILE" ;;
  rs)   command -v rustfmt >/dev/null 2>&1 && run rustfmt "$FILE" ;;
  rb)   command -v rubocop >/dev/null 2>&1 && run rubocop -A "$FILE" ;;
  sh|bash)
        command -v shfmt >/dev/null 2>&1 && run shfmt -w "$FILE" ;;
  dart) command -v dart >/dev/null 2>&1 && run dart format "$FILE" ;;
  *)    sl_log "no formatter mapped for .$ext ($FILE)" ;;
esac

exit 0
