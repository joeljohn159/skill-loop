---
description: One-time crawl of the current repo to generate the judgment-level coding skills and the linter/formatter config needed so Claude doesn't fail on the next PR. Run once per repo.
argument-hint: "[subdir to focus on, optional]"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
model: opus
---

# skill-loop: BOOTSTRAP (Layer 1)

You are performing the **one-time** bootstrap of skill-loop for this repository.
Goal: read the codebase and emit exactly the conventions Claude needs so it
won't violate them on the next PR. This is the only expensive, high-capability
pass — make it count, but stay disciplined and conservative. Optional focus
path: `$ARGUMENTS`

Project root: `${CLAUDE_PROJECT_DIR}`
Plugin scripts: `${CLAUDE_PLUGIN_ROOT}/bin`

## Step 0 — Model preferences (first run only)
If `${HOME}/.skill-loop/config` has no `model_reflect=` line, the
user hasn't chosen models yet. Before crawling, settle it:
- Use **AskUserQuestion** to ask which model profile they want, offering
  **Balanced** (Recommended — Opus bootstrap, Sonnet promote, Haiku auto-learning),
  **Opus everywhere** (maximum quality, ignore token cost), and **Economy**
  (cheapest). This is exactly what `/skill-loop:configure` does — apply the same
  preset table and write the same keys (`profile`, `model_bootstrap`,
  `model_promote`, `model_reflect`, `model_ci`).
- If the session is non-interactive (e.g. headless), default to `balanced`.

The configured `model_reflect` governs the recurring automatic learning, so this
choice is the main cost lever. After writing it: if `model_bootstrap` (default
`opus`) is **not** `opus`, relaunch the rest of this bootstrap via the **Task**
tool (general-purpose agent) at that model and relay its result; otherwise
continue here on Opus.

## Step 1 — Detect the stack (cheap, deterministic first)
Use Bash/Glob/Grep, not guesswork:
- Languages & frameworks: by file-extension counts and manifest files
  (`package.json`, `pyproject.toml`/`requirements*.txt`, `go.mod`, `Cargo.toml`,
  `Gemfile`, `pubspec.yaml`, `*.csproj`, `composer.json`).
- Test runner & layout: test dirs/globs (`*_test.go`, `*.test.ts`, `tests/`,
  `*_spec.rb`, `test/`), and how tests are named/structured.
- EXISTING formatter/linter configs already in the repo (respect them):
  `.prettierrc*`, `.eslintrc*`, `eslint.config.*`, `ruff.toml`/`[tool.ruff]`,
  `.flake8`, `.rubocop.yml`, `.editorconfig`, `rustfmt.toml`, `.golangci.yml`,
  `dprint.json`, `biome.json`, `analysis_options.yaml`.

## Step 2 — Observe conventions (sample, don't read everything)
Read a handful of representative, recently-changed source files plus 2–3 tests.
Identify concrete, recurring conventions in these buckets:
- **naming** — file/dir/symbol naming intent (not casing a linter handles).
- **layering** — directory/module boundaries, allowed dependency directions,
  where business logic vs IO lives.
- **testing** — what gets a test, table-driven vs example, mocking style,
  fixture conventions.
- **error-handling** — exceptions vs Result/error returns, wrapping, logging,
  user-facing vs internal errors.
- **domain / architectural** — repo-specific patterns (e.g. "all API handlers
  return a typed envelope", "providers never import widgets").

## Step 3 — THE HARD SPLIT (the most important rule)
For every convention you found, classify it:

- **Deterministic** — anything a formatter/linter can mechanically enforce:
  indentation, quote style, import ordering, line length, trailing commas,
  semicolons, spacing. **DO NOT create a skill for these.** Instead:
  - If a config already exists, leave it; if a rule is missing from it, add it.
  - If no config exists, generate a minimal, idiomatic one for the detected
    stack (e.g. `.editorconfig` always; `.prettierrc` for JS/TS; `[tool.ruff]`
    in `pyproject.toml` or `ruff.toml` for Python; `rustfmt.toml`; etc.).
  - Layer 2 (enforce) auto-detects and runs the project's formatter per file, so
    no command needs recording. NOTE: a formatter config is the ONLY thing
    bootstrap may write into the repo — it's shared team infra, not a personal skill.

- **Judgment-level** — anything requiring taste/intent (the buckets in Step 2).
  These become skills. Each rule MUST come with a shell command that verifies
  compliance (a grep, a test invocation, a script). If you cannot write a
  verification command and the rule isn't enforceable by a linter, keep it only
  if it's clearly high-value; otherwise drop it.

When in doubt, prefer FEWER, higher-signal rules. Bloat is paid for in tokens
on every future session.

## Step 4 — Write tiny skills (judgment rules only) — personal & per-project
First resolve where this project's skills go (kept personal to you, never in the
repo, and scoped so they don't bleed into your other projects):
```bash
"${CLAUDE_PLUGIN_ROOT}/bin/sl-where.sh"   # prints STATE_DIR, SKILLS_DIR, SKILL_PREFIX, SKILL_PATHS
```
For each judgment concern with ≥1 real rule, write
`<SKILLS_DIR>/<SKILL_PREFIX><concern>/SKILL.md` using this exact shape (body =
a few dozen tokens of distilled rules):

```markdown
---
name: <SKILL_PREFIX><concern>
description: <one precise line so it auto-loads on relevance — e.g. "Error-handling for this repo: when to return errors vs throw.">
paths: <SKILL_PATHS>
---

# <Concern> conventions

- <imperative rule 1>
- <imperative rule 2>

**Verify:** `<command that checks compliance>`
```

`<concern>` examples: `naming`, `layering`, `testing`, `error-handling`, `domain`.
The `description` makes it auto-load by relevance; `paths` scopes it to THIS repo
so it never bleeds into your other projects.

## Step 5 — Initialize state (personal & per-project, in your HOME)
Personal prefs (the model keys from Step 0 + the promotion threshold) live in the
GLOBAL `${HOME}/.skill-loop/config`:
```
promote_min=2
```
Per-project signals/candidates live in the `STATE_DIR` printed by `sl-where.sh`
(already created). Never write anything into the repo or the plugin folder.

## Step 6 — Report back
Show the user:
1. Detected stack.
2. **Linter/formatter configs** created or modified (paths + why).
3. **Skills** generated: for each, the path, its `description`, the rules, and
   the verify command.
4. Anything you deliberately did NOT turn into a skill because a linter covers
   it (prove the hard split happened).
5. The `.skill-loop/config` you wrote.

Finally, record one line in the live activity log so the run shows in
`/skill-loop:logs`:
```bash
"${CLAUDE_PLUGIN_ROOT}/bin/event.sh" BOOTSTRAP "generated <N> skill(s) + <M> config(s)"
```

Keep skills minimal and every rule verifiable. After this runs once, the hooks
take over and the skills improve on their own.
