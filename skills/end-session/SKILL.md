---
name: end-session
description: Closes out a session: diary, learnings, commit, and merge of the working branch. Use when the user signals the work is finished.
model: none
---

## What This Does

One command to close out a working session in ANY repo:

1. `/diary` — record the session's decisions/outcomes.
2. `/session-learnings` — capture reusable insights to `~/worklogs/learnings/`.
3. Commit every change in the repo.
4. Auto-merge the working branch into the main branch (no confirmation).

This is a generic close-out for OTHER repos. It deliberately does NOT run
`/evolve` or `plugin-audit` — those are context-forge-internal and run by hand.

## When to Use

- User says the session is finishing: "kończymy sesję", "we're done", "wrap up", `/end-session`.
- NOT mid-session — this commits and merges, it is a terminal action.

## Steps (run in order, stop on first failure)

1. **Capture diary** — invoke the `diary` skill with a one-line summary of the
   session's key decision(s) and outcome. If nothing significant happened, skip.

2. **Capture learnings** — invoke the `session-learnings` skill. Let it write to
   `~/worklogs/learnings/`.

3. **Commit** — from the repo root:
   ```bash
   git add -A
   git commit -m "<conventional message summarizing the session>"
   ```
   If `git commit` reports "nothing to commit", continue to step 4.

4. **Auto-merge into main** — detect the main branch, then merge:
   ```bash
   MAIN=$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
   [ -z "$MAIN" ] && { git rev-parse --verify --quiet main >/dev/null && MAIN=main || MAIN=master; }
   CUR=$(git branch --show-current)
   if [ "$CUR" = "$MAIN" ]; then
     echo "already on $MAIN — commit only, no merge needed"
   else
     git checkout "$MAIN" && git merge --no-ff "$CUR" -m "merge $CUR into $MAIN (session close)"
   fi
   ```
   If the merge reports a conflict, STOP: report the conflicting files, leave
   the repo mid-merge, do NOT `--abort` or force. This is a circuit-breaker halt
   (rule 004) — the user resolves the merge.

5. **Report** — one line:
   `[END-SESSION] diary + learnings captured, committed <N> files, merged <CUR> → <MAIN>` (or `committed on <MAIN>, no merge`).

## Constraints

NEVER push to remote — this skill stops at the local merge (add push only if the user asks).
NEVER run `/evolve` or `plugin-audit` from here — those are context-forge-internal, run manually.
NEVER force-resolve or `--abort` a merge conflict — halt and hand it to the user.
NEVER skip the commit before the merge — an unstaged change lost in a checkout is unrecoverable.
ALWAYS run the steps in order; a failed diary/learnings capture does not block the commit, but a failed commit BLOCKS the merge.
