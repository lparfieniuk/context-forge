---
name: plugin-audit
description: >
  Runs the repeatable ContextForge audit gate after change packages, before PRs or commits,
  after convert, and after runtime artifact cleanup. Uses plugin-audit.sh as the only
  supported entrypoint.
model: none
---

## What This Does

Runs the full ContextForge plugin audit gate through `core/scripts/tools/plugin-audit.sh`.
The gate validates the module index, installed artifact parity, runtime artifacts,
documentation claims, plugin surface consistency, rule quality, token benchmark drift,
and test suite health.

## When to Use

Use this skill:

- After every package of ContextForge changes.
- Before creating a PR or commit.
- After `npm run convert` synchronizes installed copies.
- After cleanup of runtime artifacts such as `.claude/cache`, `.claude/lessons`,
  `.cursor/lessons`, or `.local-marketplace/plugins/context-forge`.

## How to Use

ALWAYS run the audit through the single script entrypoint:

```bash
bash core/scripts/tools/plugin-audit.sh --plugin-root .
```

NEVER assemble the audit manually from individual commands. The script is the source of
truth for gate order, failure handling, and runtime artifact detection.

## Output Format

The script returns a compact envelope:

```text
[PLUGIN AUDIT]
- validate-index: PASS
- check-parity: PASS
- audit-runtime-artifacts: PASS
- audit-doc-claims: PASS
- audit-plugin-surface: PASS
- audit-rules: PASS
- benchmark-tokens: PASS
- npm-test: PASS
- final: PASS
[END PLUGIN AUDIT]
```

## Constraints

ALWAYS treat any failing gate as blocking for PR or commit readiness.
ALWAYS report runtime artifacts as failures without deleting them.
NEVER delete runtime artifacts from this skill.
NEVER bypass `plugin-audit.sh` by running the individual gate commands manually.
NEVER treat a clean working tree as proof a repo is safe to publish — before any public release ALWAYS scan git HISTORY (`git log --all --diff-filter=A --name-only`, plus a secret/private-path grep over `git rev-list --all`). A file deleted from HEAD still lives in every earlier commit.
