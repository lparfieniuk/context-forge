# Tier Routing

## SYSTEM CONSTRAINTS

The sub-agent tool is `Agent` (fields `subagent_type`, `model`, `prompt`). `Task` is a legacy alias the binary still accepts — write `Agent(...)`, and match BOTH names in any hook (`"matcher": "Agent|Task"`).
NEVER spawn Agent() when a Tier 0 or Tier 1 alternative exists.
NEVER spawn >2 concurrent Tier 3 Tasks without explicit authorization.
ALWAYS default to `model: "haiku"` (Haiku) for all Tier 2 tasks.
NEVER escalate Haiku to Sonnet unless all 3 escalation gate conditions are met.
ALWAYS check `core/scripts/_index.yaml` before spawning any Agent().
If task touches ≤2 files: BANNED to spawn sub-agent. Apply change directly.
ALWAYS use KERNEL template structure for all Agent() prompts (rule 011).
NEVER accept a sub-agent's `[SUCCESS]` as proof of completion — ALWAYS evaluate its `Done-when:` predicate in the parent after it returns (rule 011). The worker reports; the parent decides. A false predicate is one rule-004 strike, NEVER a retry loop.
NEVER let a spawned sub-agent spawn its own sub-agents — delegation depth is capped at 1. Recursive Language Models (Zhang/Kraska/Khattab, arXiv:2512.24601, abstract verified 2026-08-12) is the case FOR depth-1 fan-out: handing each child a clean context instead of one shared window carries prompts "up to two orders of magnitude beyond model context windows", and RLM-Qwen3-8B beats its own base by 28.3% on average. An independent reproduction (arXiv:2603.02615, verified 2026-08-12) is the case AGAINST going deeper: depth-2 turned a 3.6s retrieval into 344.5s (~95x) while DEGRADING accuracy on the simpler tasks. Depth-1 fan-out is the win, depth-2 is overthinking with a bill attached.

## Cost Hierarchy

| Tier | Executor | Model ID | Token Cost | When |
|------|----------|----------|-----------|------|
| 0 | Inline CLI (`rg`, `diff`, `wc`, `git`) | none | ~0 | One-off mechanical queries |
| 1 | Shell scripts (`core/scripts/`) | none | ~50 amortized | Recurring checks, script exists |
| 2 | `Agent(model: "haiku")` — Haiku | `claude-haiku-4-5` | ~200–1k | Multi-file reasoning, LLM judgment |
| 3 | `Agent(model: "sonnet")` — Sonnet | `claude-sonnet-5` | ~600–5k | Architecture, planning, complex reasoning |
| 3+ | `Agent(model: "opus")` — Opus | `claude-opus-5` | ~1k–10k | Novel architecture decisions only |

ALWAYS pick the cheapest tier that produces a correct result.

Agent tool model enum: `sonnet | opus | haiku | fable`. `Agent(model: "fable")` (Fable 5) is reserved for the hardest, long-horizon work only — it is the most expensive model and sits outside the normal tier hierarchy.

Sub-agent output contract: ALWAYS return ≤2,000 tokens. NEVER return raw tool outputs cross-agent.

## Decision Tree

| Question | Answer | Tier |
|----------|--------|------|
| Quick yes/no heuristic? | Yes | 0 (inline CLI) |
| One-off mechanical query (rg/diff/wc)? | Yes | 0 (inline CLI) |
| Script exists in `core/scripts/`? | Yes | 1 (run script) |
| Task requires LLM judgment across files? | Yes | 2 (Haiku default) |
| Architecture or planning decision? | Yes | 3 (Sonnet) |

## Haiku-First Heuristic

ALWAYS default to Haiku (`claude-haiku-4-5`) for Tier 2.
NEVER upgrade to Sonnet (`claude-sonnet-5`) without passing ALL three escalation gate conditions:

1. Task touches >5 interrelated files across multiple architectural layers, AND
2. Requires semantic reasoning beyond pattern application (not search/replace, not codegen), AND
3. Haiku already attempted and returned `[ESCALATE]` or failed silently.

NEVER escalate to Opus (`claude-opus-5`) unless ALL of the following are true:
1. Task touches >10 files across multiple architectural layers, AND
2. Requires novel architecture decisions (not pattern application), AND
3. Sonnet already attempted and returned `[ESCALATE]` or produced inadequate results.

## Scribe Dispatch (Observation Masking)

Before a large output enters primary context, compress it — Tier 1 first (`core/scripts/tools/compress-observation.sh`), cf-scribe (`model: "haiku"`) only when the compression needs judgment. Scribe returns `[SCRIBE OUTPUT] Summary / Key finding: path:line / Recommendation [END SCRIBE OUTPUT]`; the raw input is discarded after.
Thresholds: Bash build/test/lint >100 lines or >5 KB · search >50 matches · any tool result >3 KB · worklog >15 entries.
Sub-agent responses MUST cap at ≤2,000 tokens — excess tokens cause systematic errors, not just cost.
Measured 2026-09-05: zero cf-scribe spawns across a 30-day transcript window. The mechanism was described in every session and exercised in none, so the Tier 1 script is the default and a Scribe spawn is the exception that needs a reason.

## Few-shot example

**Input:** "Refactor AuthService across 6 files — add tenantId to all methods."
**Reasoning:** >2 files, requires LLM judgment, no script exists → Tier 2 (Haiku).
**Output:**
```
Agent(
  subagent_type: "executor",
  model: "haiku",
  prompt: "Context: PROJ-3456. Task: Add tenantId to AuthService methods. Files: [list 6]. Constraints: NEVER change method return types. Format: Return [SUCCESS] + modified file list. Verify: rg 'tenantId' src/auth/ shows N matches."
)
```

## Validation gate (MANDATORY before Agent() or sub-agent spawn)

- [ ] Checked `core/scripts/_index.yaml` for Tier 0/1 alternative?
- [ ] Task genuinely touches >2 files (sub-agent justified)?
- [ ] `model: "haiku"` used for Tier 2 (not "default")?
- [ ] Tier 3 concurrent count ≤2?
- [ ] KERNEL template (Context/Task/Constraints/Format/Verify/Done-when) used in prompt?
- [ ] `Done-when:` predicate evaluated in the parent after the child returned?
If any unchecked → fix before spawning sub-agent.
