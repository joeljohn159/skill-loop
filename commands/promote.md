---
description: Promote recurring skill-loop candidate rules into real SKILL.md files, generalize them, prune stale entries, and git-commit each change so every evolution is revertable. Run occasionally, when candidates have accrued.
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
model: sonnet
---

# skill-loop: PROMOTE (Layer 5)

Promote staged candidate rules into your PERSONAL skills. This runs rarely and on
Sonnet. Be careful and conservative — these edits change Claude's future
behavior, so each must be clean, generalized, and individually revertable.

Personal skills: `${HOME}/.claude/skills/`  ·  State: `${HOME}/.skill-loop/`
(everything is personal — never the repo, never pushed)

## Step 0 — Honor the configured model
Read `model_promote` from `${HOME}/.skill-loop/config` (default
`sonnet`; set via `/skill-loop:configure`). If it is **not** `sonnet`, relaunch
the rest of this command via the **Task** tool (general-purpose agent) at that
model and relay the result. Otherwise continue here on Sonnet.

## Step 1 — Load candidates
Read `${HOME}/.skill-loop/candidates.jsonl` (machine source of
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
Map each candidate's `concern` to `${HOME}/.claude/skills/sl-<concern>/SKILL.md`.
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

## Step 5 — Keep it revertable (personal, no repo commits)
These skills are personal and live in `${HOME}/.claude/skills/`, outside any repo,
so there is NO git commit and nothing is ever pushed. Keep changes revertable:
- Before editing an existing `sl-<concern>/SKILL.md`, copy it to
  `${HOME}/.skill-loop/skill-history/sl-<concern>.$(date +%s).md`.
- To undo a promotion later, restore that backup or delete the rule/skill file.

## Step 6 — Concurrency note
Treat `candidates.jsonl` as the source of truth and rewrite it atomically (write
a temp file, then move). Append/merge into SKILL.md rather than overwrite, in
case another session edited it.

## Step 7 — Report
Summarize: which rules were promoted (and into which skill), what was pruned,
and how many candidates remain in staging.

For each promoted rule, also record it in the live activity log so it shows up in
`/skill-loop:logs`:
```bash
"${CLAUDE_PLUGIN_ROOT}/bin/event.sh" PROMOTE "<skill> <- <rule>"
```
