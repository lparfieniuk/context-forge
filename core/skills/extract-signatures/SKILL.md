---
name: extract-signatures
description: >
  Extracts method stubs (names, parameters, return types — no bodies) from TypeScript or PHP source files using a live ripgrep-based script. Returns ~500-2k tokens per file, always fresh.
  <example>
  Context: User needs to understand AuthService API before editing it.
  user: "Extract signatures from libs/auth/src/lib/auth.service.ts"
  assistant: "Running extract-signatures on auth.service.ts — returns class/method stubs without bodies."
  </example>
model: haiku
---

## What This Does

Runs `bash ${CLAUDE_PLUGIN_ROOT}/core/scripts/tools/extract-signatures.sh --file <path>` and returns method stubs only: names, parameters, return types, decorators. Method bodies are replaced with `// ...`. Supports TypeScript and PHP. Always reads live source — no cache.

## When to Use

- "How is X structured?" or "What methods does X have?"
- Before editing a file — pre-edit recon to understand the API contract
- Need function/class signatures without reading full file bodies (~500–2k tokens per file vs full file cost)

## How to Use

```bash
bash ${CLAUDE_PLUGIN_ROOT}/core/scripts/tools/extract-signatures.sh --file <path/to/file.ts>
```

Optional flags:
- `--kind class|interface|function` — filter by symbol kind
- `--repo <repo>` — scope to a specific repository

## Output Format

```typescript
// auth.service.ts — signatures only
export class AuthService {
  authenticate(userId: string, tenantId: string): Observable<AuthResult>
  refreshToken(token: RefreshToken): Observable<AccessToken>
  logout(): void
}
```

Indented signature blocks, one class/interface per section, no method bodies.

## Constraints

- NEVER read full files >200 lines without using this skill first
- ALWAYS use this before editing a file with complex APIs
- NEVER cache or reuse output — always re-run for fresh results
- ALWAYS replace method bodies with `// ...` in output
