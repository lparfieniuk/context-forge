---
name: rule-index
description: Loads the ContextForge rule governing a specific concern: prompt caching, context clearing, MCP routing, sub-agent prompts, research after a failure, cloud spend, or token pricing. Use before an API call, an MCP or sub-agent call, a failure recovery, or a spend decision.
model: haiku
tier: 0
---

# Rule Index

12 ContextForge rules load ON DEMAND instead of occupying context every session.
Measured 2026-08-17: installing them as always-on project instructions cost
**14968 tokens per session**. This index costs ~250 and reads only what the task
needs.

## Constraints

ALWAYS read the rule file BEFORE acting on the concern it governs — reading it afterwards is an audit, not a guardrail.
NEVER read more than 2 rule files for one task. If a task seems to need 3+, the task is too broad — split it.
NEVER quote a rule body back into the response — apply it, cite it as `rule NNN` in one clause.
NEVER guess a rule's content from its name. Read it or do not cite it.

## Index

| Read when you are about to… | Rule | File |
|---|---|---|
| design a prompt/cache layout, choose a TTL, place static context | 006 prompt-caching | `006-cf-prompt-caching.md` |
| decide which rules a task needs (branch → task_type budget) | 007 context-loading | `007-cf-context-loading.md` |
| write a worklog/ticket entry, or resume from one | 008 worklog | `008-cf-worklog.md` |
| add or move a ContextForge module (rule/skill/agent) | 009 module-index | `009-cf-module-index.md` |
| write a `Task()` prompt or evaluate a sub-agent's return | 011 kernel-prompts | `011-cf-kernel-prompts.md` |
| author or edit a rule file | 012 rule-authoring | `012-cf-rule-authoring.md` |
| set `thinking`/`effort` on a direct Messages API call | 013 interleaved-thinking | `013-cf-interleaved-thinking.md` |
| clear tool results or thinking blocks; context editing API | 014 tool-result-clearing | `014-cf-tool-result-clearing.md` |
| call an MCP tool (playwright, chrome-devtools, firecrawl, glif) | 015 mcp-tools | `015-cf-mcp-tools.md` |
| recover from a failed action; search GitHub/docs/forums | 016 research-escalation | `016-cf-research-escalation.md` |
| submit metered remote work (GPU pod, serverless, paid API) | 017 cloud-execution | `017-cf-cloud-execution.md` |
| justify a routing choice in dollars; batch vs sync | 018 cost-model | `018-cf-cost-model.md` |

## How to read one

```bash
cat "${CLAUDE_PLUGIN_ROOT}/core/rules/<file>"
```

Always-on rules (001 token-efficiency, 002 shadow-index, 003 tier-routing,
004 circuit-breaker, 005 code-search, 010 context-budget, 019 critical-response)
are already loaded — NEVER read those from disk.

## Few-shot example

**Input:** About to call `firecrawl_crawl` to pull a docs site.

**Reasoning:** MCP tool call → rule 015 governs it and must be read BEFORE the call, not after. One file, not two.

**Output:**
```bash
cat "${CLAUDE_PLUGIN_ROOT}/core/rules/015-cf-mcp-tools.md"
# → uncapped crawl is BANNED; set limit + maxDepth, onlyMainContent: true
```

## Validation gate (MANDATORY before citing a rule)

- [ ] Rule file actually read this session (not recalled from its name)?
- [ ] Read BEFORE the action it governs, not after?
- [ ] ≤2 rule files for this task?
- [ ] Rule applied, not quoted back into the response?
If any unchecked → fix before proceeding.
