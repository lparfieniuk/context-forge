---
name: shadow-lookup
description: Use for "where is X defined", "find the symbol", or "locate this function" with an existing manifest; use explicit --text for literal occurrences in a repository with fewer than 30 source files and no index. Do NOT use text matches as proof of a declaration, or for broad search in larger repositories — use focused rg.
model: inherit
---

## What This Does

Runs `bash ${CLAUDE_PLUGIN_ROOT}/core/scripts/tools/shadow-lookup.sh --symbol <name>` against the pre-built lightweight shadow manifest. Returns TSV with symbol, kind, file and repository. Without a manifest in a small repository, explicit `--text` searches literal occurrences without creating an index; these rows use kind `text-match`, not a declaration kind.

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
- `--text` — literal source matches in the current repository, only below 30 non-ignored source files; cannot combine with `--kind` or a different `--repo`

If the manifest is missing, use `--text` for a small repository. For larger repositories, run refresh-manifest for its supported TypeScript, JavaScript, Python or PHP declarations. The regex index is not exhaustive: use focused source search for unsupported syntax. Text lookup covers `.ts`, `.tsx`, `.js`, `.jsx`, `.mjs`, `.cjs`, `.py` and `.php`; respects ignore rules; limits output to 3000 bytes; and fails visibly on search errors, no matches or names that cannot fit TSV.

## Output Format

```
BillingFacade	class	libs/billing/src/lib/billing.facade.ts	my-workspace
BillingService	class	libs/billing/src/lib/billing.service.ts	my-workspace
```

Tab-separated columns: `symbol<TAB>kind<TAB>file<TAB>repo`. Multiple rows if multiple matches.
In `--text` mode a row such as `alpha<TAB>text-match<TAB>src/a.ts<TAB>my-workspace` can refer to a declaration, use, comment or string. Inspect the file before asserting where a symbol is defined. Mode diagnostics go to stderr, keeping stdout machine-readable.

## Constraints

- NEVER read the full manifest file for a single symbol lookup — use this script
- NEVER create an index solely to search fewer than 30 source files unless explicitly requested
- NEVER treat `text-match` as a declaration or infer that no matches proves a symbol does not exist
- NEVER use LLM inference to guess file paths — verify the returned files
- ALWAYS use TSV output as-is — NEVER reformat to JSON
