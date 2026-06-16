---
description: Promote recurring skill-loop candidate rules into real SKILL.md files, generalize them, prune stale entries, and git-commit each change so every evolution is revertable. Run occasionally, when candidates have accrued.
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
model: sonnet
---

# skill-loop: PROMOTE (Layer 5)

Promote staged candidate rules into the repo's skills. This runs rarely and on
Sonnet. Be careful and conservative — these edits change Claude's future
behavior, so each must be clean, generalized, and individually revertable.

Project root: `${CLAUDE_PROJECT_DIR}`
State: `${CLAUDE_PROJECT_DIR}/.skill-loop/`

## Step 0 — Honor the configured model
Read `model_promote` from `${CLAUDE_PROJECT_DIR}/.skill-loop/config` (default
`sonnet`; set via `/skill-loop:configure`). If it is **not** `sonnet`, relaunch
the rest of this command via the **Task** tool (general-purpose agent) at that
model and relay the result. Otherwise continue here on Sonnet.

## Step 1 — Load candidates
Read `${CLAUDE_PROJECT_DIR}/.skill-loop/candidates.jsonl` (machine source of
truth; `candidates.md` is the human-readable render of the same data). Read the
recurrence threshold from `.skill-loop/config` (`promote_min`, default 2).

Select **only** candidates with `recurrence >= promote_min`. List them for the
user before changing anything.

## Step 2 — Generalize each survivor
For each selected candidate:
- Strip project-specific specifics (absolute paths, one-off file names, a single
  variable name) into a general, imperative rule that applies repo-wide.
- Ensure it has a **verification command**. If the candidate's `verify` is empty
  or too narrow, write a better one (a grep, a test command, a script). A rule
  with no way to check it is low value — drop it unless clearly important.
- Confirm it is genuinely judgment-level. If on reflection a linter/formatter
  should own it, instead add it to the relevant config (and say so), and do NOT
  make it a skill.

## Step 3 — Write into the correct SKILL.md
Map each candidate's `concern` to `${CLAUDE_PROJECT_DIR}/.claude/skills/sl-<concern>/SKILL.md`.
- If the skill exists: **merge** — append the new rule under the rules list and
  keep/append its verify command. Never clobber existing rules; de-duplicate if
  the rule is already present in spirit.
- If it doesn't exist: create it using the same tiny template bootstrap uses
  (frontmatter `name` + precise `description`, a short rules list, `**Verify:**`).
- Keep each skill small. If a skill grows past ~8 rules, split by sub-concern or
  drop the weakest rules. Tokens here are paid on every relevant session.

## Step 4 — Prune
- Remove stale or low-value entries from skills: rules contradicted by the new
  ones, duplicates, or rules whose verify command no longer makes sense.
- Remove promoted candidates from `.skill-loop/candidates.jsonl`, then
  regenerate `.skill-loop/candidates.md` from the remaining JSONL (sorted by
  recurrence desc). Leave sub-threshold candidates in place to keep accruing.

## Step 5 — Commit each change (revertable history)
The project is under git. Commit so every evolution can be reverted:
- Stage and commit **each promoted/edited skill separately** (or tightly grouped
  by concern) with a clear message, e.g.:
  `skill-loop: promote rule 'return Result for expected errors' into sl-error-handling (recurrence 3)`
- Commit the candidates pruning separately:
  `skill-loop: prune promoted candidates from staging`
- If `git` isn't initialized or there's nothing to commit, say so and skip
  gracefully — never fail the command over git.
- Do NOT push. Stop at commits.

## Step 6 — Concurrency note
Treat `candidates.jsonl` as the source of truth and rewrite it atomically (write
a temp file, then move). Append/merge into SKILL.md rather than overwrite, in
case another session edited it.

## Step 7 — Report
Summarize: which rules were promoted (and into which skill), what was pruned,
each commit hash + message, and how many candidates remain in staging.

For each promoted rule, also record it in the live activity log so it shows up in
`/skill-loop:logs`:
```bash
"${CLAUDE_PLUGIN_ROOT}/bin/event.sh" PROMOTE "<skill> <- <rule>  (<commit-hash>)"
```
