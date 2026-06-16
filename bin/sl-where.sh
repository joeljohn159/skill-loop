#!/usr/bin/env bash
# Print the resolved per-project locations for the current project, so the
# slash-commands (bootstrap/promote/learn/learn-from-ci) write to the right
# personal, per-project spot without re-deriving the keying logic.
#
# Output is key=value lines:
#   SCOPE, PROJECT_KEY, STATE_DIR, SKILLS_DIR, SKILL_PREFIX, SKILL_PATHS
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$SCRIPT_DIR/../lib/common.sh" 2>/dev/null || exit 0
sl_ensure_dirs
printf 'SCOPE=%s\n'        "$SL_SCOPE"
printf 'PROJECT_KEY=%s\n'  "$PROJECT_KEY"
printf 'STATE_DIR=%s\n'    "$STATE_DIR"
printf 'SKILLS_DIR=%s\n'   "$SKILLS_DIR"
printf 'SKILL_PREFIX=%s\n' "$SL_SKILL_PREFIX"
printf 'SKILL_PATHS=%s\n'  "$SL_SKILL_PATHS"
