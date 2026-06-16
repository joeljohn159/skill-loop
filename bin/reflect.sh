#!/usr/bin/env bash
# LAYER 4 — REFLECT.  Stop hook.  The ONLY per-session LLM call, and it is
# SKIPPED ENTIRELY when a deterministic pre-scan finds no signal — so the vast
# majority of sessions cost zero tokens.
#
# Flow:
#   1. Recursion / disable guards (never recurse into our own headless claude).
#   2. Deterministic pre-scan (zero LLM): finalize CORRECTION / manifest-drift
#      signals by hashing the write-ledger against the current disk.
#   3. If the queue is still empty -> exit 0.  ZERO tokens.  (Common case.)
#   4. Atomically CLAIM the queued signals (rename, so concurrent sessions get
#      disjoint batches), assemble a COMPACT bundle (signals + tiny excerpts +
#      existing rules for dedup — never the transcript), and run ONE headless
#      Haiku pass that emits candidate rules as JSON.
#   5. Merge survivors into candidates.jsonl (recurrence-counted, lock-guarded)
#      and re-render candidates.md.  Staging only — never touches a SKILL.md.
#
# Can also be invoked directly:  reflect.sh --force-ci <logfile> <difffile>
# (used by /skill-loop:learn-from-ci) to inject a high-value FAILURE signal.

SL_TAG="reflect"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$SCRIPT_DIR/../lib/common.sh" 2>/dev/null || exit 0

DATE="$(date +%Y-%m-%d)"
MODE="stop"          # stop = Stop hook; ci = learn-from-ci; now = on-demand /learn
NOTE=""
case "$1" in
  --force-ci) MODE="ci" ;;
  --now)      MODE="now"; NOTE="$2" ;;
esac

# ----- guards ---------------------------------------------------------------
# 1) Never recurse: our own headless claude inherits this env var.
if [ -n "${SKILL_LOOP_REFLECTING:-}" ]; then exit 0; fi
[ "$(sl_cfg reflect on)" = "off" ] && exit 0

INPUT=""
if [ "$MODE" = "stop" ]; then
  INPUT="$(cat 2>/dev/null)"
  SL_SESSION="$(sl_json_get "$INPUT" .session_id)"; SL_SESSION="${SL_SESSION:-unknown}"
  # 2) stop_hook_active => this Stop was itself triggered by a stop hook; bail.
  [ "$(sl_json_get "$INPUT" .stop_hook_active)" = "true" ] && exit 0
fi
sl_ensure_dirs

# ----- recurrence threshold (configurable) ----------------------------------
PROMOTE_MIN="$(sl_cfg promote_min 2)"

# ----- emit a brief, low-noise note to the user via systemMessage -----------
note() { printf '{"continue":true,"suppressOutput":true,"systemMessage":"skill-loop: %s"}\n' "$1"; }

# ===========================================================================
# 2. DETERMINISTIC PRE-SCAN (zero LLM): correction / manifest drift detection
# ===========================================================================
detect_corrections() {
  [ -f "$WROTE" ] || return 0
  [ -n "$SL_JQ" ] || return 0
  # Most-recent unique files written (cap to keep this cheap).
  local files; files="$("$SL_JQ" -r '.file' "$WROTE" 2>/dev/null | awk 'NF' | tail -300 | awk '!seen[$0]++' | tail -100)"
  [ -n "$files" ] || return 0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    [ -f "$f" ] || continue
    local cur last; cur="$(sl_hash_file "$f")"
    last="$("$SL_JQ" -r --arg f "$f" 'select(.file==$f)|.hash' "$WROTE" 2>/dev/null | tail -1)"
    [ -n "$last" ] || continue
    [ "$cur" = "$last" ] && continue          # unchanged since Claude wrote it
    # Changed by someone other than Claude's tools -> a correction.
    local snap excerpt=""; snap="$(sl_snap_path "$f")"
    if [ -f "$snap" ]; then
      excerpt="$(diff -u "$snap" "$f" 2>/dev/null \
        | grep -E '^[+-]' | grep -vE '^(\+\+\+|---)' | head -24 | cut -c1-200)"
      excerpt="$(printf '%s' "$excerpt" | cut -c1-1200)"
    fi
    case "$(basename "$f")" in
      package.json|requirements*.txt|pyproject.toml|go.mod|Cargo.toml|Gemfile|pubspec.yaml|composer.json)
        sl_emit_signal NEW_PATTERN "$f" "manifest changed by user after Claude wrote it" "$excerpt" 2 ;;
      *)
        sl_emit_signal CORRECTION "$f" "user edited Claude's output after the write" "$excerpt" 3 ;;
    esac
    sl_record_write "$f"   # refresh baseline + snapshot so we flag this change only once
  done <<EOF
$files
EOF
}

# ----- CI mode: inject the failing log + fix diff as one big FAILURE ---------
if [ "$MODE" = "ci" ]; then
  logf="$2"; difff="$3"
  log_excerpt="$( [ -f "$logf" ] && tail -120 "$logf" | cut -c1-4000 )"
  diff_excerpt="$( [ -f "$difff" ] && head -200 "$difff" | cut -c1-4000 )"
  sl_emit_signal FAILURE "" "CI failure + fix diff" "$(printf 'LOG:\n%s\n\nFIX DIFF:\n%s' "$log_excerpt" "$diff_excerpt")" 4
  sl_log "ci signal injected from $logf / $difff"
