---
description: Open skill-loop's live activity log in a new terminal tab/window next to this session — a clean, readable stream of what it captures, learns, and updates (not the verbose debug log).
allowed-tools: Bash
model: haiku
---

# skill-loop: LIVE LOGS

Open the readable, colorized activity stream in a separate terminal so the user
can watch skill-loop work alongside the Claude session.

Run exactly this and show the user the output:

```bash
"${CLAUDE_PLUGIN_ROOT}/bin/open-logs.sh" "${CLAUDE_PROJECT_DIR}"
```

This opens a new tab (iTerm) or window (Terminal) running the live viewer. On a
host where it can't auto-open (e.g. a VS Code integrated terminal or a remote
box), it prints the one command the user can paste into their own tab.

Then tell the user, briefly:
- The viewer shows clean lines like `CORRECTION  auth.ts: user edited …`,
  `REFLECT  staged 1 candidate …`, `PROMOTE  sl-error-handling ← …`.
- It is the readable view of `.skill-loop/activity.log`; the verbose
  `.skill-loop/skill-loop.log` is still there for debugging.
- Leave the tab open; new lines appear as you work. Close it with Ctrl-C.
