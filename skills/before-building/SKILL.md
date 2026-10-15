---
name: before-building
description: Fires the moment the user proposes a build or change, and surfaces the 1-3 consequential choices hidden in the idea before any code. Use when the user says "zbuduj", "dodaj", "zrób", "zaimplementuj", "chcę mieć", "build", "add", "implement", "let's make". Do NOT use for a new product or multi-component feature that needs a full design (that is superpowers:brainstorming), for bug fixes (systematic-debugging), or when the user already answered these choices.
model: inherit
---

## What This Does

Front-loads the 2-minute conversation that saves the rewrite: the choices a user did not know they
were making when they asked for a build.


Respond instantly, from the gut. Do NOT read files, search, or call any tool — the next message
is the answer, based only on what the user just said.

List the 1-3 truly consequential choices hidden in the idea (fewer is better). For each:
the options in a few words + your gut pick + one-line reason.

Classics: one-off vs reused later · few lines vs proper module · new dependency vs stdlib ·
the biggest thing it could break · where state lives.

Skip anything minor. Nothing consequential → say "brak istotnych wyborów" and proceed.
Otherwise stop and wait for answers.

Adapted from github.com/davidondrej/skills (MIT).

## Constraints

NEVER call a tool before this answer. NEVER list more than 3 choices. NEVER start implementing in the same message.

## Few-shot

**Input:** "dodaj eksport raportu do CSV"
**Output:** 1) jednorazowy przycisk vs endpoint używany później — pick: przycisk, endpoint gdy pojawi się drugi konsument.
2) ręczny CSV vs biblioteka — pick: ręczny (`join`), biblioteka przy polach z cudzysłowami/newline. Czekam.
