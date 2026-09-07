#!/usr/bin/env bash
set -euo pipefail

# Hook 4: pre-commit-review.sh (PreToolUse — Bash)
# Block `git commit` without prior code review.

# Load common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

# Read JSON input from stdin (Claude Code hook protocol).
#
# A heredoc body can be data rather than a command: `cat > notes.md <<'EOF' ...
# git commit ... EOF` writes documentation, it does not commit. Strip those
# bodies before matching, or documenting git becomes impossible.
#
# ONLY a QUOTED delimiter (<<'EOF', <<"EOF", <<\EOF) is stripped. Bash performs
# no expansion inside those, so the body is guaranteed inert text. An UNQUOTED
# <<EOF still expands $(...) in its body, so `cat > n.md <<EOF` + `$(git commit)`
# executes the commit while looking like documentation — stripping it would be a
# gate bypass, not a false-positive fix. Unquoted bodies stay in the scan.
#
# ponytail: quoted strings are still matched (`bash -c "git commit"` stays
# blocked); loosening that trades a false positive for a bypass, so it stays.
#
# The program is fed via a quoted heredoc and the JSON via argv, so neither bash
# nor the shell touches the regex escaping.
HOOK_JSON=$(cat)
# The `)` closes on its own line AFTER the heredoc terminator — a heredoc body
# inside $( ) must sit inside the parens, not after them.
TOOL_INPUT=$(python3 - "$HOOK_JSON" 2>/dev/null <<'PY'
import sys, json, re

cmd = json.loads(sys.argv[1]).get('tool_input', {}).get('command', '')
# One pass per quoting style: a single alternation would need backreferences to
# unmatched groups, which never match in Python's re.
for pattern in (
    r"<<-?[ \t]*'(\w+)'.*?^[ \t]*\1[ \t]*$",
    r'<<-?[ \t]*"(\w+)".*?^[ \t]*\1[ \t]*$',
    r"<<-?[ \t]*\\(\w+).*?^[ \t]*\1[ \t]*$",
):
    cmd = re.sub(pattern, ' ', cmd, flags=re.S | re.M)
print(cmd)
PY
) || TOOL_INPUT=""

