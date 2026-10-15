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

# Tree hash of the whole working tree — tracked edits, staged files AND untracked
# non-ignored files — computed in a throwaway index so the real one is never touched.
# Identical before and after `git add`, so a review marker can be bound to the exact
# content reviewed: any edit after the review changes it.
#
# Usage: worktree_fingerprint [dir]   (prints nothing and returns 1 outside a repo)
worktree_fingerprint() {
  local dir="${1:-$PWD}" root gitdir tmp tree
  root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || return 1
  gitdir=$(git -C "$root" rev-parse --absolute-git-dir) || return 1
  # assume-unchanged / skip-worktree entries would hide edits from `git add -A`, so a
  # changed tree could match the reviewed one — refuse to fingerprint (fail closed).
  [ -n "$(git -C "$root" ls-files -v | awk '/^([a-z]|S) /{print; exit}')" ] && return 1
  tmp=$(mktemp) || return 1
  # Seeding from the real index lets `git add -A` reuse its stat cache instead of
  # rehashing every file.
  if [ -f "$gitdir/index" ]; then cp "$gitdir/index" "$tmp"; else rm -f "$tmp"; fi
  tree=$(GIT_INDEX_FILE="$tmp" git -C "$root" add -A >/dev/null 2>&1 \
    && GIT_INDEX_FILE="$tmp" git -C "$root" write-tree 2>/dev/null)
  rm -f "$tmp"
  [ -n "$tree" ] && printf "%s\n" "$tree"
}
