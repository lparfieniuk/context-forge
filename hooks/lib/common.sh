#!/usr/bin/env bash
# Shared utility functions for ContextForge hooks.

# Portable md5 hash of stdin. Works on macOS (md5 -q) and Linux (md5sum).
# Trailing newlines are stripped first: callers pipe in via both `echo "$PWD"`
# and `printf "%s" "$PWD"`, and md5("path\n") != md5("path") would silently give
# two different session ids for the same directory.
pwd_hash() {
  tr -d '\n' | if command -v md5 >/dev/null 2>&1; then
    md5 -q
  else
    md5sum | awk '{print $1}'
  fi
}

# Stable per-repo session id. ALWAYS use this instead of hashing $PWD directly.
#
# Hashing the raw cwd gives one repo N identities — one per subdirectory a session
# happens to cd into — which silently splits the diary, the run log and the review
# marker that are all supposed to be per-repo. Observed: a completed review in the
# repo root did not unblock a commit issued after `cd cf-bench`, and a cwd left
# pointing at an already-deleted mktemp dir hashed to a ghost id.
#
# Usage: repo_root_hash [dir]   (defaults to $PWD)
repo_root_hash() {
  local dir="${1:-$PWD}" root
  root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || root="$dir"
  printf "%s" "${root}:$(whoami)" | pwd_hash | cut -c1-8
}
