# Module Index

## SYSTEM CONSTRAINTS

NEVER invent skill, rule, or agent paths — ALWAYS look up `core/_index.yaml` first.
NEVER assume installed path equals source path — they differ after conversion.
NEVER edit `core/_index.yaml` manually without running `validate-index.sh` after.
NEVER create source files before registering entry in `core/_index.yaml`.
ALWAYS run `npm run convert` after adding a module — installed files do NOT update automatically.

## Quick Lookup Protocol

1. Open `core/_index.yaml` — single source of truth for all modules.
2. Find entry by `id` — use `source` field for editing, `installed_*` for runtime.
3. If `references` field exists — supplementary docs at that path.
4. If `script` field exists — backing shell script at that path.

## File Layout

| Location | Purpose |
|----------|---------|
| `core/_index.yaml` | Master module map |
| `core/skills/<id>/SKILL.md` | Skill source (edit this) |
| `core/skills/<id>/skill.yaml` | Skill metadata |
| `skills/<id>/SKILL.md` | Installed Claude Code skill (auto-generated) |
| `core/rules/<NNN>-cf-<id>.md` | Rule source (edit this) |
| `core/rules/<NNN>-cf-<id>.yaml` | Rule metadata |
| `.cursor/rules/<NNN>-cf-<id>.mdc` | Installed Cursor rule (auto-generated) |
| `core/agents/<id>.md` | Agent source (edit this) |
| `agents/<id>.md` | Installed Claude Code agent (auto-generated) |
| `.cursor/agents/<id>.md` | Installed Cursor agent (auto-generated) |

`convert.ts` DOES generate `.claude/rules/<id>.md` (one file per rule with `installed_claude` set — 18 today) and `.cursor/rules/*.mdc`. It does NOT generate `.cursor/skills/`; do not present that path as an active runtime artifact.

Cost note (measured 2026-07-22): every file in `.claude/rules/` is loaded as a project instruction on every session in this repo — currently ~13.5k tokens. `activation: intelligent` and `claude.include_in_claude_md: false` do NOT gate that: `convertClaudeRules()` writes any rule with `installed_claude` set and never reads either flag. Treat the rule count as a live context-budget cost (rule 010), not as free metadata.

## Adding a New Module

Step 1: Add entry to `core/_index.yaml` (BEFORE creating files).
Step 2: Create source files in `core/skills/<id>/` or `core/rules/`.
Step 3: Run `validate-index.sh` — fix all ERRORs.
Step 4: Run `npm run convert` to push to `skills/`, `agents/`, and `.cursor/`.

## Few-shot example

**Input:** "Where is the `repo-audit` skill source file?"
**Reasoning:** NEVER read raw files for discovery. Check `_index.yaml` first.
**Output:**
```bash
rg "id: repo-audit" core/_index.yaml -A 3
# Returns: source: core/skills/repo-audit/SKILL.md
```

## Validation gate (MANDATORY before any module lookup or creation)

- [ ] Checked `core/_index.yaml` before reading source files?
- [ ] Used `source` field for editing (not installed path)?
- [ ] After adding module: ran `validate-index.sh` and got STATUS: OK?
- [ ] Ran `npm run convert` to sync installed files?
If any unchecked → fix before proceeding.
