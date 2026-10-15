---
name: youtube-transcript
description: Fetches a YouTube video's transcript with yt-dlp (no files, per-minute buckets) and answers from it. Use when the prompt contains a youtube.com or youtu.be link, or the user says "obejrzyj ten film", "co mówi w tym wideo", "streść film", "transcript", "summarize this video". Do NOT use for scraping the YouTube page or channel metadata only (yt-dlp -j covers that), or for non-YouTube audio.
model: inherit
---

## What This Does

Runs `bash <CF_PLUGIN_ROOT>/core/scripts/tools/yt-transcript.sh <URL>` (Tier 1). Output: a header
line `title | channel | date | duration | chars`, then `[Nm] text` lines.

## Steps

1. Run the script. A 50-minute video is ~60k chars (~15k tokens) — for long videos, redirect to the
   scratchpad and read it in parts, or delegate summarising with the file path (never paste it into a prompt).
2. Answer the user's actual question; cite minute marks (`~33m`).
3. Links in the description (repos, tools) → `yt-dlp -j --skip-download <URL>` and read `.description`.

## Exit codes

| rc | Meaning | Action |
|---|---|---|
| 3 | HTTP 429 from YouTube timedtext (per-IP rate limit) | Wait 15–60 min, retry ONCE, then halt (rule 004) |
| 4 | No caption track | Try `--lang <code>`; else say so |
| 2 | Bad URL / yt-dlp missing | `brew install yt-dlp` |

## Constraints

NEVER retry a 429 more than once. NEVER paste the full transcript into the reply or a sub-agent prompt.
ALWAYS cite minute marks for claims taken from the video.

## Few-shot

**Input:** "streść https://youtu.be/c9nRxEy1kUY"
**Output:** script → 56 minute-buckets, 59 752 chars → 6-bullet summary with `~33m`-style marks,
plus the repo link read from `.description`.
