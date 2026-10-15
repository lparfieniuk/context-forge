# Small-project workflows

Small repositories no longer require creating a shadow index before source
discovery. Use focused `rg` without an index; use the bounded TSV interface below
when a caller needs structured results. Existing indexed lookup remains the
default. Named JavaScript/TypeScript async exports are now included in generated
manifests.

**The compact instruction profile remains experimental.** Both pilots missed
their acceptance criteria. Its shorter payload is not a demonstrated improvement
in model coding success, and it does not replace the default full profile.

## Discovery without generating an index

From a consumer repository, run the installed plugin's
`core/scripts/tools/shadow-lookup.sh --symbol NAME --text`. The explicit mode:

- searches fewer than 30 non-ignored source files and creates no manifest;
- returns at most 3000 bytes of TSV, with kind `text-match`;
- includes literal occurrences in uses, strings and comments, so inspect the
  returned files before asserting a declaration location;
- rejects kind filters, cross-repository searches and paths incompatible with
  TSV, and preserves actual search errors instead of reporting an empty result.

Plain `rg` is faster and sufficient for an interactive search. The wrapper earns
its additional overhead only when its size bound and TSV contract are useful.
The 30-file boundary is an existing routing heuristic, not a measured universal
break-even point. Reuse an existing index for repeated declaration lookups.

## Generate an experimental compact profile

```sh
npm run emit:agents -- --profile small-project --out dist/AGENTS.small-project.md
```

Review the output before using it in a consumer project's `AGENTS.md`. Preserve
the project's own instructions and facts. This command uses the existing
OpenCode harness profile; the compact payload contains no model identifiers or
hook promises. It does not install a plugin or change global configuration.

Use the compact payload **instead of** the full ContextForge instruction block.
Appending it to the full block does not remove the original context cost. Global
instructions, injected skill catalogs and enabled hooks still apply separately.
Keep only useful verified project facts alongside it, such as check commands,
source locations, data ownership and non-obvious domain invariants.

For repeatable assembly, write those facts in a short `PROJECT-CONTEXT.md` and
pass that existing file explicitly:

```sh
npm run emit:agents -- --profile small-project --project-notes ./PROJECT-CONTEXT.md --out dist/AGENTS.small-project.md
```

The file is read relative to the caller's current directory. Its contents are
included under `Project context`; the input file is unchanged and its absolute
path is not added to the output. Missing or empty notes fail before replacing
the output. The 2,400-byte compact budget covers both instructions and notes.
The emitter assembles supplied context; it does **not** verify that a command,
path or business rule is true. Check those facts against current source or an
explicit owner requirement, and remove obsolete facts when the project changes.

The default export remains `full`. Explicitly selecting `--profile full`
produces the same output as omitting the flag. Unknown profiles, missing values,
missing source files and oversized compact output fail before changing the
destination. Sources are registered in `core/_index.yaml`; the compact profile
has a 2,400-byte budget including the generated header.

## What changes

The compact workflow asks the agent to apply the requested change, establish
contracts from relevant code and tests, preserve unrelated work, edit the real
current content and verify the saved result. Small changes do not require an
index or delegation. This leaves more judgment to the agent than the full
doctrine; projects needing additional coordination should load a relevant
workflow explicitly.

Candidate v2 is 1,070 UTF-8 bytes. The previous full OpenCode export is 29,109
bytes; the **different**, condensed `cf-full` benchmark config is 7,914 bytes.
The reductions are 96.3% and 86.5%, respectively. These are byte measurements,
not tokenizer counts or measured savings in successful engineering work.

## Research behind the experiment

