#!/usr/bin/env bash
# skill-loop shared helpers — sourced by every bin/ script.
# Pure shell, ZERO LLM. Must never crash a caller: every function degrades
# gracefully and returns 0 on internal failure. Hooks that source this are
# expected to `exit 0` regardless, so the user's session is never blocked.

# --- tool discovery (cached once per process) -------------------------------
SL_JQ="$(command -v jq 2>/dev/null || true)"
SL_PY="$(command -v python3 2>/dev/null || true)"
SL_SHASUM="$(command -v shasum 2>/dev/null || true)"
SL_CLAUDE="$(command -v claude 2>/dev/null || true)"

# --- path resolution --------------------------------------------------------
# Plugin root: env wins (set by Claude Code in hooks); else derive from this
# file's own location so scripts also work when invoked directly from bin/.
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  SL_PLUGIN_ROOT="$CLAUDE_PLUGIN_ROOT"
else
  _sl_self="${BASH_SOURCE[0]:-$0}"
  _sl_dir="$(cd "$(dirname "$_sl_self")" 2>/dev/null && pwd)"
  SL_PLUGIN_ROOT="$(dirname "$_sl_dir")"
fi

# Project being worked on: Claude Code exports CLAUDE_PROJECT_DIR to hooks.
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"

STATE_DIR="$PROJECT_DIR/.skill-loop"
SKILLS_DIR="$PROJECT_DIR/.claude/skills"     # generated skills live here (auto-discovered)
QUEUE="$STATE_DIR/queue.jsonl"               # raw captured signals (append-only)
CANDIDATES="$STATE_DIR/candidates.md"        # staged rules awaiting promotion
WROTE="$STATE_DIR/wrote.jsonl"               # ledger of files Claude wrote (for correction detection)
CONFIG="$STATE_DIR/config"                   # key=value: formatters, lint cmds, stack, thresholds
LOG="$STATE_DIR/skill-loop.log"              # raw/verbose debug log
ACTIVITY="$STATE_DIR/activity.log"           # clean, human-readable narrative (for the /logs viewer)
SNAP_DIR="$STATE_DIR/snap"                   # snapshots of what Claude wrote (for correction diffs)
CANDIDATES_JSONL="$STATE_DIR/candidates.jsonl"  # machine source-of-truth; candidates.md is rendered from it
SL_MAX_SNAP=262144                           # don't snapshot files larger than 256 KB

# Session id: env if present, else "unknown" (scripts override after parsing stdin).
SL_SESSION="${CLAUDE_SESSION_ID:-unknown}"

# --- basics -----------------------------------------------------------------
sl_have() { command -v "$1" >/dev/null 2>&1; }

sl_ensure_dirs() {
  mkdir -p "$STATE_DIR" 2>/dev/null || true
  [ -f "$QUEUE" ]      || : >"$QUEUE" 2>/dev/null || true
  [ -f "$CANDIDATES" ] || printf '# skill-loop candidate rules (staging — never auto-promoted)\n\n' >"$CANDIDATES" 2>/dev/null || true
}

sl_log() {
  sl_ensure_dirs
  printf '%s [%s] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "${SL_TAG:-skill-loop}" "$*" >>"$LOG" 2>/dev/null || true
}

# One clean, readable narrative line for the live /skill-loop:logs viewer.
# Format is TAB-separated: HH:MM:SS <TYPE> <message>. Kept terse on purpose.
sl_event() {
  local type="$1"; shift
  local msg; msg="$(printf '%s' "$*" | tr '\t\n' '  ' | cut -c1-160)"
  sl_ensure_dirs
  printf '%s\t%s\t%s\n' "$(date '+%H:%M:%S')" "$type" "$msg" >>"$ACTIVITY" 2>/dev/null || true
}

# Read a config value: sl_cfg KEY [default]
sl_cfg() {
  local key="$1" def="${2:-}"
  if [ -f "$CONFIG" ]; then
    local v; v="$(grep -E "^${key}=" "$CONFIG" 2>/dev/null | head -1 | cut -d= -f2-)"
    [ -n "$v" ] && { printf '%s' "$v"; return 0; }
  fi
  printf '%s' "$def"
}

# --- JSON: read a dotted path out of a JSON string (jq -> python3) ----------
# Usage: sl_json_get "$JSON" .tool_input.file_path
sl_json_get() {
  local json="$1" path="$2"
  if [ -n "$SL_JQ" ]; then
    printf '%s' "$json" | "$SL_JQ" -r "$path // empty" 2>/dev/null
  elif [ -n "$SL_PY" ]; then
    printf '%s' "$json" | "$SL_PY" - "$path" 2>/dev/null <<'PY'
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
cur = d
for part in [p for p in sys.argv[1].split(".") if p]:
    if isinstance(cur, dict) and part in cur:
        cur = cur[part]
    else:
        cur = None; break
if cur is None:
    pass
elif isinstance(cur, (dict, list)):
    print(json.dumps(cur))
elif isinstance(cur, bool):
    print("true" if cur else "false")
else:
    print(cur)
PY
  fi
}

