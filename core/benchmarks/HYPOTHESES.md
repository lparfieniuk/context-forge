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

**Status: MEASURED 2026-07-22, RE-MEASURED CLEANLY 2026-09-06 — REFUTED on this task class, twice.**
(The definitive run is the second 2026-09-06 block below: all five arms, one invocation, one CLI
version. E vs A = **+15.9%**, p = 0.00018, at equal success. Read that block first; everything
above it is the history that produced it.)

**Original 2026-07-22 verdict:** Run: cf-bench
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

### Re-measured 2026-09-06 — the payload was under-tested 3.1x, and the run split across a CLI update

Run: cf-bench `js-express-errors-010`, Sonnet, N=10 per arm, $4.93 across
`results/bench-20260905-213559.tsv` (A/B/C, CLI **2.1.261**) +
`results/bench-20260906-de.tsv` (D/E, CLI **2.1.263**). The first file hit the circuit breaker on
two consecutive `api_error` rows before D and E ran; the missing arms were run separately rather
than re-buying A/B/C — and Claude Code auto-updated in between.

**That version drift is the headline caveat, not a footnote.** This file's own rule is: do not pool
across CLI versions unless the point is measuring harness variance. So every CROSS-FILE comparison
below is suggestive only, and the two within-file comparisons are the only clean measurements.

New arm **E (`configs/cf-full`, ~1945 tokens)** is the payload a consumer repo actually loads —
the global `CLAUDE.md` minus the personal-infrastructure section. Variant D (`cf-core`, ~619
tokens) is what the 2026-07-22 run tested, i.e. **3.1x less than the real thing**. Both figures are
characters/4 on the config file, the same estimator used for every other arm.

#### Clean (single CLI version, single file)

| pair | CLI | metric | delta | p (Mann-Whitney) |
|---|---|---|---|---|
| **C vs A** (placebo vs bare) | 2.1.261 | **cost / turns** | **+9.6% / +10.0%** | **0.001 / 0.010** |
| E vs D (1945 tok vs 619 tok) | 2.1.263 | cost | +1.9% | 0.186 (ns) |

#### Cross-version — suggestive, NOT measured

| pair | metric | delta | p |
|---|---|---|---|
| E vs A | cost | +18.6% | 0.000 |
| E vs C | cost | +8.2% | 0.001 |
| D vs A | cost | +16.4% | 0.005 |
| D vs C | cost | +6.2% | 0.045 |
| E vs C / D vs C | turns | −9.1% / −9.1% | 0.249 / 0.055 (ns) |