- [Agent Skills](https://agentskills.io/specification) separates discovery
  metadata from instructions and resources. Load relevant detail when needed;
  installed metadata still occupies context, and `allowed-tools` support is
  experimental.
- [Anthropic's agent guidance](https://www.anthropic.com/engineering/building-effective-agents)
  favors simple, composable patterns before added orchestration. Its
  [skill-creator source](https://github.com/anthropics/skills/blob/main/skills/skill-creator/SKILL.md)
  compares skills with baselines and iterates against evaluations. Here,
  correctness is determined by `cf-bench` tests rather than an LLM judge.
- [OpenAI's skill-creator](https://github.com/openai/skills/blob/main/skills/.system/skill-creator/SKILL.md)
  and the inspected installed copy favor concise, non-obvious guidance and
  progressive disclosure. Generic repeated rules are a cost to justify.
- Installed [Matt Pocock skills](https://github.com/mattpocock/skills) 1.2.3
  favor small interfaces and primary-source research. Installed
  [Superpowers](https://github.com/obra/superpowers) 6.4.1 supplies planning and
  verification workflows; using every handoff for every small task adds work.
- The inspected Ponytail 5.1.0 skill favors the smallest complete change while
  retaining checks and boundary validation. That scope discipline is useful;
  its voice and entire procedure do not need to become global instructions.

The local `ai-knowledge` MCP was read before implementation: 97 non-archived
entries assigned to ContextForge, 46 to `cf-bench` (overlapping sets), and five detailed source
contexts. Imported summaries and popularity claims were treated as leads;
primary sources and installed skill bodies supplied the design evidence.
Assignment to a project was not treated as proof of adoption.

## Measurement status

On 2026-10-09/10, a first pilot used the existing `cf-bench` runner, OpenCode
1.18.21, local `cfaios-qwen3-14b-32k`, a verified 32,768 context setting and
unchanged fixture checks. Three repeats of each arm were interleaved on each
of three tasks. The frozen first candidate was 1,664 bytes.

- `js-express-errors-010`: generic 0/3, full 0/3, compact v1 0/3.
- `js-brown-cents-005`: generic 1/3, full 0/3, compact v1 0/3.
- `ts-fix-discount-001`: generic 3/3, full 3/3, compact v1 2/3.

This pilot **did not meet acceptance**. On the Express task compact v1 was also
slower: median 393.9 seconds versus 232.9 for full and 49.1 for generic. Those
were failed attempts, so shorter durations do not imply better productivity.
N=3 is directional and does not establish equivalence or a general ranking.

For that fixed nine-attempt workload per arm, total measured runtime divided by
the number of passes was 5.48 minutes for generic, 10.60 for full and 18.86 for
compact v1. This includes failed attempts; it is a descriptive workload ratio,
not a prediction of repeated retries or a billing figure.

Captured traces showed failed edits containing display line numbers and one
compact run that described a correct fix but did not apply it. Candidate v2
addresses those general execution failures and removes other generic advice.
Because the TypeScript trace was inspected during revision, that task is no
longer an unseen holdout. Fresh tasks and a frozen candidate are required for
confirmation.

All three original fixture checks fail before their oracle solutions and pass
afterwards. Fixtures have 7, 4 and 2 JavaScript/TypeScript files, excluding
dependencies; results do not establish benefits for a whole 100-file app.
The first unavailable-host preflight did not invoke the model and was retained
separately, not scored as a correctness failure.

Acceptance requires no observed success-count loss against the generic control,
success at least matching full, and at least 15% lower median duration or output
tokens against full on two useful tasks, followed by N≥10 confirmation per
arm/task. Report intervals and failures alongside efficiency. A nonsignificant
test is not evidence of equivalence, and zero local API billing is not zero
compute cost. Until those checks pass, the profile remains experimental and
the full export remains the default.

## Project-context experiment

An additional Qwen 3.6 35B calibration on Express produced generic 1/1, full 0/1
and compact v2 0/1. Both losing profiles saved changes and passed the visible
test, but missed a project-specific error-handling contract checked separately.
This is N=1 calibration, not a statistically reliable ranking or evidence that
all instructions are harmful.

The second experiment used the benchmark's existing project notes, supplied
equally to all arms: B is notes only, K is the existing full CF payload plus
those notes, and P is compact v2 plus those notes via `--project-notes`.
The notes are intended task inputs already provided by `cf-bench`; no hidden
assertions or oracle implementations are copied into them. Candidate and input
hashes were frozen before the rotating N=3 pilot on Express, billing and RxJS.

The completed results were B 4/9, K 7/8 and P 6/9. The final K/RxJS run timed out
after macOS clamshell sleep; another B/RxJS duration includes sleep and is
excluded from timing conclusions. P/billing also exposed a tool permission
problem with equivalent `/var` and `/private/var` paths. Preserve that recorded
failure and correct the instrument consistently before another model series.

This incomplete small sample cannot establish a reliable general ranking.
The compact candidate missed the no-loss criterion regardless of the unfinished
K trial, so it was not promoted or sent to an expensive N≥10 confirmation.
No further prompt tuning was performed against these inspected tasks. The
earlier failures remain separate results; missing trials are not imputed.

## Measured discovery result

A separate deterministic component benchmark reused three public `cf-bench`
fixtures on 2026-10-10. It performed 30 rotating repetitions per mode and query,
using fresh copies, unchanged source targets and no model or hidden checks.
The query targets were `createRefundHandler`, `formatAmount` and `autoSave`.

- The original generator missed the named async Express export in 30/30 runs.
  The corrected generator found it in 30/30; the other two indexed queries
  remained successful. Repetition does not turn these into 30 independent cases.
- Bounded text lookup located the expected source file in all 90 repetitions,
  with zero manifest creation. Median durations were 30.15, 30.68 and 31.17 ms,
  versus 75.27, 75.12 and 75.73 ms for generation plus corrected indexed lookup:
  about 59–60% less command time on these small fixtures.
- An already-generated index took 10.31–10.59 ms; plain `rg` took 6.54–6.75 ms.
  Text matches have weaker semantics than indexed declarations. They are not
  substitutes for a parser or proof of a unique definition.

Fixture copying and Git initialization were outside timing; warm-index setup
was also outside its timed lookup. The first preflight exposed the async export
bug. A second series overlapped tests and archive I/O; its timings were excluded.
The reported third series ran without those competing jobs. These are component
latencies, not end-to-end model productivity or financial savings.

The full experiment bundle lives in the local worklog report
`~/worklogs/reports/cf-small-2026-10-09/`, with frozen inputs, runner versions,
captures, schedules, TSV results, exclusions and the discovery reproduction
script. No paid remote model, global profile replacement or publication was used.