# --- content hashing for correction detection ------------------------------
sl_hash_file() {
  [ -f "$1" ] || { printf 'NOFILE'; return 0; }
  if [ -n "$SL_SHASUM" ]; then
    "$SL_SHASUM" "$1" 2>/dev/null | awk '{print $1}'
  else
    cksum "$1" 2>/dev/null | awk '{print $1"-"$2}'
  fi
}

# --- atomic lock (mkdir is atomic on POSIX; flock is absent on macOS) -------
sl_lock() {
  local lock="$1" tries=0
  while ! mkdir "$lock" 2>/dev/null; do
    # Reclaim a stale lock (>1 min old) left by a crashed process.
    if [ -n "$(find "$lock" -prune -mmin +1 2>/dev/null)" ]; then
      rm -rf "$lock" 2>/dev/null
      continue
    fi
    tries=$((tries + 1))
    [ "$tries" -ge 50 ] && return 1
    sleep 0.1
  done
  return 0
}
sl_unlock() { rm -rf "$1" 2>/dev/null; return 0; }

# --- emit a raw signal to the queue (concurrency-safe append) ---------------
# Usage: sl_emit_signal TYPE FILE DETAIL EXCERPT [WEIGHT]
sl_emit_signal() {
  local type="$1" file="$2" detail="$3" excerpt="$4" weight="${5:-1}"
  case "$weight" in ''|*[!0-9]*) weight=1 ;; esac
  sl_ensure_dirs
  local ts line; ts="$(date +%s)"
  if [ -n "$SL_JQ" ]; then
    line="$("$SL_JQ" -nc \
      --arg ts "$ts" --arg type "$type" --arg session "$SL_SESSION" \
      --arg file "$file" --arg detail "$detail" --arg excerpt "$excerpt" \
      --argjson weight "$weight" \
      '{ts:$ts,type:$type,session:$session,file:$file,detail:$detail,excerpt:$excerpt,weight:$weight}' 2>/dev/null)"
  elif [ -n "$SL_PY" ]; then
    line="$("$SL_PY" - "$ts" "$type" "$SL_SESSION" "$file" "$detail" "$excerpt" "$weight" 2>/dev/null <<'PY'
import sys, json
print(json.dumps({"ts":sys.argv[1],"type":sys.argv[2],"session":sys.argv[3],
                  "file":sys.argv[4],"detail":sys.argv[5],"excerpt":sys.argv[6],
                  "weight":int(sys.argv[7])}))
PY
)"
  else
    return 0   # no safe JSON encoder available; skip rather than corrupt the queue
  fi
  [ -n "$line" ] || return 0
  if sl_lock "$QUEUE.lock"; then
    printf '%s\n' "$line" >>"$QUEUE" 2>/dev/null || true
    sl_unlock "$QUEUE.lock"
  fi
  sl_log "signal $type file=$file detail=$detail weight=$weight"
  local where=""; [ -n "$file" ] && where="$(basename "$file"): "
  sl_event "$type" "${where}${detail}"
  return 0
}

# Snapshot file path (filename = hash of the real path, so any chars are safe).
sl_snap_path() {
  local h
  if [ -n "$SL_SHASUM" ]; then h="$(printf '%s' "$1" | "$SL_SHASUM" 2>/dev/null | awk '{print $1}')"
  else h="$(printf '%s' "$1" | cksum 2>/dev/null | awk '{print $1"-"$2}')"; fi
  printf '%s/%s' "$SNAP_DIR" "$h"
}

# Record that Claude wrote a file: append hash to the ledger AND snapshot the
# content (bounded), so reflect can diff what Claude left vs the current disk.
sl_record_write() {
  local file="$1"
  [ -n "$file" ] || return 0
  sl_ensure_dirs
  # Snapshot the content (skip very large files to stay cheap).
  if [ -f "$file" ]; then
    local sz; sz="$(wc -c <"$file" 2>/dev/null | tr -d ' ')"
    if [ "${sz:-0}" -le "$SL_MAX_SNAP" ]; then
      mkdir -p "$SNAP_DIR" 2>/dev/null || true
      cp -f "$file" "$(sl_snap_path "$file")" 2>/dev/null || true
    fi
  fi
  local ts hash line; ts="$(date +%s)"; hash="$(sl_hash_file "$file")"
  if [ -n "$SL_JQ" ]; then
    line="$("$SL_JQ" -nc --arg ts "$ts" --arg file "$file" --arg hash "$hash" --arg session "$SL_SESSION" \
      '{ts:$ts,file:$file,hash:$hash,session:$session}' 2>/dev/null)"
  elif [ -n "$SL_PY" ]; then
    line="$("$SL_PY" - "$ts" "$file" "$hash" "$SL_SESSION" 2>/dev/null <<'PY'
import sys, json
print(json.dumps({"ts":sys.argv[1],"file":sys.argv[2],"hash":sys.argv[3],"session":sys.argv[4]}))
PY
)"
  else
    return 0
  fi
  [ -n "$line" ] || return 0
  if sl_lock "$WROTE.lock"; then
    printf '%s\n' "$line" >>"$WROTE" 2>/dev/null || true
    sl_unlock "$WROTE.lock"
  fi
  return 0
}
