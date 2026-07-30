---
name: pack-context
description: >
  Bundles multiple source files matching a regex pattern into a compact XML context block for tasks touching 3+ interrelated files. Max 15 files, ~10-30k tokens. Needs Sonnet to judge which files to include.
  <example>
  Context: Refactoring BillingFacade across multiple files.
  user: "Bundle all billing files for the cancelSubscription refactor"
  assistant: "Running pack-context with pattern 'billing|subscription' — returns XML bundle of up to 15 matching files."
  </example>
model: sonnet
---

## What This Does

Runs `bash ${CLAUDE_PLUGIN_ROOT}/core/scripts/tools/pack-context.sh --pattern <regex> --search-path <dir>` and returns a compact XML bundle of matching files (Minimum Viable Context, max 15 files). Uses keyword-filtered selection so only files matching the regex are included. Token cost: ~10–30k depending on file count and size.

## When to Use

- Task touches 3+ interrelated files and full method bodies are needed
- Planning a cross-file refactor and need full context, not just signatures
- extract-signatures (Tier 1) is insufficient — need complete method bodies

## How to Use

Step 1: Identify the pattern and search path.

```bash
bash ${CLAUDE_PLUGIN_ROOT}/core/scripts/tools/pack-context.sh \
  --pattern "billing|subscription" \
  --search-path libs/billing/src/
```

Optional flags:
- `--max-files <n>` — override default 15-file cap (max 15)
- `--max-lines <n>` — per-file line budget (default 400); files over it show a head+tail window (first 75% + last 25% of the budget) with the elided count reported, not a fixed 30-line stub
- `--exclude <pattern>` — exclude files matching pattern (e.g. `*.spec.ts`)

Step 2: Consume the XML output — parse `<f p="...">` blocks for file path and content.

## Output Format

```xml
<f p="libs/billing/src/lib/billing.facade.ts">
export class BillingFacade {
  cancelSubscription(id: string): Observable<void> {
    return this.store.dispatch(cancelSubscription({ id }));
  }
}
</f>
<f p="libs/billing/src/lib/billing.effects.ts">
// ... related effect code ...
</f>
```

Each file is wrapped in `<f p="<relative-path>">...</f>`. Files are ordered by relevance to the pattern.

## Constraints

- NEVER exceed 15 files — return the most relevant subset if more match
- NEVER use without a focused regex pattern — broad patterns cause context bloat
- ALWAYS prefer extract-signatures (Tier 1) when full bodies are not needed
- NEVER call this for tasks touching fewer than 3 files
