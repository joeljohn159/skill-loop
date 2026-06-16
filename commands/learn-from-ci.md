---
description: Learn from a failing CI build (any provider). Paste the red build's log into the chat (or pass a saved file); skill-loop turns it plus your local fix into a candidate rule — entirely locally. Nothing runs in your CI.
argument-hint: "[log-file] [git-range] (optional — or just paste the log)"
allowed-tools: Read, Write, Glob, Grep, Bash
model: haiku
---

# skill-loop: LEARN FROM CI

Your CI runs remotely; the learning happens here, in this session, on your local
(already-authenticated) Claude. Nothing needs to be installed in the CI runner —
the build just has to fail; you bring the result here.

Accepted input (any one):
- The user **pasted the failing build log** into the chat.
- A path to a saved log: `$1`.
- An optional git range for the fix diff: `$2` (e.g. `main...HEAD`).

## Steps
1. **Get the log.**
   - If `$1` is an existing file, use it.
   - Otherwise write the log the user pasted into this conversation to
     `${HOME}/.skill-loop/ci-fail.log`.
   - If no log is available, ask the user to paste it, then stop.
2. **Get the fix diff from LOCAL git** (no remote calls):
   - If `$2` is given: `git -C "${CLAUDE_PROJECT_DIR}" diff $2`
   - Else if the working tree has uncommitted changes: `git -C "${CLAUDE_PROJECT_DIR}" diff`
   - Else use the most recent commit: `git -C "${CLAUDE_PROJECT_DIR}" diff HEAD~1 HEAD`
   Write it to `${HOME}/.skill-loop/ci-fix.diff`.
3. **Feed both into the reflect pipeline** (runs at `model_ci`, locally; it sets
   its own recursion guard):
   ```bash
   "${CLAUDE_PLUGIN_ROOT}/bin/reflect.sh" --force-ci \
       "${HOME}/.skill-loop/ci-fail.log" \
       "${HOME}/.skill-loop/ci-fix.diff"
   ```
4. **Report**: read back `.skill-loop/candidates.md` and say which rule(s) were
   created or reinforced, and whether anything is ready for `/skill-loop:promote`.
   A failure that produced a fix is high-signal — promote it promptly.

Provider-agnostic by design (GitHub, GitLab, Jenkins, a custom push-to-deploy
server — all the same here, because you paste the log). If you later want to
automate fetching the log by build id/URL for your specific CI, ask and I'll add
a small provider snippet.
