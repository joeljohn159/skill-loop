---
description: Learn right now from the current chat — flush everything captured this session (corrections, failures, new patterns, approvals) through the reflect pipeline immediately, instead of waiting for the session to end. Optionally pass a lesson to remember.
argument-hint: "[optional: a lesson to remember from this chat]"
allowed-tools: Read, Bash
model: haiku
---

# skill-loop: LEARN NOW

Run the reflect pipeline on demand over what this session has captured so far,
without waiting for the Stop hook. Useful right after a failure, a correction, or
a decision you want captured.

## Steps
1. Trigger reflection (it runs at the configured `model_reflect`, locally):
   - If the user passed text in `$ARGUMENTS`, treat it as an explicit lesson from
     the chat and inject it:
     ```bash
     "${CLAUDE_PLUGIN_ROOT}/bin/reflect.sh" --now "$ARGUMENTS"
     ```
   - Otherwise just process captured signals:
     ```bash
     "${CLAUDE_PLUGIN_ROOT}/bin/reflect.sh" --now
     ```
2. Read back this project's `candidates.md` — its folder is the `STATE_DIR`
   printed by `"${CLAUDE_PLUGIN_ROOT}/bin/sl-where.sh"` — report what was
   staged or reinforced, and whether anything is now ready for
   `/skill-loop:promote`.
3. If nothing was captured and no lesson was given, the pre-scan exits with zero
   tokens — say there was nothing new to learn yet.

Note: this still only stages candidates. Skills change only when you run
`/skill-loop:promote`.
