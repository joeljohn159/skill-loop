#!/usr/bin/env bash
# Live, readable viewer for skill-loop's activity log. Runs in its own terminal
# tab/window (opened by /skill-loop:logs) and tails the clean narrative log,
# colorized and column-aligned — NOT the verbose debug log.
#
#   watch.sh [project-dir]      # live (default)
#   SL_WATCH_ONCE=1 watch.sh …  # render current contents once, then exit (tests)

PROJ="${1:-${CLAUDE_PROJECT_DIR:-$PWD}}"
ACT="$PROJ/.skill-loop/activity.log"
mkdir -p "$PROJ/.skill-loop" 2>/dev/null || true
[ -f "$ACT" ] || : >"$ACT"

r=$'\033[0m'; dim=$'\033[2m'; bold=$'\033[1m'
color_for() {
  case "$1" in
    CORRECTION)  printf '\033[36m' ;;   # cyan
    NEW_PATTERN) printf '\033[34m' ;;   # blue
    APPROVAL)    printf '\033[32m' ;;   # green
    FAILURE)     printf '\033[31m' ;;   # red
    REFLECT)     printf '\033[35m' ;;   # magenta
    SKILL)       printf '\033[1;34m' ;; # bold blue — a skill-loop skill in use
    PROMOTE)     printf '\033[1;32m' ;; # bold green
    BOOTSTRAP)   printf '\033[1;36m' ;; # bold cyan
    FORMAT)      printf '\033[2m' ;;    # dim
    *)           printf '\033[37m' ;;
  esac
}

printf '%s\n' "${bold}  skill-loop · live activity${r}"
printf '%s\n' "${dim}  project: $PROJ${r}"
printf '%s\n' "${dim}  $(basename "$ACT") — corrections, new patterns, approvals, failures, reflections${r}"
printf '%s\n\n' "${dim}  ──────────────────────────────────────────────────────────────${r}"

if [ -n "${SL_WATCH_ONCE:-}" ]; then
  reader() { tail -n 200 "$ACT"; }
else
  reader() { tail -n 50 -F "$ACT" 2>/dev/null; }
fi

reader | while IFS="$(printf '\t')" read -r ts type msg; do
  [ -n "$type" ] || continue
  col="$(color_for "$type")"
  printf '%s%s%s  %s%-11s%s  %s\n' "$dim" "$ts" "$r" "$col" "$type" "$r" "$msg"
done
