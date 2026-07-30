# ContextForge — Hypotheses Queue

> Claims that are plausible but **unmeasured**. Nothing here is a rule. Each entry names the
> measurement that would promote it (or kill it). Source discipline (rule 016): a lead from a
> blog / Instagram OCR / vendor benchmark is a hypothesis, never a fact — it earns a rule only
> after a local measurement, ideally via **cf-bench** (`~/Projects/ai-tools`, A/B/C harness).
>
> Established 2026-07-21 from a full pass over the local ai-knowledge base under the
> "context-forge as a plugin consumed in other repos" frame. Provenance is recorded honestly:
> most numbers below are vendor- or social-sourced and are quarantined here on purpose.

## How an entry graduates

1. Design a cf-bench task (or reuse one) whose hidden assertion the claim would change.
2. Run A/B (± C placebo) at N≥5, report medians + Fisher exact (their `summarize.sh`).
3. If the effect holds → draft a rule via `/evolve`; if not → strike the entry, keep the null result.

---

## H1 — ContextForge rules pay for themselves (the core self-test)

**Claim:** The always-on CF rules (001 token-efficiency, 003 tier-routing, 005 code-search)
reduce `cost_usd` / `turns` at equal `success`, versus a repo with no config.

**Why it matters:** CF has 18 rules and has *never been measured*. This is the single most
important open question about the whole plugin.

