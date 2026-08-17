---
name: evolve-apply
description: Applies a human-approved evolve proposal, then converts, audits, and reverts on failure. Use only after explicit approval of a specific proposal id.
model: haiku
---

## What This Does

Applies one approved proposal from `<IDE_DIR>/evolve/pending/<id>.yaml` to the
source tree under the human gate. This is the ONLY path by which the
self-evolving loop mutates `core/`.

## How to Use

1. Confirm the human has explicitly approved `<id>` (NEVER infer approval).
2. Run: `bash core/scripts/tools/evolve-apply.sh <id>`.
3. On `[EVOLVE-APPLY] <id> applied`: the patch landed, `npm run convert` and
   `npm run test:audit` passed, and the proposal moved to `applied/`. Commit it.
4. On `reverted`: the patch or the audit failed; the tree is clean. Invoke
   `/record-failure` to log a ledger, then report the failure. Do NOT retry blindly.

Every invocation appends one row to `<IDE_DIR>/evolve/ledger.tsv`
(`applied | reverted | reverted-patch`) — the persistent outcome record `/evolve`
reads Tier-0 to avoid re-proposing patches that were already reverted.

## Constraints

NEVER run without explicit human approval of the specific proposal id.
NEVER edit the patch_text — apply it verbatim or report failure.
ALWAYS rely on evolve-apply.sh to revert on audit failure (do not hand-patch).
NEVER apply more than one proposal per invocation.
ALWAYS commit applied changes so the audit trail (git) stays intact.
