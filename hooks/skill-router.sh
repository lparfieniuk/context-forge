#!/usr/bin/env bash
set -uo pipefail   # never `-e`: a prompt hook must never block the user's prompt

# Hook: skill-router.sh (UserPromptSubmit)
# Deterministic task → skill hint. Matches the prompt against hooks/lib/skill-routes.tsv and
# injects one line of additionalContext naming the skill to invoke first.
#
# Why: skills matched only by description stayed at ~zero use (2026-10-15: 5 Skill calls in 45 days).
# Descriptions are English and get dropped from the listing under budget pressure; a hook fires
# every time, in Polish too, at zero token cost when nothing matches.
# Each hit is logged to ~/worklogs/logs/skill-router.tsv so a route's hit→invocation rate is measurable.

ROUTES="$(dirname "$0")/lib/skill-routes.tsv"
[ -f "$ROUTES" ] || exit 0

python3 -c '
import json, os, re, sys, time
try:
    prompt = json.load(sys.stdin).get("prompt", "") or ""
except Exception:
    sys.exit(0)
p = re.sub(r"\s+", " ", prompt).strip().lower()
if len(p) < 8 or p.startswith("/"):   # slash commands already name what to run
    sys.exit(0)
for line in open(sys.argv[1], encoding="utf-8"):
    if not line.strip() or line.startswith("#"):
        continue
    parts = line.rstrip("\n").split("\t")
    if len(parts) != 3:
        continue
    label, skill, rx = parts
    try:
        if not re.search(rx, p):
            continue
    except re.error:
        continue
    log = os.path.expanduser("~/worklogs/logs/skill-router.tsv")
    try:
        os.makedirs(os.path.dirname(log), exist_ok=True)
        with open(log, "a") as f:
            f.write("%s\t%s\t%s\n" % (time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), skill, os.path.basename(os.getcwd())))
    except OSError:
        pass
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "UserPromptSubmit",
        "additionalContext": "skill-router: prompt looks like %s → invoke Skill(%s) first, unless the user already said how to do it." % (label, skill)}}))
    break
' "$ROUTES" 2>/dev/null || true
exit 0
