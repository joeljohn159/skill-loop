---
name: skill-loop-help
description: How the skill-loop plugin works and what to do with it — explains bootstrapping repo conventions into skills, the automatic capture/reflect learning loop, and when to run /skill-loop:bootstrap, /skill-loop:promote, and /skill-loop:learn-from-ci. Use when the user asks about skill-loop, candidate rules, why a formatter ran automatically, or how their coding skills are evolving.
---

# skill-loop

A self-improving coding-skills loop. It learns this repo's conventions once, then
keeps them current automatically while staying near-zero tokens per session.

## The six layers
1. **Bootstrap** (`/skill-loop:bootstrap`, Opus, once): crawl the repo; turn
   judgment-level conventions into tiny `.claude/skills/sl-*/SKILL.md` files and
   linter-enforceable rules into formatter/linter config (the "hard split").
2. **Enforce** (PostToolUse hook, 0 tokens): auto-run the project formatter on
   each edited file, so deterministic rules never become skills.
3. **Capture** (hooks, 0 tokens): append raw signals to `.skill-loop/queue.jsonl`
   — CORRECTION, NEW_PATTERN, APPROVAL, FAILURE.
4. **Reflect** (Stop hook, gated): if no signal, exit free. If signals exist, one
   Haiku pass extracts/dedups candidate rules into `.skill-loop/candidates.md`.
5. **Promote** (`/skill-loop:promote`, Sonnet, rare): move candidates that
   recurred ≥ N into the right SKILL.md, generalize, prune, git-commit each.
6. **CI feedback** (`/skill-loop:learn-from-ci <log> <diff>`): feed a red build +
   its fix into the same pipeline as a high-value FAILURE signal.

## What to do
- New repo: run `/skill-loop:bootstrap` once.
- Then just work. Corrections, new libs, clean merges, and failures are captured
  automatically; most sessions cost zero extra tokens.
- When the session-start note says candidates are ready, run `/skill-loop:promote`.
- Candidates are staging only — skills change only on promote (never automatic),
  and a backup is kept so every change is revertable.

Everything is personal and per-project, in your HOME — never the repo: skills in
`~/.claude/skills/sl-<project>-*` (scoped with `paths:`), state in
`~/.skill-loop/projects/<project>/`. Set `scope=global` in `~/.skill-loop/config`
to share one set across all projects.