else
  # on-demand /learn may carry an explicit lesson from the chat
  if [ "$MODE" = "now" ] && [ -n "$NOTE" ]; then
    sl_emit_signal NOTE "" "lesson noted from chat" "$NOTE" 3
  fi
  detect_corrections
fi

# ===========================================================================
# 3. GATE: no signals -> ZERO-cost exit. This is the common path.
# ===========================================================================
if [ ! -s "$QUEUE" ]; then
  sl_log "no signals; zero-cost exit"
  exit 0
fi

# claude available?  If not, leave the queue for a future session.
if [ -z "$SL_CLAUDE" ]; then
  sl_log "signals present but 'claude' not on PATH; leaving queue for later"
  exit 0
fi

# ===========================================================================
# 4. CLAIM a disjoint batch (concurrency-safe) and build a compact bundle.
# ===========================================================================
BATCH="$STATE_DIR/batch.$SL_SESSION.$$.jsonl"
if sl_lock "$QUEUE.lock"; then
  mv "$QUEUE" "$BATCH" 2>/dev/null && : >"$QUEUE"
  sl_unlock "$QUEUE.lock"
fi
[ -s "$BATCH" ] || { rm -f "$BATCH" 2>/dev/null; exit 0; }

NSIG="$(wc -l <"$BATCH" | tr -d ' ')"
sl_log "reflecting over $NSIG signal(s)"

# Existing rules (descriptions only) so Haiku dedups instead of re-proposing.
EXISTING_RULES=""
if [ -d "$SKILLS_DIR" ]; then
  EXISTING_RULES="$(grep -rhE '^description:' "$SKILLS_DIR/${SL_SKILL_PREFIX}"*/SKILL.md 2>/dev/null | sed 's/^description: */- /' | cut -c1-160 | head -60)"
fi
EXISTING_CANDS=""
[ -f "$CANDIDATES_JSONL" ] && EXISTING_CANDS="$("$SL_JQ" -r '"- " + .key + ": " + .rule' "$CANDIDATES_JSONL" 2>/dev/null | head -80)"

# Signals rendered compactly (type + detail + small excerpt). NOT the transcript.
SIGNALS="$("$SL_JQ" -r '"### " + .type + " (weight " + (.weight|tostring) + ")\nfile: " + (.file // "-") + "\nwhat: " + .detail + "\nexcerpt: " + ((.excerpt // "") | .[0:1000])' "$BATCH" 2>/dev/null)"

PROMPT_FILE="$STATE_DIR/.reflect-prompt.$$"
cat >"$PROMPT_FILE" <<EOF
You are the extraction step of a self-improving coding-skills loop. You are
reading ONLY captured signals (not a transcript). From them, extract durable,
JUDGMENT-LEVEL coding rules for THIS codebase.

HARD RULES:
- Output ONLY a JSON array. No prose, no markdown fences. If nothing is worth
  keeping, output exactly: []
- DROP anything a formatter/linter already enforces (indentation, quotes,
  import order, line length, trailing commas). Those are not skills.
- DROP one-off noise, secrets, file paths, and anything not generalizable.
- Do NOT duplicate an existing rule or existing candidate (listed below); if a
  signal reinforces one, reuse its exact "key" so it can be recurrence-counted.
- Prefer rules that come with a shell command that VERIFIES compliance.

Each array element MUST be:
{
  "key": "kebab-case-stable-id",        // reuse existing key if same rule
  "concern": "naming|layering|testing|error-handling|dependencies|domain|ci",
  "rule": "one imperative sentence, project-general (no specific paths)",
  "verify": "shell command that checks it, or \"\" if none",
  "confidence": "low|medium|high",
  "sources": ["CORRECTION"],            // signal types that drove this
  "note": "<= 12 words of context"
}

EXISTING SKILL RULES (do not re-propose):
${EXISTING_RULES:-(none yet)}

EXISTING CANDIDATES (reuse key to reinforce):
${EXISTING_CANDS:-(none yet)}

CAPTURED SIGNALS:
$SIGNALS
EOF

# Model is user-configurable (default haiku). CI uses model_ci, falling back to
# model_reflect. A user who doesn't care about tokens can set these to opus.
if [ "$MODE" = "ci" ]; then
  RMODEL="$(sl_cfg model_ci "$(sl_cfg model_reflect haiku)")"
else
  RMODEL="$(sl_cfg model_reflect haiku)"
fi
sl_log "invoking headless claude (model=$RMODEL) over $NSIG signals"
sl_event REFLECT "reflecting on $NSIG signal(s) · $RMODEL"
RAW="$(SKILL_LOOP_REFLECTING=1 "$SL_CLAUDE" -p --model "$RMODEL" --max-turns 1 \
        --output-format text <"$PROMPT_FILE" 2>>"$LOG")"
rc=$?
rm -f "$PROMPT_FILE"

