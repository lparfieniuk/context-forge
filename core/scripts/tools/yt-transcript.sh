#!/usr/bin/env bash
# tools/yt-transcript.sh — YouTube auto-caption transcript to stdout, per-minute buckets, no files.
# Usage: yt-transcript.sh <URL> [--lang en]
# Exit: 0 ok · 2 usage/missing dep · 3 YouTube rate limit (HTTP 429) · 4 no captions
set -uo pipefail

URL=""; LANG_CODE="en"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      cat <<'EOF'
Usage: yt-transcript.sh <URL> [--lang <code>]

Print a YouTube video's auto-caption transcript bucketed per minute. Writes no files.

Options:
  --lang <code>   Caption language (default: en). Tries <code>-orig first, then <code>.

Output: header line (title | channel | upload_date | duration_s | chars), then `[Nm] text`.
Exit codes: 0 ok, 2 usage or yt-dlp missing, 3 HTTP 429 from YouTube (wait 15-60 min, retry once),
4 no caption track in that language.
EOF
      exit 0 ;;
    --lang) LANG_CODE="$2"; shift 2 ;;
    *) URL="$1"; shift ;;
  esac
done

[ -n "$URL" ] || { echo "error: URL required (see --help)" >&2; exit 2; }
command -v yt-dlp >/dev/null || { echo "error: yt-dlp not installed (brew install yt-dlp)" >&2; exit 2; }

[[ "$URL" =~ ^https?://(www\.|m\.)?(youtube\.com|youtu\.be)/ ]] || { echo "error: not a YouTube URL: $URL" >&2; exit 2; }

ERR=$(mktemp); trap 'rm -f "$ERR"' EXIT
if ! META=$(yt-dlp -j --skip-download -- "$URL" 2>"$ERR"); then
  if rg -q '429|Too Many Requests' "$ERR" 2>/dev/null; then
    echo "error: HTTP 429 rate limit from YouTube — wait 15-60 min, retry once, then stop" >&2; exit 3
  fi
  echo "error: yt-dlp could not read $URL: $(tail -1 "$ERR")" >&2; exit 2
fi

printf '%s' "$META" | python3 -c '
import json, sys, urllib.request, urllib.error
lang = sys.argv[1]
d = json.load(sys.stdin)
tracks = {**(d.get("automatic_captions") or {}), **(d.get("subtitles") or {})}
src = tracks.get(lang + "-orig") or tracks.get(lang) or []
urls = [t["url"] for t in src if t.get("ext") == "json3"]
if not urls:
    print("error: no %s caption track" % lang, file=sys.stderr); sys.exit(4)
req = urllib.request.Request(urls[0], headers={"User-Agent": "Mozilla/5.0"})
try:
    body = urllib.request.urlopen(req, timeout=30).read()
except urllib.error.HTTPError as e:
    if e.code == 429:
        print("error: HTTP 429 rate limit from YouTube timedtext — wait 15-60 min, retry once, then stop", file=sys.stderr); sys.exit(3)
    raise
buckets = {}
chars = 0
for e in json.loads(body).get("events", []):
    s = "".join(x.get("utf8", "") for x in (e.get("segs") or [])).strip()
    if s:
        buckets.setdefault(e["tStartMs"] // 60000, []).append(s); chars += len(s) + 1
print("%s | %s | %s | %ss | %d chars" % (d.get("title"), d.get("channel"), d.get("upload_date"), d.get("duration"), chars))
for m in sorted(buckets):
    print("[%dm] %s" % (m, " ".join(buckets[m])))
' "$LANG_CODE"