Success: A, B and E each 10/10; D **8/10**; C 7/7 of the runs that executed (two more never ran and
are excluded, per this repo's convention that an empty `success` is a non-run, not a failure).

What the clean rows support:

1. **Payload SIZE is not the cost driver.** E vs D is +1.9%, ns, on one CLI version, even though E's
   config is ~1326 tokens larger and drives `cache_creation` up by 2640 tokens (median 16007 vs
   13367) — twice the config delta, and still no significant cost effect. The July worry that
   correcting the 3.1x under-test would reveal a far worse number is **refuted**.
2. **Having any CLAUDE.md at all costs ~10%.** C vs A is +9.6% cost and +10.0% turns on one version,
   replicating July's +8.2%/+14.3%. Whatever CF costs, most of it is not CF-specific.

What the clean rows do NOT support, and what the July run claimed: that the rules buy a turn saving.
Every CF-vs-baseline comparison here crosses the CLI boundary, so **H1 is neither confirmed nor
re-refuted by this run** — the July REFUTED verdict stands on the July data, not on this one.

Flag carried forward: **D scored 8/10** where A, B and E scored 10/10 — runs #4 and #7 finished
(`terminal_reason=completed`) in 8 and 9 turns and failed the hidden assertion. Fisher exact vs A
gives **p = 0.474**. Needs a re-test at higher N before it means anything.

**Next measurement, and it is now required rather than optional:** re-run all five arms in ONE
invocation on ONE CLI version. Cost ~$6 per task class. Until then the only defensible claims from
2026-09-06 are the two clean rows above.

What stays unmeasured is unchanged and is the larger open question — skills, hooks and the
shadow-index layer live in user scope, which `--setting-sources project` excludes by design, so no
cf-bench variant reaches them.

---

### Re-measured 2026-09-06 (second run) — clean, one CLI version, all five arms

Run: cf-bench `js-express-errors-010`, Sonnet, **N=10 per arm, all 50 runs in ONE
`run-bench.sh` invocation**, CLI **2.1.263** in every row (column 16 has exactly one distinct
value), `DISABLE_AUTOUPDATER=1` exported for the whole run, $5.22, 0 invalid rows.
File: `results/bench-20260906-081546.tsv`. This is the run the previous block called required.

| variant | config | tokens | succ | med cost | Δ vs A | p (Mann-Whitney) |
|---|---|---|---|---|---|---|
| A | none | 0 | 10/10 | 0.0979 | — | — |
| B | task knowledge | — | 10/10 | 0.0939 | **−4.1%** | **0.017** |
| C | generic placebo | ~46 | 10/10 | 0.1066 | **+8.9%** | **0.0013** |
| D | `cf-core` | ~619 | **6/10** | 0.1068 | +9.1% | 0.0046 |
| E | `cf-full` | ~1945 | 10/10 | 0.1134 | **+15.9%** | **0.00018** |

E vs C: **+6.4%, p = 0.0028**. E vs D: +6.2%, p = 0.038 (but see the artefact note below).

**1. H1 is REFUTED again, now on the real payload and with no version drift.** The payload a
consumer repo actually loads costs **+15.9%** against no config at all, at identical success
(10/10 vs 10/10) and identical turns (10 vs 10). The July verdict was reached on a 3.1x
under-tested config; correcting that made the penalty larger, not smaller.

**2. The penalty splits cleanly into two parts.** C vs A is +8.9% — the price of *any* `CLAUDE.md`
existing, replicated a third time now (July +8.2%, 2026-09-05 +9.6%, today +8.9%). E vs C is
+6.4% — the price of ContextForge's *content* on top of that. Roughly 56% of CF's cost is not
CF-specific; the remaining 44% is.

**3. Encoded task knowledge is the only arm that is cheaper than bare.** B −4.1%, p = 0.017 — a
third replication (July −3.6%). The generalisation this supports is not "configs are expensive"
but: *a config that carries a task fact pays for itself; a config that carries process advice does
not.* That is cf-bench's own thesis turned on its author.

**4. Payload size is still not the cost driver — the apparent E vs D delta is an artefact.**
Pooling D and E across both 2.1.263 files (N=20 each, permitted: same version, same task, same
config) gives E vs D +3.5%, p = 0.015 — which looks like a size effect until D's failures are
separated out. D's 6 failing runs are *cheap* (median $0.1025, 8 turns) and drag its median down;
D's 14 successful runs cost $0.1130 against E's $0.1134, a delta of **+0.4%, p = 0.278**. A 1326-token
config difference buys no measurable cost difference. The July worry stays refuted.

**5. The `D 8/10` flag reproduced and got worse: 6/10.** Pooled across both 2.1.263 runs D is
**14/20** where A is 10/10 on the same version; Fisher exact p = 0.074 — directional, still not
significant at N=20. All six failures ended `terminal_reason=completed` in 8–10 turns: the agent
believed it was finished and failed the hidden assertion. Cheap, fast, confidently wrong — the same
shape `js-config-lies-008` produces with a *lying* config, here produced by a config that states
nothing about the task at all.

**The asymmetry that matters: D fails, E does not.** `cf-core` is not a subset of `cf-full` — it is
a hand-written paraphrase carrying rules 001/002/003/004/010, while `cf-full` carries
019/001/003/011/004/005/010/015 plus worklogs. Two differences are candidates:
`cf-core` ships **002 ("do not read whole files for discovery; use a few lines around a match")**
without **005** (the progressive-disclosure chain that supplies the substitute) and without **015 /
019** (verify against local source; never assent before verification). This is the exact defect the
July run already named — *"a rule that bans an action without supplying the cheaper substitute is
strictly a cost"* — except the price is now visible as **failed runs, not just tokens**. Consistent
with it: D's median `cache_read` is 196,747 against 135k–148k in every other arm, i.e. D re-reads
far more while reading fewer whole files.

**This is a hypothesis, not a measurement.** It is testable for ~$1.1: a variant F = `cf-core`
plus the 005 progressive-disclosure chain and the 015 verification line, N=10, same invocation.
If F returns to 10/10 the mechanism is confirmed and the always-on set has a concrete defect to fix.
Until F runs, the honest statement is: *the 619-token core paraphrase lost 6 of 20 runs that bare
baseline won, and we do not know which line did it.*

**What this does NOT say.** It does not say delete the rules. It says: on a single-file bugfix in a
9-file repo, the always-on bundle is a pure 16% tax, and the cheaper half of it is not even
ContextForge's fault. Nothing here generalises to multi-file work — `js-express-errors-xl-014`
(142 files) is where 002/003/005 could pay off, and it has not been run with variant E.

---

### Variant F, 2026-09-08 — the July fix, measured. It does not pay.

The block above proposed a $1.1 test: variant **F = `configs/cf-core-plus`** — `cf-core`
byte-for-byte plus the two things it lacked, rule 005's progressive-disclosure chain (the
substitute that rule 002's ban assumes exists) and the 015/019 verify-before-concluding mandate.
~908 tokens, sitting between D (~619) and E (~1945). Run: `results/bench-20260908-144052.tsv`,
N=10, CLI **2.1.263** — the same version as every arm below, so all of these pool legitimately.
$1.24. This is exactly the "pair 002 with 005" action item the July analysis wrote down.

| arm | config | tokens | n | succ | med cost | med turns | med `cache_read` |
|---|---|---|---|---|---|---|---|
| A | none | 0 | 10 | 10/10 | 0.0979 | 10 | 135,587 |
| B | task knowledge | — | 10 | 10/10 | 0.0939 | 10 | 136,273 |
| C | placebo | ~46 | 10 | 10/10 | 0.1066 | 11 | 137,423 |
| D | `cf-core` | ~619 | 20 | 14/20 | 0.1096 | 10 | 196,747 |
| E | `cf-full` | ~1945 | 20 | 20/20 | 0.1134 | 10 | 148,167 |
| **F** | **`cf-core-plus`** | **~908** | **10** | **9/10** | **0.1202** | **11** | **216,559** |

**1. The mechanism hypothesis is neither confirmed nor refuted — the test was underpowered and
that was foreseeable.** F 9/10 against D 14/20 is Fisher p = 0.37. Against A's 10/10, p = 1.0.
`tools/power-analysis.py` puts the power of a 70%-vs-100% effect at N=10 at **0.15**; settling this
needs roughly N=50 per arm, about $11. The direction is right (90% vs 70%) and that is all it is.

**2. What the run DOES settle is that the fix costs rather than saves.** F is the most expensive
arm measured: **+22.8% against bare** (p < 0.001), +9.6% against D (p = 0.048), and statistically
indistinguishable from E (+6.0%, p = 0.692). Excluding F's single failure changes nothing — its nine
successful runs have a median of $0.1181, still the highest. So **F is dominated by E**: no better
on success, not cheaper, and E is the config that actually ships.

**3. The mechanism is visible and it is the opposite of the intent.** F's median `cache_read` is
**216,559** — the highest of any arm, 60% above bare A's 135,587 — and its median turn count rises
to 11 while every arm except the placebo sits at 10. The rules added to make reading cheaper made
the agent read *more*: the progressive-disclosure chain replaces one whole-file read with a count,
a file list and several targeted reads, and the verification mandate sends it back to check. On a
9-file repo that is strictly more work. The July prescription — *"do not delete 002, promote 005
alongside it"* — is now measured, and on this task class it makes the bundle worse on cost while
leaving the success question open.

**4. Payload size is not the cost driver, third replication.** F carries ~908 tokens and E ~1945,
and their costs are indistinguishable (p = 0.692). Together with D-successes vs E (+0.4%, p = 0.278)
this is now measured three ways on one CLI version.

**Standing recommendation, unchanged in direction and firmer in evidence:** the always-on bundle is
a net cost on a single-file bugfix in a small repo, and no arrangement of it tested so far turns that
around. The open question is not *which rules* but *whether an always-on bundle is the right shape
at all* for this task class. What would change the verdict: an arm that wins on a task where the
discovery machinery has something to discover — `js-express-errors-xl-014` (142 files) with variants
C/E/F, which has never been run.

**Deliberately not done:** cutting rules on the strength of this. D is a hand-written paraphrase, not
the shipped artefact; E is the shipped artefact and it scores 20/20. Deleting a rule because a
paraphrase of it lost runs would be acting on the wrong object.



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

## H6 — Most of the plugin's surface is never used outside its own repo

**Claim:** the skills and Tier 1 scripts that carry ContextForge's headline value — the shadow
index, signature extraction, context packing — earn their always-on listing cost in real project
work. This is the discovery half of H1, which measured the *rules*.

**Measurement (Tier 0, `core/scripts/tools/skill-usage.sh`, run 2026-09-05):** count Skill-tool
invocations, slash invocations, and sub-agent spawns per skill across every transcript in
`~/.claude/projects`, then repeat with `context-forge` transcripts excluded.

**Status: MEASURED 2026-09-05 — REFUTED.**

| Scope | Result |
|---|---|
| Skills invoked at all (30-day window) | 7 of 23 |
| Skills invoked outside the `context-forge` repo | 5 — `diary` 37, `session-learnings` 34, `end-session` 18, `pre-review` 11, `record-failure` 1 |
| Discovery skills used outside the repo | 0 |
| Tier 1 script executions outside the repo | 0 of 21 distinct scripts executed |
| `cf-scribe` spawns, anywhere | 0 |

Every surviving user is a session-workflow skill. The discovery layer — the plugin's stated first
pillar — was exercised only while developing the plugin itself. Two candidate causes, not yet
separated: the descriptions were summaries rather than routing predicates (rewritten 2026-09-05,
so the next window is a genuine re-test), or the native Read/Grep/Glob tools are simply reached
for first and no description can outbid them. **Next measurement:** re-run `skill-usage.sh` after
2026-10-05 on a window that contains only post-rewrite sessions; if discovery use is still zero,
the cause is not discoverability and the layer should be cut, not re-described.

**Instrument caveat:** transcripts are deleted after `cleanupPeriodDays` (default 30, verified in
the 2.1.261 binary), so every number above is a rolling month, never project history. The
`PostToolUse`/`Skill` hook added the same day writes `~/worklogs/logs/skill-usage.tsv` so later
windows are not bounded by that.

---

## Leads logged but NOT queued (insufficient signal to design a measurement)

- CodeGraph (−58% tool calls claim), Shepherd (reversible agent trace, ~95% KV reuse),
  OpenWiki (auto agent-docs), claude-mem (session capture), mattpocock/skills (interview-first,
  distribution pattern), Impeccable (frontend anti-pattern detectors), PAUL/CHARLIE OS
  (clonable-repo plugin distribution). All are *tools to evaluate*, not claims to measure — they
  belong in a build/evaluate backlog, not this queue. Star counts in the OCR source are mutually
  inconsistent (rule 016: lead, not truth) — verify via API before acting on any.
