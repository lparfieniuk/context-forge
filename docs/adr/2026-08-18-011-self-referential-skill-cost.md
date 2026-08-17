# ADR-011: Keep Self-Referential Skills in One Plugin

**Date:** 2026-08-18
**Status:** Accepted
**Deciders:** lukasz-parfieniuk

## Context

The harness injects the name and description of every installed skill into every
session, in every repository. Five ContextForge skills only ever do useful work
inside `~/Projects/context-forge` itself:

| Skill | description bytes |
|---|---|
| `evolve` | 167 |
| `evolve-apply` | 161 |
| `help` | 158 |
| `optimize-rules` | 149 |
| `plugin-audit` | 143 |
| **total** | **778 B ≈ 194 tokens** |

All 22 skill descriptions together cost 3706 B ≈ 926 tokens per session. The five
self-referential ones are 21% of that.

The question was whether to split the plugin into `context-forge` (portable) and
`context-forge-dev` (self-referential), so a foreign repo pays only for the
portable half.

## Decision

**Keep one plugin. Pay the 194 tokens.**

## Rationale

The saving is 194 tokens per session. The split costs, permanently:

- a second `plugin.json` and a second marketplace entry to keep version-synced;
- `convert.ts` routing every skill to one of two output trees, and a new class of
  bug where a skill lands in the wrong one;
- `plugin-audit.sh` and the parity tests running against two surfaces instead of
  one — every gate doubles;
- an install and enablement step per plugin, which has to be *disabled* per repo
  to realise the saving at all;
- `${CLAUDE_PLUGIN_ROOT}` becoming ambiguous — `~/.claude/CLAUDE.md` and the
  `rule-index` skill both resolve rule files through it, and there would now be
  two roots;
- a routing decision attached to every future skill.

194 tokens is roughly 0.15% of a 130k effective window. The maintenance surface
is permanent and the saving is not measurable against session-to-session
variance. The trade is bad in the direction of splitting.

## Counter-position (on record)

The argument for splitting does not disappear: skill descriptions are the one
part of the plugin that is unconditionally injected everywhere, so they are the
only surface where "portable" and "self-referential" have a real cost
difference. If ContextForge grows a second cluster of repo-local skills — say
another five — the figure reaches ~400 tokens and the arithmetic is worth
re-running. The threshold to revisit is **≥500 tokens of self-referential skill
description**, not a feeling that there are "a lot of them".

## Rejected alternatives

- **Merge `evolve-apply` into `evolve` behind a flag.** Saves 161 B ≈ 40 tokens
  and costs an argument-parsing branch plus a rewrite of both skill bodies. Not
  worth it at that size.
- **Shorten the five descriptions.** Would save ~80 tokens with no structural
  cost, but descriptions are what the model matches on when selecting a skill;
  trimming them trades a measured 80 tokens for an unmeasured drop in selection
  accuracy. Not taken without evidence.
