#!/usr/bin/env bash
# Open the live activity viewer (watch.sh) in a NEW terminal tab/window next to
# the Claude session. macOS only for the auto-open; everywhere else it prints the
# one command to run yourself. Never fails the caller.
#
#   open-logs.sh [project-dir]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
WATCH="$SCRIPT_DIR/watch.sh"
# Resolve THIS project's activity log here (we have CLAUDE_PROJECT_DIR); the new
# tab won't inherit it, so we pass the resolved path to watch.sh.
. "$SCRIPT_DIR/../lib/common.sh" 2>/dev/null || true
ACT="${ACTIVITY:-$HOME/.skill-loop/activity.log}"

manual() {
  printf 'Open a terminal tab and run:\n  "%s" "%s"\n' "$WATCH" "$ACT"
}

# Non-macOS (or no GUI): just tell the user the command.
if [ "$(uname -s 2>/dev/null)" != "Darwin" ]; then
  echo "Auto-open is macOS-only."; manual; exit 0
fi

# Bake a self-contained launcher so we never wrestle with nested AppleScript
# quoting around paths that contain spaces (this plugin's path does).
LAUNCH="$(mktemp -t skillloop-watch).command"
printf '#!/usr/bin/env bash\nexec %q %q\n' "$WATCH" "$ACT" >"$LAUNCH"
chmod +x "$LAUNCH"

opened=""
case "${TERM_PROGRAM:-}" in
  iTerm.app)
    osascript >/dev/null 2>&1 <<OSA && opened="iTerm tab"
tell application "iTerm"
  activate
  if (count of windows) = 0 then
    set w to (create window with default profile)
    tell current session of w to write text "exec \"$LAUNCH\""
  else
    tell current window
      create tab with default profile
      tell current session to write text "exec \"$LAUNCH\""
    end tell
  end if
end tell
OSA
    ;;
  Apple_Terminal)
    osascript >/dev/null 2>&1 <<OSA && opened="Terminal tab"
tell application "Terminal" to activate
tell application "System Events" to keystroke "t" using command down
delay 0.2
tell application "Terminal" to do script "exec \"$LAUNCH\"" in front window
OSA
    ;;
esac

# Fallback: open the .command (new Terminal.app window) for any other host
# (VS Code integrated terminal, tmux, etc.) or if the above failed.
if [ -z "$opened" ]; then
  if open "$LAUNCH" >/dev/null 2>&1; then
    opened="Terminal window"
  fi
fi

if [ -n "$opened" ]; then
  echo "Opened skill-loop live logs in a new $opened."
  echo "(If nothing appeared, run it yourself:)"
fi
manual
exit 0
