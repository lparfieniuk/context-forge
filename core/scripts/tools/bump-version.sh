#!/usr/bin/env bash
# tools/bump-version.sh — write one version into every file that states it, cut the CHANGELOG.
# Usage: bump-version.sh <X.Y.Z> [--date YYYY-MM-DD]
# The drift CHECK lives in audit-doc-claims.sh (plugin-audit); this is the matching WRITER,
# so its file list mirrors that check plus package-lock.json and the local Codex AGENTS.md.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
NEW=""; DATE="$(date +%F)"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) sed -n 2,5p "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    --date) DATE="$2"; shift 2 ;;
    *) NEW="$1"; shift ;;
  esac
done
[[ "$NEW" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "error: version X.Y.Z required (see --help)" >&2; exit 2; }

python3 - "$ROOT" "$NEW" "$DATE" <<'PY'
import json, pathlib, re, sys
root, new, date = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
old = json.loads((root / ".claude-plugin/plugin.json").read_text())["version"]
key = lambda v: tuple(map(int, v.split(".")))
if key(new) <= key(old):
    sys.exit(f"error: {new} is not newer than {old}")

cl = root / "CHANGELOG.md"
text = cl.read_text()
m = re.search(r"^## \[Unreleased\]\n(.*?)(?=^## \[)", text, re.S | re.M)
if not m or not m.group(1).strip():
    sys.exit("error: CHANGELOG [Unreleased] is empty — nothing to release")

# Every edit is computed and checked in memory first; nothing is written unless all match,
# so a missing badge or field can never leave a half-bumped release.
out = {}
def sub(rel, pattern, repl, expect=1, optional=False):
    f = root / rel
    if not f.exists():
        if optional:
            return
        sys.exit(f"error: {rel} missing")
    t2, n = re.subn(pattern, repl, out.get(f, f.read_text()), count=expect, flags=re.M)
    if n != expect:
        sys.exit(f"error: {rel}: expected {expect} version match(es), found {n} — nothing written")
    out[f] = t2

field = r'("version"\s*:\s*")' + re.escape(old) + '"'
for rel in (".claude-plugin/plugin.json", ".claude-plugin/marketplace.json",
            ".cursor-plugin/plugin.json", "package.json"):
    sub(rel, field, r"\g<1>" + new + '"')
# package-lock: the two root package entries, never a dependency that happens to share the number
sub("package-lock.json", field, r"\g<1>" + new + '"', expect=2)
sub("README.md", r"badge/version-" + re.escape(old) + "-", f"badge/version-{new}-")
sub("CLAUDE.md", r"(\*\*Version:\*\*\s*)" + re.escape(old), r"\g<1>" + new)
sub("AGENTS.md", r"(\*\*Version:\*\*\s*)" + re.escape(old), r"\g<1>" + new, optional=True)  # untracked Codex copy
out[cl] = text.replace("## [Unreleased]\n", f"## [Unreleased]\n\n## [{new}] - {date}\n", 1)

for f, body in out.items():
    f.write_text(body)
    print(f"{f.relative_to(root)}: {old} -> {new}")
PY
