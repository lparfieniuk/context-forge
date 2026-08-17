---
name: extract-signatures
description: Extracts function and class signatures (names, parameters, return types — no bodies) from TypeScript or PHP files. Use before editing an unfamiliar file, to learn its API for ~500-2k tokens instead of a full read.
model: haiku
---

## What This Does

Runs `bash ${CLAUDE_PLUGIN_ROOT}/core/scripts/tools/extract-signatures.sh --file <path>` and returns the file's declaration lines — the `line:source` of each top-level declaration, plus public class members and framework decorators when the file has any. Bodies are not shown because the lines that open them are not followed. Supports TypeScript/JavaScript and PHP. Always reads live source — no cache.

Files of 50 lines or fewer are printed in full: below that size extraction saves nothing. If the extraction would be no smaller than the source (a module that is almost entirely declarations), the tool says so and tells you to read the file instead — it never costs more than the Read it replaces.

## When to Use

- "How is X structured?" or "What methods does X have?"
- Before editing a file — pre-edit recon to understand the API contract
- Need function/class signatures without reading full file bodies (~500–2k tokens per file vs full file cost)

## How to Use

```bash
bash ${CLAUDE_PLUGIN_ROOT}/core/scripts/tools/extract-signatures.sh --file <path/to/file.ts>
```

`--file` is the only argument. There is no `--kind` and no `--repo`; the script
rejects any other flag.

## Output Format

```
=== EXTRACT SIGNATURES: geometry.ts ===

## Top-level declarations

4:export const dist = (a: Vec2, b: Vec2): number => Math.hypot(b.x - a.x, b.y - a.y);
24:export function wallDir(w: Wall): Vec2 {
46:export function projectOnSegment(p: Vec2, a: Vec2, b: Vec2): { point: Vec2; t: number } {

METRICS:
  issues=0
  lines=100
=== DONE EXTRACT SIGNATURES ===
```

`## Public class members` and `## Decorators` sections appear only when the file
contains a class or framework decorators. Measured on that 100-line module:
1060 B out for 3456 B of source.

## Constraints

- NEVER read full files >200 lines without using this skill first
- ALWAYS use this before editing a file with complex APIs
- NEVER cache or reuse output — always re-run for fresh results