# Is this a commit? `git` and `commit` are NOT always adjacent: git takes global
# options before the subcommand, and `git -C <dir> commit` / `git -c k=v commit`
# slipped through a bare `git[[:space:]]+commit` match — the gate did not fire at
# all. Allow a run of option tokens (each optionally followed by its value) in
# between. Deliberately biased toward blocking: `git log --grep commit` matches too,
# and a false block costs one extra word on the command line, a false pass costs the
# whole gate.
if ! [[ "$TOOL_INPUT" =~ git([[:space:]]+-[^[:space:]]*([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+commit ]]; then
  # Not a commit command, allow
  exit 0
fi

# The documented bypass is a COMMAND PREFIX (`SKIP_REVIEW=1 git commit ...`), and a
# PreToolUse hook is a separate process spawned BEFORE that command runs — the prefix
# never reaches this environment. Match it in the command itself, which is the only
# place it exists. `${SKIP_REVIEW:-0}` stays for an operator who exports it for real.
if [ "${SKIP_REVIEW:-0}" == "1" ] || [[ "$TOOL_INPUT" =~ SKIP_REVIEW=1[[:space:]]+git[[:space:]] ]]; then
  exit 0
fi

# Generate session hash based on the command cwd and current user.
# PreToolUse hooks may execute from the plugin/runtime directory, while the
# Bash command itself runs in tool_input.cwd. Use the command cwd when present
# so the review marker matches the workspace being committed.
HOOK_CWD=$(echo "$HOOK_JSON" | python3 -c "import os,sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('cwd') or d.get('cwd') or os.environ.get('PWD',''))" 2>/dev/null || echo "$PWD")

# ...but tool_input.cwd is the SESSION's directory, not necessarily the repo being
# committed. `cd /other/repo && git commit` and `git -C /other/repo commit` both commit
# somewhere else while the session stays put, so the marker would be keyed to the wrong
# repo — observed: a fresh marker for repo A gating a commit in repo B. The command names
# the real target; prefer it. `git -C` wins over `cd` because it points at the repo
# directly, and a relative path resolves against the session cwd, exactly as bash would.
#
# Both patterns are written to pick the RIGHT occurrence, not merely the first one:
#   - `git -C` is tied to the `commit` that follows it, so `git -C /a status &&
#     git -C /b commit` resolves /b. A bare first-match would have taken /a.
#   - the `cd` pattern is deliberately greedy (`.*` prefix, no `^` anchor) so the LAST
#     cd wins: in `cd /reviewed && cd /unreviewed && git commit` the commit runs from
#     /unreviewed, and matching /reviewed would hand it that repo's marker. A leading
#     space is prepended so the first token can still match the word boundary.
# Regexes live in variables: inside [[ ... =~ ... ]] bash tokenises the pattern
# itself, so a bare `;` or `|` in a bracket expression is a syntax error.
RE_GIT_C='git[[:space:]]+-C[[:space:]]+([^[:space:]]+)([[:space:]]+-[^[:space:]]*([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+commit'
RE_CD='.*[[:space:];&|]cd[[:space:]]+([^[:space:]]+)[[:space:]]*&&'
TARGET_DIR=""
if [[ "$TOOL_INPUT" =~ $RE_GIT_C ]]; then
  TARGET_DIR="${BASH_REMATCH[1]}"
elif [[ " $TOOL_INPUT" =~ $RE_CD ]]; then
  TARGET_DIR="${BASH_REMATCH[1]}"
fi

# Written as plain `if`s on purpose: under `set -e` a bare `[[ ... ]] && assign`
# whose test is false makes the whole script exit 1, which would skip the marker
# check entirely — the gate would fail open.
if [ -n "$TARGET_DIR" ]; then
  # `~` is expanded by the shell that RUNS the command, never by this regex. Left
  # unexpanded it is not absolute, so it used to be pasted onto the session cwd,
  # resolve to nothing, and silently fall back to the session repo — the exact bug
  # this block exists to fix, reintroduced by one character. Caught live 2026-09-07.
  case "$TARGET_DIR" in
    "~") TARGET_DIR="$HOME" ;;
    "~/"*) TARGET_DIR="$HOME/${TARGET_DIR#\~/}" ;;
  esac
  if [[ "$TARGET_DIR" != /* ]]; then
    TARGET_DIR="$HOOK_CWD/$TARGET_DIR"
  fi
  if [ -d "$TARGET_DIR" ]; then
    HOOK_CWD="$TARGET_DIR"
  fi
fi

# Normalize to the repo root: `cd subdir` inside the session must not invalidate a
# review done at the root (the hook runs BEFORE the command, so an inline `cd` in
# the commit command cannot help either).
if ! git -C "$HOOK_CWD" rev-parse --show-toplevel >/dev/null 2>&1; then
  echo "[BLOCKED] git commit from a path that is not a git repo (or no longer exists): $HOOK_CWD" >&2
  echo "REASON: cannot resolve the repo this commit belongs to, so the review marker cannot be checked." >&2
  exit 2
fi
SESSION_HASH=$(repo_root_hash "$HOOK_CWD")
REVIEW_MARKER="/tmp/.claude-review-done-${SESSION_HASH}"

# Check for review marker. Bounded by age: without this, one review at the start of a
# session silently unlocks every later commit in that repo forever.
REVIEW_TTL_MIN="${CF_REVIEW_TTL_MIN:-60}"
if [ -f "$REVIEW_MARKER" ]; then
  if [ -z "$(find "$REVIEW_MARKER" -mmin +"$REVIEW_TTL_MIN" 2>/dev/null)" ]; then
    exit 0
  fi
  rm -f "$REVIEW_MARKER"
  echo "[BLOCKED] review marker older than ${REVIEW_TTL_MIN} min — re-run /pre-review." >&2
  exit 2
fi

# No review marker found, block commit
cat >&2 << 'EOF'
[BLOCKED] git commit attempted without code review.
REASON: Code review required before commit (pre-commit-review hook + reviewer-protocol rule).

TO PROCEED:
  1. Use superpowers:requesting-code-review skill
  2. Wait for code-reviewer agent to complete review
  3. Review findings and address issues
  4. Try commit again

TO BYPASS (not recommended):
  SKIP_REVIEW=1 git commit -m "message"
EOF
exit 2
