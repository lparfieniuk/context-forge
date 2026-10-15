# Shadow Index Protocol

## SYSTEM CONSTRAINTS

ALWAYS use an existing manifest first for symbol discovery.
NEVER generate a missing manifest for a repository with fewer than 30 source files unless the user explicitly requests indexing. Use focused `rg`; use `shadow-lookup.sh --symbol X --text` when bounded TSV output is needed. Inspect returned files: `text-match` rows are occurrences, NOT declarations.
ALWAYS follow the indexed protocol below for repositories with 30 or more source files. The text lookup enforces the boundary using non-ignored `.ts`, `.tsx`, `.js`, `.jsx`, `.mjs`, `.cjs`, `.py` and `.php` files.
NEVER escalate to pack-context solely because a file-count threshold was crossed; use it when related method bodies are actually needed together.
ALWAYS resolve `<IDE_DIR>` (`.claude` or `.cursor`) before manifest lookup.
ALWAYS generate a missing manifest before indexed lookup; NEVER require an index for the small-repository text path.
NEVER hardcode `.cursor/shadow/` — ALWAYS use IDE-resolved `<IDE_DIR>`.
EXEMPTION — ONE self-contained artifact under ~30k tokens, read once to answer one question (a downloaded transcript, a single log, one PDF): read it directly. NEVER build a manifest, bundle, or sub-agent pipeline around it — the scaffolding costs more than the artifact. The manifest protocol governs REPEATED discovery across a codebase, not a single read.

## IDE Auto-Detection

Determine `<IDE_DIR>` before any manifest lookup:

| IDE | `<IDE_DIR>` | Detection |
|-----|-------------|-----------|
| Claude Code | `.claude` | `.claude/` exists at project root |
| Cursor | `.cursor` | `.cursor/` exists at project root |
| Both present | dual-write | Read whichever is populated |
| Neither | `.cursor` | Legacy fallback |

Manifest path: `<IDE_DIR>/shadow/<repo>/_manifest.lightweight.yaml`

## Three-Step Lookup Protocol (mandatory order)

> Note: "Step" numbering here refers to lookup escalation order, not the Tier routing cost hierarchy in rule 003.

| Step | Tool | Trigger | Token Cost |
|------|------|---------|-----------|
| 1 — Lightweight Manifest | `<IDE_DIR>/shadow/<repo>/_manifest.lightweight.yaml` | "Where is class X?" | ~50 |
| 2 — extract-signatures skill | `<IDE_DIR>/skills/extract-signatures/SKILL.md` | "How is X structured?" | ~500–2k |
| 3 — pack-context skill | `<IDE_DIR>/skills/pack-context/SKILL.md` | Task touches 3+ interrelated files | ~10–30k |

## Step-by-Step Protocol

Step 1 — Detect IDE: check `.claude/` then `.cursor/` at project root.
Step 2 — Check manifest: `ls <IDE_DIR>/shadow/<repo>/_manifest.lightweight.yaml`
  - If MISSING and fewer than 30 source files → use focused `rg` or the bounded `shadow-lookup.sh --symbol X --text` interface, then inspect matches. A failed search is not proof that a declaration is absent; check its diagnostic before deciding the next step.
  - If MISSING and 30 or more source files → run `/refresh-manifest` for its supported TypeScript, JavaScript, Python or PHP declarations. Use focused source search for unsupported syntax or languages; the regex-based index is not exhaustive.
  - If present → read manifest. Find target symbol path.
Step 3 — extract-signatures: run against the file found in Step 2.
  - Sufficient for interface understanding and writing new code.
Step 4 — pack-context: only when task touches 3+ interrelated files with full method bodies required.

## Raw Source — When to Use

- Applying a diff (editing actual file).
- Verifying runtime behavior not visible in signatures.
- Following text matches in a small repository without a manifest.

## Few-shot example

**Input:** "Add cancelSubscription() to BillingFacade."
**Reasoning:** An existing manifest resolves the declaration; signatures establish the API. Bundle related bodies only when the change needs them together. In a small repository without a manifest, `--text` instead supplies candidate files to inspect.
**Output:**
```bash
# Step 1: IDE = .claude (detected)
# Step 2: manifest lookup → BillingFacade → src/billing/billing.facade.ts
# Step 3: extract-signatures billing.facade.ts (~800 tokens)
# Step 4: 4 files touched → pack-context "cancelSubscription|BillingFacade" (~15k tokens)
```

## Validation gate (MANDATORY before symbol lookup)

- [ ] `<IDE_DIR>` resolved via auto-detect table (not hardcoded)?
- [ ] Manifest checked before reading any raw source file?
- [ ] If manifest missing: used the small-repository text path or generated the supported larger repository's index?
- [ ] Treated text matches as candidate files rather than verified declarations?
- [ ] Escalated only for the context actually needed?
If any unchecked → fix before performing symbol lookup.
