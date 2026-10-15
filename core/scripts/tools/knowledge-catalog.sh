#!/usr/bin/env bash
# tools/knowledge-catalog.sh — deduplicated TSV catalog of tools/libraries/MCP servers from ai-knowledge.
# Reads entry frontmatter directly from disk, so it works while the knowledge MCP (DevHub backend) is down.
# Usage: knowledge-catalog.sh [--entries DIR] [--out FILE] [--if-stale]
set -uo pipefail

ENTRIES="${AI_KNOWLEDGE_ENTRIES:-$HOME/Projects/ai_knowledge/entries}"
OUT="$HOME/worklogs/wiki/ai-knowledge/catalog.tsv"
IF_STALE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      cat <<'EOF'
Usage: knowledge-catalog.sh [--entries DIR] [--out FILE] [--if-stale]

Build `title<TAB>tags<TAB>source_url<TAB>id<TAB>summary` from ai-knowledge Markdown entries.
Keeps only tool-shaped tags (ai-tools, dev-tools, open-source, automation, agent-engineering,
claude-code, frontend, context-engineering, evals, context-forge); dedups by normalized title.

Options:
  --entries DIR   default: $AI_KNOWLEDGE_ENTRIES or ~/Projects/ai_knowledge/entries
  --out FILE      default: ~/worklogs/wiki/ai-knowledge/catalog.tsv
  --if-stale      rebuild only if an entry is newer than FILE (silent no-op otherwise)
EOF
      exit 0 ;;
    --entries) ENTRIES="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --if-stale) IF_STALE=1; shift ;;
    *) echo "error: unknown arg $1" >&2; exit 2 ;;
  esac
done

[ -d "$ENTRIES" ] || { echo "error: entries dir not found: $ENTRIES" >&2; exit 2; }
if [ "$IF_STALE" = 1 ] && [ -f "$OUT" ] && [ -z "$(find "$ENTRIES" -name '*.md' -newer "$OUT" -print -quit)" ]; then
  exit 0
fi
mkdir -p "$(dirname "$OUT")"

python3 - "$ENTRIES" "$OUT" <<'EOF'
import os, re, sys
src, out = sys.argv[1], sys.argv[2]
KEEP = {"ai-tools","dev-tools","open-source","automation","agent-engineering","claude-code",
        "frontend","context-engineering","evals","context-forge"}
def clean(s): return re.sub(r"\s+", " ", s or "").replace("\t", " ").strip()
def field(fm, name):
    # scalar, or a folded/literal block (`>-`, `|`) continued on indented lines
    m = re.search(r"^%s:[ \t]*(.*)\n((?:[ \t]+.*\n?)*)" % name, fm, re.M)
    if not m: return ""
    head, cont = m.group(1).strip(), m.group(2)
    if head in (">", ">-", "|", "|-"): head = " ".join(l.strip() for l in cont.splitlines())
    return clean(head.strip("'\""))
rows, seen = [], set()
for name in sorted(os.listdir(src)):
    if not name.endswith(".md"): continue
    text = open(os.path.join(src, name), encoding="utf-8", errors="ignore").read()
    m = re.match(r"---\n(.*?)\n---\n?(.*)", text, re.S)
    if not m: continue
    fm, body = m.groups()
    title = field(fm, "title") or name[:-3]
    tags = re.findall(r"^\s*-\s*([\w-]+)\s*$", fm.split("tags:", 1)[1], re.M) if "tags:" in fm else []
    tags = [t for t in tags if t in KEEP]
    if not tags: continue
    key = re.sub(r"[^a-z0-9]", "", title.lower())
    if key in seen: continue
    seen.add(key)
    url = field(fm, "source_url")
    if not url.startswith("http"):
        # OCR entries point at a local screenshot; the repo/site link, when any, lives in the body
        link = (re.search(r"https?://github\.com/[^\s)\]>\"']+", body)
                or re.search(r"https?://[^\s)\]>\"']+", body))
        url = link.group(0) if link else "-"
    eid = field(fm, "id")
    first = next((l for l in body.splitlines() if l.strip() and not l.startswith("#")), "")
    rows.append("\t".join([title, ",".join(tags), url, eid or name, clean(first)[:100]]))
with open(out, "w", encoding="utf-8") as f:
    f.write("title\ttags\tsource_url\tid\tsummary\n" + "\n".join(rows) + "\n")
print(f"{len(rows)} rows -> {out}")
EOF
