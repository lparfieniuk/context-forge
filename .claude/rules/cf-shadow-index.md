# Shadow Index Protocol

## SYSTEM CONSTRAINTS

NEVER read raw source files for type/API discovery — use manifest first.
NEVER skip Step 1 (manifest) and jump to Step 2 or 3.
NEVER read more than 5 raw source files without escalating to pack-context skill.
ALWAYS resolve `<IDE_DIR>` (`.claude` or `.cursor`) before manifest lookup.
ALWAYS generate manifest immediately when absent — NEVER ask user, NEVER skip.
NEVER hardcode `.cursor/shadow/` — ALWAYS use IDE-resolved `<IDE_DIR>`.

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
  - If MISSING → run `/refresh-manifest` skill immediately. Do NOT ask user.
  - If present → read manifest. Find target symbol path.
Step 3 — extract-signatures: run against the file found in Step 2.
  - Sufficient for interface understanding and writing new code.
Step 4 — pack-context: only when task touches 3+ interrelated files with full method bodies required.

## Raw Source — When to Use

- Applying a diff (editing actual file).
- Verifying runtime behavior not visible in signatures.

## Few-shot example

**Input:** "Add cancelSubscription() to BillingFacade."
**Reasoning:** Step 1 first — find file via manifest. Then Step 2 — get signatures. 3+ files → Step 3.
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
- [ ] If manifest missing: `/refresh-manifest` run immediately (not skipped, not asked user)?
- [ ] Not reading >5 raw files without escalating to pack-context?
If any unchecked → fix before performing symbol lookup.
