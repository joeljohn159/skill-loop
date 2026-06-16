---
description: Promote recurring skill-loop candidate rules into your personal per-project skills, generalize them, prune stale entries, and keep a backup so every change is revertable. Run occasionally, when candidates have accrued.
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
model: sonnet
---

# skill-loop: PROMOTE (Layer 5)

Promote staged candidate rules into your PERSONAL skills. This runs rarely and on
Sonnet. Be careful and conservative — these edits change Claude's future
behavior, so each must be clean, generalized, and individually revertable.

Everything is personal & per-project — never the repo, never pushed. First resolve
this project's locations and use the values literally below:
```bash
"${CLAUDE_PLUGIN_ROOT}/bin/sl-where.sh"   # prints STATE_DIR, SKILL_NAME, SKILL_FILE, SKILL_PATHS
```

## Step 0 — Honor the configured model
Read `model_promote` from `${HOME}/.skill-loop/config` (default
`sonnet`; set via `/skill-loop:configure`). If it is **not** `sonnet`, relaunch
the rest of this command via the **Task** tool (general-purpose agent) at that
model and relay the result. Otherwise continue here on Sonnet.

## Step 1 — Load candidates
Read `<STATE_DIR>/candidates.jsonl` (machine source of truth; `candidates.md` is
the human-readable render). Read the recurrence threshold from the global
`${HOME}/.skill-loop/config` (`promote_min`, default 2).

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

## Step 3 — Merge into this project's skill (router + per-concern files)
This project's skill lives in `<SKILL_DIR>`: a router `SKILL.md` plus one
supporting file per concern (`<concern>.md`).
- If `<SKILL_FILE>` doesn't exist, create it (frontmatter `name: <SKILL_NAME>`, a
  precise `description`, `paths: <SKILL_PATHS>`) with an index linking the concern
  files.
- For each candidate, append its rule + `**Verify:**` line to the matching
  `<SKILL_DIR>/<concern>.md` (`naming.md`, `layering.md`, `testing.md`,
  `error-handling.md`, `domain.md`). If it's a new concern, create the file and add
  it to the router's index. Never clobber existing rules; de-duplicate in spirit.
- Keep each concern file small. If one grows past ~8 rules, tighten or drop the
  weakest. The router is paid every relevant session; concern files load on demand.

## Step 4 — Prune
- Remove stale or low-value entries from skills: rules contradicted by the new
  ones, duplicates, or rules whose verify command no longer makes sense.
- Remove promoted candidates from `<STATE_DIR>/candidates.jsonl`, then
  regenerate `<STATE_DIR>/candidates.md` from the remaining JSONL (sorted by
  recurrence desc). Leave sub-threshold candidates in place to keep accruing.

## Step 5 — Keep it revertable (personal, no repo commits)
These skills are personal and live in `${HOME}/.claude/skills/`, outside any repo,
so there is NO git commit and nothing is ever pushed. Keep changes revertable:
- Before editing, snapshot the whole skill folder:
  `cp -R "<SKILL_DIR>" "<STATE_DIR>/skill-history/<SKILL_NAME>.$(date +%s)"`.
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
