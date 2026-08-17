---
name: shadow-lookup
description: Finds which file defines a symbol by reading the shadow manifest (~50 tokens, no LLM call). Use to answer 'where is X defined' before opening any source file.
model: none
---

## What This Does

Runs `bash ${CLAUDE_PLUGIN_ROOT}/core/scripts/tools/shadow-lookup.sh --symbol <name>` against the pre-built lightweight shadow manifest. Returns a TSV-formatted result with symbol name, kind (class/interface/function/type), file path, and repository. Auto-detects IDE for manifest location. Cost: ~50 tokens per lookup (vs ~30k for reading the full manifest).

## When to Use

- "Where is class X defined?"
- "Which file contains the Y interface?"
- Any quick symbol-to-file-path mapping before editing or reviewing
- Tier 0: use before escalating to extract-signatures (Tier 1) or pack-context (Tier 2)

## How to Use

```bash
bash ${CLAUDE_PLUGIN_ROOT}/core/scripts/tools/shadow-lookup.sh --symbol <SymbolName>
```

Optional flags:
- `--repo <repo>` — scope lookup to a specific repository
- `--kind class|interface|function|type` — filter by symbol kind

If the manifest is missing, run refresh-manifest first, then retry.

## Output Format

```
BillingFacade	class	libs/billing/src/lib/billing.facade.ts	my-workspace
BillingService	class	libs/billing/src/lib/billing.service.ts	my-workspace
```

Tab-separated columns: `symbol<TAB>kind<TAB>file<TAB>repo`. Multiple rows if multiple matches.

## Constraints

- NEVER read the full manifest file for a single symbol lookup — use this script
- ALWAYS run refresh-manifest if this returns no results before escalating
- NEVER use LLM inference to guess file paths — always verify via shadow-lookup first
- ALWAYS use TSV output as-is — NEVER reformat to JSON
