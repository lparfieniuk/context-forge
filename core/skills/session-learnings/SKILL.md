---
name: session-learnings
description: >
  Captures key observations, anti-patterns, and rule improvement suggestions at the end of a
  session. Writes a sharded YAML to ~/worklogs/learnings/YYYY/MM/ and updates the learnings index.
  <example>
  Context: End of a debugging session on manifest generation
  user: "/session-learnings"
  assistant: "Captured 3 observations, 1 anti-pattern, 2 rule suggestions → ~/worklogs/learnings/2026/04/2026-04-14-manifest-debug.yaml"
  </example>
model: sonnet
---

## What This Does

Reviews the current session conversation **plus today's diary** (`/diary` decisions +
SessionEnd baseline) to extract:
- **Observations:** factual findings about how the system behaved
- **Anti-patterns:** behaviors or approaches that caused waste or errors
- **Rule suggestions:** concrete improvements to existing rules or new constraints needed
- **Next actions:** deferred tasks that should be picked up in a future session

Writes to `~/worklogs/learnings/YYYY/MM/YYYY-MM-DD-<slug>.yaml` (date-sharded for efficient lookup).
Updates `~/worklogs/learnings/INDEX.yaml` with the new entry.

## When to Use

**Trigger:**
- `/session-learnings` command (manual invocation)
- End of any substantive session (implementation, debugging, refactoring)
- After a circuit-breaker halt that was resolved

**Skip:**
- Sessions that were purely exploratory with no findings
- Sessions shorter than ~15 minutes with no significant discoveries

## How to Use

1. Read today's diary — the durable record of this day's decisions and outcomes:
   `cat ~/worklogs/diaries/$(date +%Y/%m)/$(date +%Y-%m-%d)-$(printf "%s" "$PWD" | (md5 -q 2>/dev/null || md5sum | awk '{print $1}') | cut -c1-8).yaml`
   Missing file → skip, conversation is the only source. Present → its `decisions`,
   `worked`, `failed`, and `signals` are facts; mine them for observations and
   anti-patterns before reading the conversation.
2. Review conversation for observations, anti-patterns, and rule friction points.
3. Generate a 2-3 word slug summarizing the session focus (e.g., `manifest-debug`, `auth-refactor`).
4. Write YAML to `~/worklogs/learnings/YYYY/MM/YYYY-MM-DD-<slug>.yaml`.
5. Append entry to `~/worklogs/learnings/INDEX.yaml` — **nested under the `entries:` key, indented 2 spaces** (see INDEX Append Format below).
6. Return summary of what was captured.

## INDEX Append Format (get the indentation right)

`INDEX.yaml` is a mapping with a single `entries:` key — appended items MUST be
nested under it. A column-0 `- ts:` append makes the whole file invalid YAML
(`end of the stream or a document separator is expected`) and silently breaks the
SessionStart recall, which reads `^  - ` and would then show stale entries forever.

```yaml
entries:
  - ts: "2026-04-14"                    # 2 spaces before the dash
    slug: shadow-index-optimization     # 4 spaces for fields
    file: "learnings/2026/04/2026-04-14-shadow-index-optimization.yaml"
    repo: context-forge
    summary: "One-line what/why + key findings."
    rule_suggestions_count: 2
    topics: [shadow-index, manifest, performance]
```

After appending, verify the file still parses:
`node -e "require('js-yaml').load(require('fs').readFileSync(process.env.HOME+'/worklogs/learnings/INDEX.yaml','utf8'))"`

## Output Format

```yaml
date: "2026-04-14"
slug: shadow-index-optimization
session_focus: "Optimized manifest generation for large repos"
observations:
  - "Manifest generation takes >30s for repos with >2000 files"
  - "Incremental updates not yet implemented"
anti_patterns:
  - "Reading full manifest when shadow-lookup.sh suffices"
rule_suggestions:
  - rule: cf-shadow-index
    suggestion: "Add incremental update mode for large repos"
next_actions:
  - "Implement delta manifest generation"
```

## Constraints

ALWAYS write to sharded path `YYYY/MM/YYYY-MM-DD-<slug>.yaml` — NEVER flat directory.
ALWAYS update `~/worklogs/learnings/INDEX.yaml` after writing.
ALWAYS nest the INDEX entry under `entries:` with a 2-space indent (`  - ts:`) — a column-0 `- ts:` append is BANNED: it invalidates the YAML and silently breaks SessionStart cross-session recall (rule 008).
ALWAYS read today's diary before writing — it is the durable record and survives `/clear`, the conversation does not.
NEVER fabricate observations — only capture what actually occurred in the session or the diary.
NEVER include raw code snippets — observations must be prose.
ALWAYS generate a meaningful slug (not `session-1`, `day-1`, etc.).
NEVER write more than 10 items per section — compress to the most significant findings.
