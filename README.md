# skill-loop

A Claude Code plugin that **bootstraps coding skills from an existing repo, then
automatically improves them as you work** — learning from anything new you do,
not just corrections. Expensive work is rare; the constant per-session cost is
**zero tokens unless a real signal is detected**.

## Install

```bash
/plugin marketplace add joeljohn159/skill-loop      # this GitHub repo
/plugin install skill-loop@skill-loop
```

Then, once per repo:

```bash
/skill-loop:bootstrap
```

## Commands
| Command | When | What it does |
|---|---|---|
| `/skill-loop:bootstrap` | once per repo | Crawl the codebase → generate skills + linter/formatter config. Asks your model profile on first run. |
| `/skill-loop:logs` | anytime | Open a live, readable activity log in a new terminal tab beside the session. |
| `/skill-loop:learn [lesson]` | anytime | Learn now from the current chat — optionally capture a lesson you state explicitly. |
| `/skill-loop:learn-from-ci` | on a red build | Paste a failing CI log → stage a fix rule. Any CI, runs locally, nothing in the runner. |
| `/skill-loop:promote` | when candidates pile up | Turn recurring candidates into committed skills (manual — never automatic). |
| `/skill-loop:configure` | anytime | Choose models per stage: Maximum / Balanced / Economy / Custom. |

## How it works — 6 layers

| Layer | Trigger | Cost | Job |
|------|---------|------|-----|
| 1 **Bootstrap** | `/skill-loop:bootstrap` | Opus, once | Crawl the repo. Judgment rules → tiny `SKILL.md`s. Linter-enforceable rules → formatter/linter config (the *hard split*). Every rule ships with a verify command. |
| 2 **Enforce** | PostToolUse (Write/Edit) | **0 tokens** | Run the project formatter on the edited file. Deterministic rules get auto-fixed and never pollute the skills. |
| 3 **Capture** | hooks | **0 tokens** | Append raw signals to `.skill-loop/queue.jsonl`: CORRECTION, NEW_PATTERN, APPROVAL, FAILURE. |
| 4 **Reflect** | Stop hook | gated; ~0 most sessions | Pre-scan deterministically. No signal → exit free. Else **one Haiku pass** reads only flagged diffs/lines, extracts + dedups candidate rules into `.skill-loop/candidates.md` with recurrence + confidence. Staging only. |
| 5 **Promote** | `/skill-loop:promote` | Sonnet, rare | Candidates that recurred ≥ N → generalized, written into the right `SKILL.md`, stale entries pruned, **each change git-committed** (revertable). |
| 6 **CI feedback** | `/skill-loop:learn-from-ci` | model_ci | Paste a failing build log from **any** CI; it + your local fix become a high-value FAILURE candidate. Runs locally — nothing is installed in your CI runner. |

## Token discipline
- The Stop reflection is the **only** per-session LLM call, and it is skipped
  entirely when the deterministic pre-scan finds no signal.
- Model tiering: **Haiku** for capture/extraction/dedup; **Sonnet/Opus** only for
  bootstrap and promote. Never the reverse.
- Skills stay tiny (progressive disclosure: the `description` loads, the body
  loads on match). SessionStart injects only a compact index, never the corpus.
- Dedup + a recurrence threshold gate every write, so skill files never bloat.

## Watching it work (live logs)
Run `/skill-loop:logs` to open a **new terminal tab/window beside your Claude
session** streaming a clean, colorized activity log — corrections captured, new
patterns, approvals, failures, reflections, and promotions:

```
13:05:58  SKILL        used: sl-error-handling          ← a skill-loop skill fired
13:05:59  FORMAT       prettier a.ts
13:06:00  CORRECTION   a.ts: user edited Claude's output after the write
13:06:00  REFLECT      reflecting on 2 signal(s) · haiku
13:06:00  REFLECT      staged 1 candidate(s); 0 ready to promote
13:06:00  PROMOTE      sl-error-handling ← Return Result for expected errors (abc1234)
```

The `SKILL used: …` line is how you confirm in the terminal that a learned skill
is actually being applied (it's logged whenever Claude invokes a skill).

This is the readable `.skill-loop/activity.log` — separate from the verbose
`.skill-loop/skill-loop.log` kept for debugging. On iTerm it opens a tab, on
Terminal a tab/window; anywhere else (VS Code terminal, remote box) it prints the
one command to run yourself: `bin/watch.sh <project>`.

## Learning on demand & from remote CI
Learning is local and session-based — it runs on the Claude you're already using,
never inside your CI.

- **From the current chat:** `/skill-loop:learn` flushes everything captured so far
  (corrections, failures, new patterns) through reflection immediately, instead of
  waiting for session end. Pass a lesson to capture it explicitly:
  `/skill-loop:learn "always validate webhook signatures"`.
- **From a remote build:** when CI goes red, paste the failing log into the chat and
  run `/skill-loop:learn-from-ci`. It saves the log, derives the fix diff from local
  git, and stages a high-value candidate. Any CI (GitHub, GitLab, Jenkins, a custom
  push-to-deploy server) — nothing runs in the runner.

## Choosing your models
The tiering above is the **Balanced** default. Pick a different profile any time
with `/skill-loop:configure` (bootstrap also asks on first run):

| Profile | bootstrap | promote | reflect (auto) | ci |
|---------|-----------|---------|----------------|----|
| **Maximum** — quality first, ignore token cost | opus | opus | opus | opus |
| **Balanced** — recommended default | opus | sonnet | haiku | haiku |
| **Economy** — cheapest | sonnet | haiku | haiku | haiku |
| **Custom** | pick each stage | | | |

`reflect` is the only automatic per-session call, so its model is the main cost
lever — a user who isn't worried about tokens can set everything to Opus. The
choice is stored in `.skill-loop/config` and takes effect immediately (the hook
re-reads it each run). Headless/CI: `/skill-loop:configure economy` with a
profile argument, no prompt.

## Where state lives (per project)
- `.claude/skills/sl-*/SKILL.md` — the generated, auto-loading skills (commit these).
- `.skill-loop/` — runtime state: `queue.jsonl` (signals), `candidates.jsonl`
  (machine source of truth), `candidates.md` (human view), `config`, `snap/`
  (snapshots for correction diffs), `wrote.jsonl` (write ledger). Gitignore this
  whole directory — it's transient runtime state.

## Safety
- Skill edits go to staging (`candidates.*`), then a human runs `/skill-loop:promote`,
  which git-commits each change — always revertable. **It never auto-promotes**;
  nothing rewrites a skill on its own.
- Concurrency: two sessions reflecting into the same files use an atomic
  `mkdir` lock and append/merge (recurrence-counted), never clobber.
- Hooks are defensive: every hook exits 0 and degrades gracefully (missing
  `jq`/`claude`/formatter, malformed input) so the session is never blocked.

## Layout
```
.claude-plugin/{plugin.json, marketplace.json}
commands/{bootstrap,promote,learn-from-ci,learn,configure,logs}.md
skills/skill-loop-help/SKILL.md     # ships with the plugin
hooks/hooks.json                    # SessionStart, PostToolUse, PostToolUseFailure, Stop
bin/{enforce,capture,reflect,session-index,watch,open-logs,event}.sh
lib/common.sh
```
All internal paths use `${CLAUDE_PLUGIN_ROOT}` / `${CLAUDE_PROJECT_DIR}`.
