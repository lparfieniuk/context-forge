# Writing checkable standards — ContextForge

Document owner: Łukasz Parfieniuk. Source review: 2026-10-08.

This document records why I apply rules and practices turning them into
unambiguous requirements. The cards below formalize existing practice; they do not
replace `core/rules/`, the index, or project instructions. New ideas stay `draft`
until the owner decides and they land in the right source.

## How to write the next standard

1. Describe the concrete problem and the cost of not acting. Also record the cost of the rule itself.
2. Set the scope: the object, when it is checked, and who is responsible.
3. Write one requirement. Split a sentence that carries several independent conditions.
4. Add the check outcome, a compliant example, a non-compliant example, and an edge case.
5. Name the source, the check, and the evidence it ran. Mark any missing one explicitly.
6. Review the card when its source changes. The history explains the decision and its reason.

In this document `MUST` means an obligation, `SHOULD` a recommendation that allows a
justified deviation, and `MAY` an option. The meanings come from
[RFC 2119](https://www.rfc-editor.org/info/rfc2119/) and
[RFC 8174](https://www.rfc-editor.org/rfc/rfc8174.html).
This is a writing vocabulary, not an enforcement mechanism.

## Card template

```markdown
### <ID> — <short name>

- Version / status: 1 / draft | formalization of an existing rule | accepted | retired.
- Owner / review date: <person> / <YYYY-MM-DD>.
- Problem and rationale: <the concrete failure mode this prevents>.
- Scope: <which objects, when, for which tool or process>.
- Requirement: <object> MUST/SHOULD/MAY <one observable condition>.
- Decision source: <link to a rule, an ADR, or the owner's decision>.
- Check: <automatic | manual | none; file and test name, or procedure>.
- Pass criterion: <unambiguous check outcome>.
- Evidence: <commit, command, actual exit code, report; or not run>.
- Compliant example: <minimal case that meets the condition>.
- Non-compliant example: <minimal case that breaks the condition>.
- Edge case: <scope boundary or a case that cannot be assessed>.
- Exception: <who approves, reason, scope, expiry; or none>.
- Cost / limitation: <what I lose, or what the check does not prove>.
- History: <date — change, reason; when reversing a decision, point to the earlier one>.
```

Check and evidence are recorded separately: a test that exists has not necessarily
been run. A check outcome is `pass`, `fail`, or `not-assessed`. An approved exception
is recorded on its own; it never turns a test outcome into `pass`.

## Cards from existing practice

### CF-STD-001 — Register a rule's source

- Version / status: 1 / formalization of an existing rule.
- Owner / review: Łukasz Parfieniuk / 2026-10-08.
- Problem: a file outside the registry can be skipped during distribution.
- Scope: a new ContextForge runtime rule, before its source file is created.
- Requirement: a new rule MUST have an entry in `core/_index.yaml` before its
  source file is created.
- Source: global ContextForge development rule; [index](../core/_index.yaml).
- Check: manual for the order of changes; as a helper,
  [validate-index.sh](../core/scripts/tools/validate-index.sh) checks existing
  file references. The final index alone does not prove creation order.
- Criterion: change history shows registration before the source was created.
- Evidence: checker source reviewed; history of a specific new rule not assessed.
- Compliant example: index entry first, then the file at the listed path.
- Non-compliant example: create the rule, then add it to the index.
- Edge case: a document in `docs/` does not become a runtime rule by using `MUST`.
- Exception: none in this card; the owner decides process changes.
- Cost / limitation: an extra step; the validator checks state, not history.
- History: 2026-10-08 — recorded the existing rule and the limit of the automatic check.

### CF-STD-002 — Cost of always-loaded rules

- Version / status: 1 / formalization of an existing rule.
- Owner / review: Łukasz Parfieniuk / 2026-10-08.
- Problem: a rule needed only in some tasks weighs on every session.
- Scope: indexed rules for the Claude Code emitter, during distribution validation.
- Requirement: a rule with a non-empty `installed_claude` MUST have `activation: always`.
- Source: activation contract in [CLAUDE.md](../CLAUDE.md).
- Check: automatic in
  [rule-activation.test.ts](../scripts/rule-activation.test.ts), test
  ``only `always` rules occupy .claude/rules/ (always-on cost)``.
- Criterion: the test finds zero rules with a Claude install and another activation.
- Evidence: check read in source; the test was not run while writing the card.
- Compliant example: an on-demand rule has `installed_claude: null`.
- Non-compliant example: an on-demand rule has a path in `.claude/rules/`.
- Edge case: an orphaned installed file needs a separate directory check; the
  index test alone does not catch it. Another harness needs a check of its own emitter.
- Exception: none; widening the load scope requires changing the source decision.
- Cost / limitation: an on-demand rule may never be read by the agent.
- History: 2026-10-08 — separated the index check from file and behavior checks.

### CF-STD-003 — Scope of a claim that a rule is enforced

- Version / status: 1 / draft; proposal to sharpen how this is reported.
- Owner / review: Łukasz Parfieniuk / 2026-10-08.
- Problem: a correct instruction install can be mistaken for compliance with it.
- Scope: a report claiming the agent follows a specific rule.
- Requirement: the report MUST cite evidence of observed agent behavior
  concerning that rule to support the claim that it is followed.
- Decision source: this card's proposal; the reference point is
  [check-parity.sh](../core/scripts/tools/check-parity.sh), which inspects the install
  and always returns 0 as an informational result.
- Check: manual review of the claim, the observation, and its scope; no gate.
- Criterion: the evidence covers the assessed behavior, its conditions, and the limit of the conclusion.
- Evidence: no behavior experiment for this card; `not-assessed`.
- Compliant example: "In scenario X the hook blocked operation Y; event record Z".
- Non-compliant example: "parity exited 0, so the agent follows the rules".
- Edge case: a measurement without the needed observation stays not-assessed, not passed.
- Exception: none; the conclusion can be narrowed to install correctness.
- Cost / limitation: collecting observations costs; a single scenario does not
  prove effectiveness across all tasks.
- History: 2026-10-08 — proposal, no change to active rules or hooks.

## Exercise: from slogan to requirement

Take one rule, e.g. "use the cheapest correct executor". Write card
`CF-STD-004` with status `draft`. First define what "correct" means, how you
compare cost, and what you do when one quantity is unknown. Prepare a case
where the cheaper executor ends up costing more through repeated work.

Ask a reader to judge three cases from the card alone. If you have to fill in a
definition for them, fix the requirement. An expert interview practices settling
that definition; a test only checks the agreed text.

For learning purposes, local levels can be used:
- **baseline:** one requirement, scope, source, and pass criterion;
- **enhanced:** plus examples, an edge case, and defined exception handling;
- **evidenced:** plus real evidence that the check ran for this version.

This is a proposal for rating card completeness, not a project compliance
certificate. A `draft` card is rated as an exercise; filling in the fields does not approve it for runtime.

Measurement examples: [cf-bench register](../../ai-tools/cf-bench/docs/standards-authoring.md).
The link between local repositories assumes the `Projects` directory layout; once
the repositories are published separately, their READMEs remain the entry points.

## Document history

- 2026-10-08 — first version: shared template, two examples of existing rules,
  one proposal, and an exercise. No changes to runtime sources.
- 2026-10-15 — translated to English (project content is English-only).
