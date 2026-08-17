---
name: refresh-manifest
description: Regenerates the shadow index manifest of top-level exports for fast symbol lookup. Use when the manifest is missing or stale, or symbol lookup returns nothing.
model: haiku
---

## What This Does

Runs `bash ${CLAUDE_PLUGIN_ROOT}/core/scripts/tools/refresh-manifest.sh` to regenerate lightweight shadow manifests. Reads `config/manifest-repos.json` (relative to plugin root) to discover target repositories, their absolute paths, and which subdirectories to scan. For each repository, scans TypeScript/JavaScript source files, extracts top-level exports (classes, interfaces, functions, types, enums), and generates `_manifest.lightweight.yaml` with proper metadata. Auto-detects the active IDE by checking whether `.claude` or `.cursor` directories exist. Dual-writes to both `.claude/shadow/` and `.cursor/shadow/` to keep both IDEs in sync. Manifests include YAML `metadata.generated` timestamp for freshness validation.

## When to Use

- Manifest file missing: `<IDE_DIR>/shadow/<repo>/_manifest.lightweight.yaml` not found
- Symbol lookups return stale or incorrect results
- Large refactor completed (new files/classes added to top-level exports)
- `validate-manifest.sh` reports STALE or MISSING verdict

## How to Use

Step 1: Run refresh-manifest.

```bash
bash ${CLAUDE_PLUGIN_ROOT}/core/scripts/tools/refresh-manifest.sh
```

Optional flags:
- `--repo <repo>` — regenerate for a specific repository only

Step 2: Verify output shows `[MANIFEST GENERATED]` with FRESH verdict.

Step 3: Proceed with symbol lookups via shadow-lookup skill.

## Output Format

```
=== REFRESH MANIFEST ===
Config: config/manifest-repos.json

  Scanning repo: my-workspace at ../../my-workspace
    → .claude/shadow/my-workspace/_manifest.lightweight.yaml (1247 symbols)
    → .cursor/shadow/my-workspace/_manifest.lightweight.yaml (1247 symbols)
  
  Scanning repo: builder at ../../builder
    → .claude/shadow/builder/_manifest.lightweight.yaml (345 symbols)
    → .cursor/shadow/builder/_manifest.lightweight.yaml (345 symbols)

=== DONE REFRESH MANIFEST ===
```

Each manifest contains a YAML structure with:
```yaml
metadata:
  generated: 1729900000      # epoch timestamp for freshness tracking
  repo: my-workspace
symbols:
  - symbol: BillingFacade
    kind: class
    file: libs/data-access-billing/src/lib/billing.facade.ts
    repo: my-workspace
```

## Input

- **config/manifest-repos.json** (relative to plugin root): JSON file declaring each repository to scan, with `name`, `rel_path` (relative to plugin root), and `paths` (array of subdirectories to scan, e.g. `["libs/", "apps/"]`). Example:
  ```json
  {
    "repos": [
      {"name": "my-workspace", "rel_path": "../../my-workspace", "paths": ["libs/", "apps/"]},
      {"name": "builder", "rel_path": "../../builder", "paths": ["src/"]}
    ]
  }
  ```

## Constraints

- NEVER skip this step when manifest is missing — ALWAYS run before shadow-lookup
- ALWAYS dual-write to both .claude/shadow/ and .cursor/shadow/ when both directories exist
- NEVER run during an active refactor that has unsaved files — results will be stale
- config/manifest-repos.json MUST exist and contain valid JSON with `repos` array
