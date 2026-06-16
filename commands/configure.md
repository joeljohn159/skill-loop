---
description: Choose which Claude models skill-loop uses for each stage (bootstrap, promote, the automatic reflect/learn loop, and CI). Pick a preset like "Opus everywhere" or set each stage yourself.
argument-hint: "[maximum|balanced|economy] (optional; omit to choose interactively)"
allowed-tools: Read, Write, Bash, AskUserQuestion
model: haiku
---

# skill-loop: CONFIGURE MODELS

Let the user decide the quality/cost trade-off. Some users won't worry about
token cost and want Opus everywhere; others want the cheap defaults.

Config file: `${CLAUDE_PROJECT_DIR}/.skill-loop/config`
Requested preset (optional): `$1`

## Presets
| Preset | bootstrap | promote | reflect (auto) | ci |
|--------|-----------|---------|----------------|----|
| **maximum** — quality first, ignore token cost | opus | opus | opus | opus |
| **balanced** — recommended default | opus | sonnet | haiku | haiku |
| **economy** — cheapest | sonnet | haiku | haiku | haiku |
| **custom** — pick each | you choose | you choose | you choose | you choose |

Only the recurring work (`reflect`, `ci`) and the rare `promote`/`bootstrap`
commands consume tokens; `reflect` is the only automatic per-session call, so its
model is the one that matters most for ongoing cost.

## Steps
1. **Determine the choice.**
   - If `$1` is `maximum`, `balanced`, or `economy`, use that preset (no prompt —
     this also works headlessly in CI).
   - Otherwise, use **AskUserQuestion** to ask which preset the user wants
     (offer Balanced first, marked Recommended; then "Opus everywhere" / maximum;
     then Economy; the tool always adds an "Other" escape). If they pick custom,
     ask one more question per stage with options opus / sonnet / haiku.
2. **Resolve to four values** `MB MP MR MC` (bootstrap, promote, reflect, ci)
   using the table above. Valid model names: `opus`, `sonnet`, `haiku`.
3. **Write the config** atomically, preserving any non-model keys:
   ```bash
   cfg="${CLAUDE_PROJECT_DIR}/.skill-loop/config"; mkdir -p "$(dirname "$cfg")"; touch "$cfg"
   grep -vE '^(profile|model_bootstrap|model_promote|model_reflect|model_ci)=' "$cfg" > "$cfg.tmp" 2>/dev/null || true
   {
     echo "profile=<chosen-preset-or-custom>"
     echo "model_bootstrap=<MB>"
     echo "model_promote=<MP>"
     echo "model_reflect=<MR>"
     echo "model_ci=<MC>"
   } >> "$cfg.tmp"
   mv "$cfg.tmp" "$cfg"
   ```
4. **Confirm** to the user: print the resulting four model assignments and note
   that `reflect` (the automatic learning pass) now uses `<MR>` on every
   signal-bearing session. The change takes effect immediately — the reflect hook
   reads this file at run time; no restart needed.
