---
name: optimize-rules
description: Audits ContextForge rules for token cost, cross-rule duplication, and wrong activation mode. Use when the always-on rule budget grows.
model: sonnet
---

## What This Does

Performs a full token audit of all rules in `core/rules/`. Specifically:

1. **Token cost estimation** — estimates token count per rule file using `wc -c` as a proxy
   (1 token ≈ 4 bytes). Sums total always-on budget.
2. **Duplication detection** — uses `rg` to find paragraphs or constraint phrases that appear
   in 2+ rule files.
3. **Activation mode suggestions** — identifies `mode: always` rules used in fewer than 80%
   of sessions and suggests downgrading to `mode: intelligent`.
4. **Budget report** — total always-on token budget vs ≤6k target.
5. **Quality score** — run `core/scripts/tools/quality-score.sh` (Tier 1) for a deterministic
   composite score per rule and skill. It uses the full-denominator model: every defined
   dimension counts toward the denominator, so a missing few-shot / validation-gate / `<example>`
   caps the score honestly (reported as `4/7`, never hidden by renormalization). Surface any
   file below 1.00 with its `missing` dimensions.

## Quality Score (Tier 1)

```bash
bash core/scripts/tools/quality-score.sh            # TSV: kind, file, score, passed, total, missing
```

Dimensions — rules (7): SYSTEM CONSTRAINTS section, hard-constraint density (≥5), no soft
language in constraints, few-shot example, validation gate, YAML pair, within token budget.
Skills (6): frontmatter `name`, `description`, purpose section, Constraints section, `<example>`,
within budget. A run ends with an `average` line across all files.

**Replication-gated eval (roadmap).** Structural score answers "is the rule well-formed"; it does
NOT answer "does the rule change behavior". A future harness (cc-thinking-skills pattern) would run
skill-vs-placebo comparisons and only promote a rule/skill that shows a replicated effect — kept as
a separate, non-deterministic gate so the deterministic score stays reproducible.

## When to Use

**Trigger:**
- `/optimize-rules` command (manual invocation)
- Periodic token audit (recommended after adding 3+ new rules)
- Always-on budget report shows >6k tokens

## How to Use

1. List all rule files: `ls core/rules/*.md | sort`
2. For each file: estimate tokens via `wc -c <file>` ÷ 4.
3. Sum tokens for all `mode: always` (`alwaysApply: true`) rules.
4. Run duplication scan: `rg -l "ALWAYS|NEVER" core/rules/ | xargs rg -c "phrase"` for common phrases.
5. Identify rules with `mode: always` that are narrow-scope (patterns suggest <80% session use).
6. Generate report with total budget, duplications, and mode-change suggestions.

## Output Format

```
[RULES AUDIT]
- Total rules: 12
- Always-on rules: 4 (001, 002, 003, 010)
- Always-on budget: 7,200 tokens (target: ≤6,000)
- Over budget by: 1,200 tokens

Duplication clusters:
  - "NEVER read raw source" appears in: cf-shadow-index, cf-code-search, cf-module-index
    → Suggestion: consolidate to cf-shadow-index, reference from others

Mode-change suggestions:
  - cf-context-loading (003): used only on new_feature/refactor tasks
    → Suggest: mode: always → mode: intelligent (pattern: "new_feature|refactor|bugfix")
  - cf-prompt-caching (006): rarely triggered outside bundle attachment sessions
    → Suggest: mode: always → mode: intelligent (pattern: "bundle|attach|cache")

Estimated savings if accepted: ~1,400 tokens/session
[END RULES AUDIT]
```

## Constraints

ALWAYS report total always-on budget vs ≤6k target.
ALWAYS detect duplication using `rg` — NEVER eyeball rules manually.
NEVER suggest deleting constraints that are functionally distinct even if phrasing is similar.
ALWAYS include estimated token savings for each suggested change.
NEVER auto-apply mode changes — present as suggestions only.
ALWAYS flag when always-on budget exceeds 6k tokens.
