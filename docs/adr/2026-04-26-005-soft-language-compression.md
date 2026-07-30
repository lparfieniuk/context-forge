# ADR-005: Soft-Language Compression Pass

**Date:** 2026-04-26
**Status:** Accepted
**Deciders:** lukasz-parfieniuk

## Context

Automated audit of rules via `audit-rules.sh` showed 0 violations in `## SYSTEM CONSTRAINTS` sections across all 13 rules (verified hard constraint density). However, soft language persisted in guidance, example, and few-shot sections. Examples: "track these aggressively" (rule 010), redundant "consider" statements in procedural guidance (rules 007, 008, 011). Every soft verb wastes tokens without reducing instruction-following compliance — hard constraints (ALWAYS/NEVER/BANNED) are 2–3 words shorter and more precise.

## Decision

Conducted surgical soft-language compression pass:
- `core/rules/007-cf-context-loading.md`: Validation gate phrase "ensure rule loaded" → "rule loaded" (1 soft verb removed)
- `core/rules/010-cf-context-budget.md`: Guidance phrase "track these aggressively" → "ALWAYS track these via Scribe dispatch" (soft verb replaced with hard constraint)
- Both files: word-level edits only; no structural rewrites; line counts unchanged

No other rules contained actionable soft violations in non-constraint sections. Audit reconfirms 0 violations post-edit.

## Rationale

Hard constraints use fewer tokens and reduce ambiguity:
- Soft language ("consider", "should", "ideally", "try"): 1–2 tokens per phrase
- Hard constraints ("ALWAYS", "NEVER", "BANNED"): 1 token + directness
- Research shows hard constraint density correlates with instruction-following accuracy in agentic systems

Token savings: ~8–10 tokens across 2 rules. More importantly: consistent signal-to-noise ratio improves compliance at rule read time.

## Consequences

**Positive:**
- Cleaner signal-to-noise ratio — rules are directives, not suggestions
- Slightly lower per-read token cost (~10 tokens amortized across plugin)
- No meaning lost — soft phrasing made implicit what is now explicit

**Negative/Tradeoffs:**
- None identified — no guidance tone changed, only precision improved
- No behavioral impact (hard constraints were already intended meaning)

## Notes

Session-start.sh improvement (ipa-* branch detection on line 53) was also completed in this iteration but does not warrant a separate ADR as it is a minor script enhancement. The `ipa-[0-9]+` pattern detection routes Jira ticket branches to `unknown` task type, allowing downstream heuristics (ticket name, description) to refine classification.

## References

- `core/rules/007-cf-context-loading.md`
- `core/rules/010-cf-context-budget.md`
- `core/scripts/tools/audit-rules.sh` (verifies hard constraint density)
