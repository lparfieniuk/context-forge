# Contributing

The one rule that explains every other rule here: **`core/` is source, everything else is build
output.** Editing a generated file is a no-op — the next `npm run convert` overwrites it, and the
parity gate fails the build in the meantime.

| Artifact | Edit here | Generated (never edit) |
|---|---|---|
| Rules | `core/rules/<NNN>-cf-<id>.{md,yaml}` | `.claude/rules/*.md`, `.cursor/rules/*.mdc` |
| Skills | `core/skills/<id>/SKILL.md` | `skills/<id>/SKILL.md` |
| Agents | `core/agents/<id>.{md,yaml}` | `agents/<id>.md`, `.cursor/agents/<id>.md` |
| Module map | `core/_index.yaml` | — |
| Hooks, scripts, tests | `hooks/`, `core/scripts/`, `scripts/` | — |

## Setup

```bash
nvm use            # .nvmrc pins Node 22; the suite needs >= 20
npm install
npm run test:audit # should print "final: PASS" before you change anything
```

You also need `ripgrep` (`rg`) and `jq` on PATH. `grep` is deliberately blocked by a hook.

## The loop

```bash
# 1. edit under core/ (or hooks/, core/scripts/, scripts/)
# 2. propagate to every installed path
npm run convert
# 3. run the gate that CI runs
npm run test:audit
```

`npm run test:audit` is the single gate. It runs, in order: `validate-index`, `check-parity`,
`audit-runtime-artifacts`, `audit-doc-claims`, `audit-plugin-surface`, `audit-rules`,
`benchmark-tokens`, and the vitest suite. CI runs exactly this, so a green local run means a green
build. Individual pieces are runnable on their own during a debug loop:

```bash
npm test                                            # vitest only
npm run validate-index                              # _index.yaml consistency
bash core/scripts/tools/benchmark-tokens.sh         # token cost per artifact
bash core/scripts/tools/audit-doc-claims.sh --plugin-root .
```

## Adding a module

Order matters — the index is checked before the files exist, on purpose.

1. Register the entry in `core/_index.yaml` **first** (id, source paths, installed paths, tier, model).
2. Create the source files under `core/rules/` or `core/skills/<id>/`.
3. `npm run validate-index` — fix every `ERROR`.
4. `npm run convert`.
5. `npm run test:audit`.

`audit-doc-claims` cross-checks counts written in prose ("20 skills", "11 hooks") against the index,
so adding a skill without updating `README.md`, `CLAUDE.md`, `CHANGELOG.md`, and `core/skills/help/`
fails the build. That is intended: the docs are part of the artifact.

## Writing a rule

Rules are a dual YAML + Markdown pair, and the format is enforced by `audit-rules.sh`
(see `core/rules/012-cf-rule-authoring.md` for the full contract). Every rule body needs:

- a `## SYSTEM CONSTRAINTS` section at the top, stated as ALWAYS / NEVER / BANNED — no soft language
- at least one `## Few-shot example` with **Input / Reasoning / Output**
- a closing `## Validation gate` checklist

Number ranges: `000–099` always-on core, `100–199` frontend patterns, `200–299` backend,
`900–999` meta/tooling. Set `activation.mode: intelligent` unless the rule genuinely applies to
more than 80% of sessions — every always-on rule is a permanent tax on the context budget, which is
the thing this plugin exists to protect.

`core/scripts/tools/scaffold-rule.sh` and `scaffold-skill.sh` generate a conforming skeleton.

## Shell scripts

Scripts run on macOS (BSD userland) and in CI (GNU coreutils). Both must work:

- `stat`: try GNU first (`stat -c %Y … || stat -f %m …`), then guard the result is numeric. The
  reverse order silently corrupts output on GNU — see the `1.1.0` entry in `CHANGELOG.md`.
- `date -j -f` is BSD-only; always provide a fallback.
- `md5 -q` (BSD) / `md5sum` (GNU): use `hooks/lib/common.sh`'s `pwd_hash` instead of open-coding it.
- `set -euo pipefail` is the default; an unguarded `rg` in a command substitution aborts the whole
  hook when it matches nothing. Append `|| true` where an empty result is valid.
- Never infer success from a pipeline ending in `tail`/`head`/`grep` — the exit code is that of the
  last element.

## Commits

Conventional Commits (`feat:`, `fix:`, `docs:`, `test:`, `ci:`, `refactor:`). The body should say
*why*, and name the root cause when it is a fix — the changelog is written from these.

A `pre-commit-review.sh` hook blocks `git commit` until a review marker exists. Bypass with
`SKIP_REVIEW=1` **in the environment** (`export SKIP_REVIEW=1`, not as a command prefix — the hook
runs before the command and never sees a prefix assignment).

## Pull requests

Include the output of `npm run test:audit`, note any new always-on token cost, and update
`CHANGELOG.md` under `[Unreleased]`.