# Extract the JSON array defensively (model may wrap it).
JSON="$(printf '%s' "$RAW" | "$SL_PY" -c '
import sys,re,json
s=sys.stdin.read()
m=re.search(r"\[.*\]", s, re.S)
if not m: print("[]"); sys.exit(0)
try:
    json.loads(m.group(0)); print(m.group(0))
except Exception:
    print("[]")
' 2>/dev/null)"
[ -n "$JSON" ] || JSON="[]"

if [ "$rc" -ne 0 ] || [ -z "$RAW" ]; then
  # Reflection failed — put the batch back so nothing is lost, then exit.
  sl_log "headless claude failed (rc=$rc); re-queuing batch"
  sl_event REFLECT "model call failed — $NSIG signal(s) re-queued for next time"
  if sl_lock "$QUEUE.lock"; then cat "$BATCH" >>"$QUEUE" 2>/dev/null; sl_unlock "$QUEUE.lock"; fi
  rm -f "$BATCH"; exit 0
fi

# ===========================================================================
# 5. MERGE survivors into candidates.jsonl (recurrence-counted), re-render md.
# ===========================================================================
NCAND="$(printf '%s' "$JSON" | "$SL_JQ" 'length' 2>/dev/null)"; NCAND="${NCAND:-0}"
added=0
if [ "$NCAND" -gt 0 ] && sl_lock "$CANDIDATES_JSONL.lock"; then
  [ -f "$CANDIDATES_JSONL" ] || : >"$CANDIDATES_JSONL"
  i=0
  while [ "$i" -lt "$NCAND" ]; do
    obj="$(printf '%s' "$JSON" | "$SL_JQ" -c ".[$i]" 2>/dev/null)"
    i=$((i + 1))
    [ -n "$obj" ] || continue
    "$SL_JQ" -s -c --argjson new "$obj" --arg today "$DATE" '
      ( (map(.key) | index($new.key)) as $idx
        | if $idx == null
          then . + [ $new + {recurrence:1, first_seen:$today, last_seen:$today} ]
          else .[$idx] |= ( .recurrence = ((.recurrence // 1) + 1)
                            | .last_seen = $today
                            | .sources = (((.sources // []) + ($new.sources // [])) | unique)
                            | .verify = (if (.verify // "") == "" then ($new.verify // "") else .verify end)
                            | .confidence = (if ($new.confidence) == "high" then "high" else (.confidence // $new.confidence) end) )
          end
      ) | .[]
    ' "$CANDIDATES_JSONL" >"$CANDIDATES_JSONL.tmp" 2>/dev/null \
      && mv "$CANDIDATES_JSONL.tmp" "$CANDIDATES_JSONL" && added=$((added + 1))
  done

  # Render the human-readable candidates.md from the JSONL source of truth.
  {
    printf '# skill-loop candidate rules (staging — never auto-applied)\n\n'
    printf '_Promote with `/skill-loop:promote` once recurrence >= %s._\n\n' "$PROMOTE_MIN"
    "$SL_JQ" -r -s 'sort_by(-.recurrence)[]
      | "## [" + .concern + "] " + .rule + "\n"
      + "- key: `" + .key + "`\n"
      + "- recurrence: " + (.recurrence|tostring) + "  |  confidence: " + (.confidence // "low") + "\n"
      + "- sources: " + ((.sources // [])|join(", ")) + "\n"
      + (if (.verify // "") != "" then "- verify: `" + .verify + "`\n" else "" end)
      + (if (.note // "") != "" then "- note: " + .note + "\n" else "" end)
      + "- seen: " + (.first_seen // "?") + " → " + (.last_seen // "?") + "\n"
      + (if (.recurrence // 1) >= '"$PROMOTE_MIN"' then "- **READY TO PROMOTE**\n" else "" end)' \
      "$CANDIDATES_JSONL" 2>/dev/null
  } >"$CANDIDATES.tmp" 2>/dev/null && mv "$CANDIDATES.tmp" "$CANDIDATES"
  sl_unlock "$CANDIDATES_JSONL.lock"
fi

# Archive the processed batch (bounded) for auditing, then drop it.
cat "$BATCH" >>"$STATE_DIR/queue.archive.jsonl" 2>/dev/null || true
tail -1000 "$STATE_DIR/queue.archive.jsonl" >"$STATE_DIR/queue.archive.tmp" 2>/dev/null \
  && mv "$STATE_DIR/queue.archive.tmp" "$STATE_DIR/queue.archive.jsonl"
rm -f "$BATCH"

READY="$("$SL_JQ" -s -r '[.[]|select((.recurrence // 1) >= '"$PROMOTE_MIN"')]|length' "$CANDIDATES_JSONL" 2>/dev/null)"
sl_log "reflect done: $added candidate update(s); $READY ready to promote"

if [ "${added:-0}" -gt 0 ]; then
  sl_event REFLECT "staged $added candidate(s); $READY ready to promote"
  if [ "${READY:-0}" -gt 0 ]; then
    note "$added candidate rule(s) staged; $READY ready — run /skill-loop:promote"
  else
    note "$added candidate rule(s) staged for review"
  fi
fi
exit 0