**Measurement (cf-bench bridge — wiring is ~10 lines, do NOT run without Lukasz's budget nod):**
- add `cf-bench/configs/cf-core/CLAUDE.md` = the CF always-on SYSTEM-CONSTRAINTS blocks (no task knowledge)
- on an already-calibrated task: `VARIANTS="A B C D"` + `CONFIG_D="cf-core"`
- **the honest comparison is D vs C, not D vs A** — C (`generic`) already controls for "having any
  CLAUDE.md at all", so D−C isolates *CF's rules* from *mere config presence*.
- **prediction:** D ≈ C on `success` (CF encodes no task fact), D < C on `cost_usd`/`turns` if
  001/003/005 do what they claim. A null D−C would be the most useful negative result CF could get.
- respects cf-bench law: metrics-first, `--setting-sources project` isolation, N≥5, human-gated spend.

**Status: MEASURED 2026-07-22 — REFUTED on this task class.** Run: cf-bench
`js-express-errors-010` (cost-only), A/B/C/D × N=10, Sonnet, CLI 2.1.217, $5.84/41 runs,
`results/bench-20260722-104241.tsv`. All 40 valid runs succeeded (100%), so cost is the pure signal.

| pair | metric | delta | p (Mann-Whitney) |
|---|---|---|---|
| **D vs A** (CF vs bare) | **cost** | **+6.9%** | **0.016** |
| D vs A | turns | −4.8% | 0.162 (ns) |
| **D vs C** (CF vs placebo) | **turns** | **−16.7%** | **0.001** |
| D vs C | cost | −1.2% | 0.462 (ns) |
| **C vs A** (placebo vs bare) | cost / turns | **+8.2% / +14.3%** | **0.003 / 0.007** |
| **B vs A** (task knowledge) | cost | **−3.6%** | **0.028** |

Read: **CF's always-on core is significantly MORE expensive than no config at all (+6.9%)** and
shows no significant cost saving over a generic placebo. Mechanism is visible in the data —
`cache_creation` median A 12,526 → D 13,467: ~940 tokens of rules loaded on every single run.
The rules *do* work behaviourally (D cuts turns 12→10 vs placebo, p=0.001 — generic advice makes
the agent flail, CF stops that), but the token cost of carrying them eats the entire gain.
Only **encoded task knowledge (B) is actually cheaper than bare** — exactly cf-bench's own thesis.

Caveats, stated honestly: (1) ONE task, single-file bugfix class — near worst case for CF, since
rules 002/003 target multi-file work with manifests and sub-agents that do not exist in a bare
fixture; (2) isolation (`--setting-sources project`) tests rules-as-injected-CLAUDE.md only —
hooks, skills and shadow-index are user-scope and excluded; (3) n=10, sd ≈ $0.007;
(4) **variant D under-tests the real plugin by ~3x** — see the ledger below.

### Always-on token ledger (measured 2026-07-22, Tier 0)

| what | est. tokens | note |
|---|---|---|
| `configs/generic` (placebo C) | ~46 | baseline "a CLAUDE.md exists" |
| **`configs/cf-core` (variant D as tested)** | **~534** | compressed always-on constraints |
| **`~/.claude/CLAUDE.md` — what a consumer repo actually loads** | **~1,545** | the real per-session cost in every project |
| `.claude/rules/*.md` in the context-forge repo itself | +13,536 | all 18 rules load as project instructions |
| all 18 rule sources (`core/rules`) | 24,506 | full corpus |

Two consequences. First, **the +6.9% penalty is a LOWER BOUND**: variant D carried ~534 tokens,
a real consumer carries ~1,545, so the true small-task penalty is likely materially worse.
Second, the `activation: intelligent` flag is **aspirational, not enforced** — every rule file
present in `.claude/rules/` is loaded as a project instruction regardless of its declared mode.
Rule 007 (context-loading) describes trimming that nothing actually performs.

### Mechanism (from the 39 run transcripts, not inferred)

Tool-call medians recovered from `~/.claude/projects/*cfbench*/*.jsonl`:

| variant | Read | Grep+Glob | Bash | total tool calls |
|---|---|---|---|---|
| A (bare) | 6.5 | 0 | 2 | 9.5 |
| B (task knowledge) | 6.0 | 0 | 2 | 9.0 |
| **C (generic placebo)** | **8.0** | 0 | 2 | **11.0** |
| **D (CF core)** | **6.0** | 0 | 2 | **9.0** |

The placebo's harm is now explained precisely: generic advice ("read the existing code and tests
before making changes; follow the conventions you find") makes the agent read **2 more files**.
CF's discovery discipline cancels that exactly — D returns to 6.0 reads / 9.0 calls, matching the
task-specific config B. **The rules work as designed.** They just fix a problem a 9-file repo does
not have: bare A already reads only 6.5, so CF pays ~534 tokens to prevent bloat that isn't there.

**Grep/Glob is 0 in every single run, all variants.** Nobody searched; everyone read files
directly. Rational at 9 files — and the reason the whole discovery-rule family is untestable at
this scale.

**Design finding this exposes:** the always-on set ships the rule that *forbids*
(002 shadow-index: "never read raw source for discovery") but NOT the rule that *enables*
(005 code-search: `rg -c` → `rg -l` → targeted lines), which is `intelligent` mode and therefore
absent from `cf-core`. A rule that bans an action without supplying the cheaper substitute is
strictly a cost. If the XL run shows D failing to convert scale into savings, this is the first
thing to fix — not by deleting 002, but by promoting 005 alongside it.

**Action:** this does NOT say "delete the rules" — it says the always-on bundle is too heavy for
small tasks. That is precisely what rule 007 (context-loading) exists to prevent, and even its
"core only" bugfix path is evidently too much here. Next: (a) measure a multi-file/XL task where
002/003/005 can actually pay off, before generalising (IN FLIGHT: `js-express-errors-xl-014`,
142 files); (b) treat the always-on tax as a budget to defend — trim the bugfix path in 007;
(c) pair 002 with 005 so the ban comes with its substitute.

---

## H2 — Advisor routing beats solo-model on cost-adjusted score

**Claim (vyzual.ai OCR, unverified):** a cheap executor + expensive *advisor* (advisor only on
hard decisions, executor does the work) reaches ~92% of the all-expensive score at ~63% of cost.
BrowseComp figures cited: all-Sonnet 77.8% @ $16.01; Fable-lead + Sonnet-workers 86.8% @ $18.53;
all-Fable 90.8% @ $40.56.

**Why it matters:** rule 003 treats Fable as "hardest work only, outside the tier hierarchy" with
zero cost-adjusted guidance. If the advisor pattern holds, 003 gains a real fourth mode.

**Measurement:** a multi-decision cf-bench task; arms = {solo-cheap, solo-expensive, advisor}.
Metric = success × cost. Provenance is a marketing account → treat as lead only (rule 016).

**Status:** unmeasured, vendor-sourced.

---

## H3 — Loop economics: cost-per-accepted-change is the real metric

**Claim (power.ai OCR series):** for iterative loops (`/evolve`, `/loop`), the metric that
matters is **cost per accepted change**, not tokens or iterations; a loop under ~50% acceptance
stops paying; loops without a hard verify gate fail silently and keep spending.

**Why it matters:** `/evolve` has a hard human gate but no *cost* gate. This would be a new rule
(loop-economics) only after the numbers are real on our own loop.

**Measurement:** instrument `/evolve` runs — log iterations, cost, accept/reject. After ~10 real
runs, compute cost-per-accepted-change. If the ~50% cliff reproduces, draft the rule.

**Status:** unmeasured; instrument first, rule later.

---

## H4 — Repomix `--compress` for pack-context

**Claim (measured locally 2026-07-20):** `rg -l | repomix --stdin --compress` cut a 3-file
TypeScript bundle by **66%** (28,828 → 9,743 bytes) while preserving signatures; lost on tiny
inputs and did nothing on bash (no tree-sitter grammar). pack-context.sh also silently truncates
files >500 lines to 30 lines — arbitrary loss repomix does not suffer.

**Why it matters:** real, reproduced saving — but adds an `npx repomix` dependency to a plugin
that is currently pure bash + rg (violates the ai-tools "zero deps without consent" instinct).

**Measurement:** cf-bench task where the fixture has a >500-line file the agent must reason about;
arms = {pack-context.sh (truncates), repomix --compress}. Metric = success (does truncation cost
correctness?) + bundle tokens. Decide the dependency on evidence, not the 66% headline alone.

**Status:** saving verified; dependency trade-off unmeasured. Leaning: fix the 500-line silent
truncation in pack-context.sh regardless (that's a defect, not a dep question).

---

## H5 — JSON ≈ 2x tokens vs plain text

**Claim (earlystartupdays OCR):** structured JSON costs ~2x the tokens of equivalent plain text.
Already the basis of rule 001's "NEVER raw JSON, use TSV". Independent corroboration, not new.

**Measurement:** trivial — `token-counter.sh` on the same data as JSON vs TSV. Low priority; the
rule already exists and the direction is not in doubt.

**Status:** rule already reflects it; measure only if challenged.

---

## Leads logged but NOT queued (insufficient signal to design a measurement)

- CodeGraph (−58% tool calls claim), Shepherd (reversible agent trace, ~95% KV reuse),
  OpenWiki (auto agent-docs), claude-mem (session capture), mattpocock/skills (interview-first,
  distribution pattern), Impeccable (frontend anti-pattern detectors), PAUL/CHARLIE OS
  (clonable-repo plugin distribution). All are *tools to evaluate*, not claims to measure — they
  belong in a build/evaluate backlog, not this queue. Star counts in the OCR source are mutually
  inconsistent (rule 016: lead, not truth) — verify via API before acting on any.
