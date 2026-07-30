# Context Loading

## SYSTEM CONSTRAINTS

ALWAYS detect `task_type` from branch prefix before loading any context-specific rules.
NEVER load domain or integration rules for a single-file fix (<3 files, no cross-boundary changes).
NEVER load rules tagged `skip_on_bugfix: true` when `task_type = bugfix`.
ALWAYS use the decision table below to determine the minimal rule set per task type.

## Task Type Detection (Branch Heuristic)

| Branch prefix | task_type |
|---------------|-----------|
| `fix/`, `hotfix/`, `bugfix/` | bugfix |
| `feature/`, `feat/` | new_feature |
| `refactor/`, `cleanup/` | refactor |
| `spike/`, `poc/`, `research/` | spike |
| anything else | unknown |

## Decision Table: Rules to Load

| task_type | Core | Domain Rules | Integration Rules | Boundary Rules |
|-----------|------|-------------|-------------------|----------------|
| `bugfix` | ALWAYS | SKIP | SKIP | SKIP |
| `new_feature` | ALWAYS | if domain changes | if external integration | if new module/boundary |
| `refactor` | ALWAYS | if domain logic changes | if dependencies change | ALWAYS |
| `spike` | ALWAYS | SKIP | SKIP | SKIP |
| `unknown` | ALWAYS | on demand | on demand | on demand |

## Rule Token Budget

| task_type | Max tokens | Justification |
|-----------|-----------|---------------|
| `bugfix` | ~3k | Core only — narrow scope |
| `new_feature` | ~8k | Full context needed |
| `refactor` | ~5k | Domain + boundary |
| `spike` | ~2k | Discovery mode |
| `unknown` | ~5k | Conservative default |

## Few-shot example

**Input:** Branch is `fix/PROJ-1234-null-check`.
**Reasoning:** `fix/` prefix → task_type: bugfix. Load core only. Skip domain/integration rules.
**Output:**
```
task_type: bugfix
Loaded: core rules only (001-cf-token-efficiency, 002-cf-shadow-index, 003-cf-tier-routing, 004-cf-circuit-breaker, 010-cf-context-budget)
Skipped: domain, integration, boundary rules (005-cf-code-search is intelligent-mode — NOT always-on)
Token budget: ~2.8k / 3k limit
```

## Validation gate

- [ ] task_type detected from branch prefix before loading rules?
- [ ] `skip_on_bugfix` rules skipped when task_type = bugfix?
- [ ] Rule token budget within limits for detected task_type?
- [ ] Domain/integration rules NOT loaded for single-file fixes?
If any unchecked → fix before loading additional rules.
