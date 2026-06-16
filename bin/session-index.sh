#!/usr/bin/env bash
# SessionStart hook.  ZERO LLM.  Injects only a COMPACT index into context:
# which skill-loop skills exist + how many candidate rules are ready to promote.
# Deliberately tiny — this text is paid for on every single session.
#
# The skills themselves auto-load by relevance (progressive disclosure) because
# they live in .claude/skills/; this index just orients Claude and nudges the
# rare human actions (bootstrap once, promote when candidates pile up).

SL_TAG="session"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$SCRIPT_DIR/../lib/common.sh" 2>/dev/null || exit 0
cat >/dev/null 2>&1   # drain stdin (SessionStart payload); we don't need fields

emit_ctx() {
  if [ -n "$SL_JQ" ]; then
    "$SL_JQ" -nc --arg ctx "$1" \
      '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$ctx}}'
  else
    printf '%s\n' "$1"   # SessionStart also accepts raw stdout as context
  fi
}

# This project's conventions live in ONE skill file, with a section per concern.
names=""; n=0
if [ -f "$SKILL_FILE" ]; then
  n=1
  for f in "$SKILL_DIR"/*.md; do
    [ -f "$f" ] || continue
    b="$(basename "$f" .md)"; [ "$b" = "SKILL" ] && continue
    names="$names$b, "
  done
  names="$(printf '%s' "${names%, }" | cut -c1-120)"
fi

# This project not bootstrapped yet? (per-project: each repo gets its own skill)
if [ "$n" -eq 0 ]; then
  emit_ctx "skill-loop is installed but this project has no convention skill yet. Run /skill-loop:bootstrap once to crawl this codebase and generate it (kept personal to you, never pushed)."
  exit 0
fi

ready=0; total=0
if [ -f "$CANDIDATES_JSONL" ] && [ -n "$SL_JQ" ]; then
  PROMOTE_MIN="$(sl_cfg promote_min 2)"
  total="$("$SL_JQ" -s 'length' "$CANDIDATES_JSONL" 2>/dev/null)"; total="${total:-0}"
  ready="$("$SL_JQ" -s -r "[.[]|select((.recurrence // 1) >= $PROMOTE_MIN)]|length" "$CANDIDATES_JSONL" 2>/dev/null)"; ready="${ready:-0}"
fi

ctx="skill-loop active for this project (conventions skill auto-loads by relevance)."
prof="$(sl_cfg profile)"; [ -n "$prof" ] && ctx="$ctx Models: $prof."
[ -n "$names" ] && ctx="$ctx Covers: $names."
if [ "${ready:-0}" -gt 0 ]; then
  ctx="$ctx  ⚑ $ready candidate rule(s) ready to promote — run /skill-loop:promote."
elif [ "${total:-0}" -gt 0 ]; then
  ctx="$ctx  ($total candidate rule(s) still accruing in staging.)"
fi

emit_ctx "$ctx"
exit 0
