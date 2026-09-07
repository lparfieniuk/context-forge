/**
 * hooks.test.ts — Guards against session-start hook breakage.
 *
 * Regression for: https://github.com/anthropics/claude-code/issues
 * Root cause: ~/.claude/plugins/cache/local/ missing → CLAUDE_PLUGIN_ROOT points to
 * non-existent path → hook exits 127 → "startup hook error" on every session.
 *
 * This suite catches:
 *   1. Hook parity drift between source and .local-marketplace
 *   2. Hook execution failure when run with a valid CLAUDE_PLUGIN_ROOT
 */

import { describe, it, expect } from 'vitest';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { spawnSync } from 'child_process';

const PLUGIN_ROOT = path.resolve(__dirname, '..');
const SOURCE_HOOKS = path.join(PLUGIN_ROOT, 'hooks');
const MARKETPLACE_HOOKS = path.resolve(
  PLUGIN_ROOT,
  '../.local-marketplace/plugins/context-forge/hooks',
);

// ---------------------------------------------------------------------------
// Parity: source hooks must match marketplace hooks
// ---------------------------------------------------------------------------

// The marketplace lives outside the repo (a sibling `.local-marketplace/`), so it
// is present only on a machine that has the plugin installed locally. On a fresh
// clone and in CI there is nothing to compare against — skip rather than fail.
const HAS_MARKETPLACE = fs.existsSync(MARKETPLACE_HOOKS);

describe.skipIf(!HAS_MARKETPLACE)('hook parity: source vs .local-marketplace', () => {
  it('all source hook files are present and identical in marketplace', () => {
    const sourceFiles = fs
      .readdirSync(SOURCE_HOOKS)
      .filter(f => fs.statSync(path.join(SOURCE_HOOKS, f)).isFile());

    const diffs: string[] = [];

    for (const file of sourceFiles) {
      const srcPath = path.join(SOURCE_HOOKS, file);
      const destPath = path.join(MARKETPLACE_HOOKS, file);

      if (!fs.existsSync(destPath)) {
        diffs.push(`missing in marketplace: ${file}`);
        continue;
      }

      const srcContent = fs.readFileSync(srcPath, 'utf-8');
      const destContent = fs.readFileSync(destPath, 'utf-8');

      if (srcContent !== destContent) {
        diffs.push(`content differs: ${file} — run: npm run convert`);
      }
    }

    expect(diffs).toEqual([]);
  });

  // `convert.ts` writes but never prunes. A deleted or renamed hook keeps running
  // from the installed copy — wiki-nudge.sh and pre-compact-anchor.sh both survived
  // their own deletion this way on 2026-09-05, and every other gate passed.
  it('marketplace holds no hook file that source has dropped', () => {
    const sourceFiles = new Set(
      fs.readdirSync(SOURCE_HOOKS).filter(f => fs.statSync(path.join(SOURCE_HOOKS, f)).isFile()),
    );
    const orphans = fs
      .readdirSync(MARKETPLACE_HOOKS)
      .filter(f => fs.statSync(path.join(MARKETPLACE_HOOKS, f)).isFile())
      .filter(f => !sourceFiles.has(f));

    expect(orphans).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// Execution: session-start.sh must exit 0 with a valid CLAUDE_PLUGIN_ROOT
// Regression test for the bootstrap failure (exit 127)
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// repo_root_hash: one repo → one identity, regardless of which subdir the
// session cd'd into. Regression for the cwd-fragmentation bug (review marker /
// diary / run log splitting per subdirectory).
// ---------------------------------------------------------------------------

describe('repo_root_hash (hooks/lib/common.sh)', () => {
  const COMMON = path.join(SOURCE_HOOKS, 'lib/common.sh');
  const hashOf = (dir: string) =>
    spawnSync('bash', ['-c', '. "$1"; repo_root_hash "$2"', '_', COMMON, dir], {
      encoding: 'utf-8',
    }).stdout.trim();

  const gitInit = (dir: string) => spawnSync('git', ['-C', dir, 'init', '-q']);

  it('a subdirectory hashes to the same id as the repo root', () => {
    const repo = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-repo-'));
    gitInit(repo);
    const sub = path.join(repo, 'a/b/c');
    fs.mkdirSync(sub, { recursive: true });
    expect(hashOf(sub)).toBe(hashOf(repo));
  });

  it('a different repo gets a different id', () => {
    const r1 = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-repo-'));
    const r2 = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-repo-'));
    gitInit(r1);
    gitInit(r2);
    expect(hashOf(r1)).not.toBe(hashOf(r2));
  });

  it('non-git dir falls back deterministically to an 8-char hash', () => {
    const d = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-nogit-'));
    const h = hashOf(d);
    expect(h).toBe(hashOf(d));
    expect(h).toMatch(/^[0-9a-f]{8}$/);
  });

  it('a deleted cwd does not crash and still yields an 8-char hash', () => {
    const ghost = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-ghost-'));
    fs.rmSync(ghost, { recursive: true, force: true });
    expect(hashOf(ghost)).toMatch(/^[0-9a-f]{8}$/);
  });
});

// ---------------------------------------------------------------------------
// pre-commit-review.sh: review marker must survive `cd subdir`, and a stale
// marker must not silently unlock commits forever.
// ---------------------------------------------------------------------------

describe('pre-commit-review.sh marker semantics', () => {
  const HOOK = path.join(SOURCE_HOOKS, 'pre-commit-review.sh');
  const COMMON = path.join(SOURCE_HOOKS, 'lib/common.sh');
  const COMMIT_CMD = ['git', 'commit'].join(' ');

  const runCommit = (cwd: string) =>
    spawnSync('bash', [HOOK], {
      input: JSON.stringify({ tool_input: { command: `${COMMIT_CMD} -m x`, cwd } }),
      encoding: 'utf-8',
    });

  const markerFor = (cwd: string) => {
    const hash = spawnSync(
      'bash',
      ['-c', '. "$1"; repo_root_hash "$2"', '_', COMMON, cwd],
      { encoding: 'utf-8' },
    ).stdout.trim();
    // The hook hardcodes /tmp for the marker (not os.tmpdir(), which is /var/folders on macOS).
    return `/tmp/.claude-review-done-${hash}`;
  };

  it('blocks a commit when no review marker exists', () => {
    const repo = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-repo-'));
    spawnSync('git', ['-C', repo, 'init', '-q']);
    const m = markerFor(repo);
    fs.rmSync(m, { force: true });
    expect(runCommit(repo).status).toBe(2);
  });

  it('a marker set at the repo root unblocks a commit issued from a subdir', () => {
    const repo = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-repo-'));
    spawnSync('git', ['-C', repo, 'init', '-q']);
    const sub = path.join(repo, 'sub');
    fs.mkdirSync(sub);
    fs.writeFileSync(markerFor(sub), '');
    try {
      expect(runCommit(sub).status).toBe(0);
    } finally {
      fs.rmSync(markerFor(sub), { force: true });
    }
  });

  const runRaw = (command: string, repo: string) =>
    spawnSync('bash', [HOOK], {
      input: JSON.stringify({ tool_input: { command, cwd: repo } }),
      encoding: 'utf-8',
    });

  it('ignores the phrase inside a QUOTED heredoc body — that is a file being written', () => {
    const repo = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-repo-'));
    spawnSync('git', ['-C', repo, 'init', '-q']);
    fs.rmSync(markerFor(repo), { force: true });
    const writingDocs = `cat > notes.md <<'EOF'\nstep 3: ${COMMIT_CMD} -m x\nEOF`;
    expect(runRaw(writingDocs, repo).status).toBe(0);
  });

  // An UNQUOTED heredoc still expands $(...) in its body, so stripping it would
  // let `cat > n.md <<EOF` + `$(git commit)` run the commit while looking like
  // documentation. Only quoted delimiters are inert enough to strip.
  it('blocks command substitution hidden in an UNQUOTED heredoc body', () => {
    const repo = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-repo-'));
    spawnSync('git', ['-C', repo, 'init', '-q']);
    fs.rmSync(markerFor(repo), { force: true });
    const smuggled = `cat > notes.md <<EOF\n$(${COMMIT_CMD} -m pwned)\nEOF`;
    expect(runRaw(smuggled, repo).status).toBe(2);
  });

  it('blocks a commit from a path that is not a git repo', () => {
    const nogit = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-nogit-'));
    expect(runCommit(nogit).status).toBe(2);
  });

  // Negative tests for the two bugs found on 2026-09-06. Each one FAILS if its
  // mechanism is deleted from the hook — a check with no failing test is
  // documentation, not enforcement.

  // Bug 1: the marker was keyed to tool_input.cwd (the SESSION's directory), so a
  // commit into another repo was gated by the session repo's marker. Observed live:
  // a fresh ai-tools marker let a context-forge commit through.
  it('gates the repo named by `cd <repo> &&`, not the session cwd', () => {
    const session = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-session-'));
    const target = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-target-'));
    spawnSync('git', ['-C', session, 'init', '-q']);
    spawnSync('git', ['-C', target, 'init', '-q']);
    // Session repo reviewed, target repo NOT reviewed → the commit must still block.
    fs.writeFileSync(markerFor(session), '');
    fs.rmSync(markerFor(target), { force: true });
    try {
      expect(runRaw(`cd ${target} && ${COMMIT_CMD} -m x`, session).status).toBe(2);
    } finally {
      fs.rmSync(markerFor(session), { force: true });
    }
  });

  it('gates the repo named by `git -C <repo>`, not the session cwd', () => {
    const session = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-session-'));
    const target = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-target-'));
    spawnSync('git', ['-C', session, 'init', '-q']);
    spawnSync('git', ['-C', target, 'init', '-q']);
    fs.writeFileSync(markerFor(session), '');
    fs.rmSync(markerFor(target), { force: true });
    try {
      expect(runRaw(`git -C ${target} commit -m x`, session).status).toBe(2);
    } finally {
      fs.rmSync(markerFor(session), { force: true });
    }
  });

  it("lets the target repo's own marker unblock a cross-repo commit", () => {
    const session = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-session-'));
    const target = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-target-'));
    spawnSync('git', ['-C', session, 'init', '-q']);
    spawnSync('git', ['-C', target, 'init', '-q']);
    fs.rmSync(markerFor(session), { force: true });
    fs.writeFileSync(markerFor(target), '');
    try {
      expect(runRaw(`cd ${target} && ${COMMIT_CMD} -m x`, session).status).toBe(0);
    } finally {
      fs.rmSync(markerFor(target), { force: true });
    }
  });

  // Raised in review 2026-09-07: taking the FIRST `cd` is a bypass. In
  // `cd reviewed && cd unreviewed && git commit` the commit runs from the second
  // repo, so gating on the first hands it a marker it never earned.
  it('takes the LAST cd in a chain, not the first', () => {
    const session = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-session-'));
    const reviewed = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-reviewed-'));
    const unreviewed = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-unreviewed-'));
    for (const r of [session, reviewed, unreviewed]) spawnSync('git', ['-C', r, 'init', '-q']);
    fs.writeFileSync(markerFor(reviewed), '');
    fs.rmSync(markerFor(unreviewed), { force: true });
    try {
      expect(
        runRaw(`cd ${reviewed} && cd ${unreviewed} && ${COMMIT_CMD} -m x`, session).status,
      ).toBe(2);
    } finally {
      fs.rmSync(markerFor(reviewed), { force: true });
    }
  });

  // Same shape for `git -C`: the -C that counts is the one attached to the commit,
  // not an earlier read-only invocation in the same chain.
  it('binds `git -C` to the invocation that actually commits', () => {
    const session = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-session-'));
    const reviewed = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-reviewed-'));
    const unreviewed = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-unreviewed-'));
    for (const r of [session, reviewed, unreviewed]) spawnSync('git', ['-C', r, 'init', '-q']);
    fs.writeFileSync(markerFor(reviewed), '');
    fs.rmSync(markerFor(unreviewed), { force: true });
    try {
      expect(
        runRaw(`git -C ${reviewed} status && git -C ${unreviewed} commit -m x`, session).status,
      ).toBe(2);
    } finally {
      fs.rmSync(markerFor(reviewed), { force: true });
    }
  });

  // Bug 1b, found live 2026-09-07: `git -C ~/repo commit` slipped through, because
  // `~` is expanded by the shell that runs the command, never by the hook's regex.
  // An unexpanded `~/...` is not absolute, so it was pasted onto the session cwd,
  // resolved to nothing, and fell back to the session repo — reintroducing bug 1.
  it('expands a leading ~ in the target path', () => {
    const session = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-session-'));
    const target = fs.mkdtempSync(path.join(os.homedir(), '.cf-target-'));
    spawnSync('git', ['-C', session, 'init', '-q']);
    spawnSync('git', ['-C', target, 'init', '-q']);
    fs.writeFileSync(markerFor(session), '');
    fs.rmSync(markerFor(target), { force: true });
    const tilde = `~/${path.relative(os.homedir(), target)}`;
    try {
      expect(runRaw(`git -C ${tilde} commit -m x`, session).status).toBe(2);
    } finally {
      fs.rmSync(markerFor(session), { force: true });
      fs.rmSync(target, { recursive: true, force: true });
    }
  });

  // Bug 2: the hook advertised `SKIP_REVIEW=1 git commit` and then read
  // ${SKIP_REVIEW} from its OWN environment. A PreToolUse hook is a separate
  // process spawned before the command, so the prefix never arrived — the
  // documented bypass did nothing at all.
  it('honours the documented SKIP_REVIEW=1 command prefix', () => {
    const repo = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-repo-'));
    spawnSync('git', ['-C', repo, 'init', '-q']);
    fs.rmSync(markerFor(repo), { force: true });
    expect(runRaw(`SKIP_REVIEW=1 ${COMMIT_CMD} -m x`, repo).status).toBe(0);
  });

  it('does not treat a bare mention of SKIP_REVIEW as a bypass', () => {
    const repo = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-repo-'));
    spawnSync('git', ['-C', repo, 'init', '-q']);
    fs.rmSync(markerFor(repo), { force: true });
    expect(runRaw(`${COMMIT_CMD} -m 'note about SKIP_REVIEW=1 usage'`, repo).status).toBe(2);
  });

  it('rejects a marker older than the TTL', () => {
    const repo = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-repo-'));
    spawnSync('git', ['-C', repo, 'init', '-q']);
    const m = markerFor(repo);
    fs.writeFileSync(m, '');
    const old = new Date(Date.now() - 1000 * 60 * 60 * 24); // 24h ago
    fs.utimesSync(m, old, old);
    try {
      expect(runCommit(repo).status).toBe(2);
    } finally {
      fs.rmSync(m, { force: true });
    }
  });
});

describe('session-start.sh execution', () => {
  const HOOK = path.join(SOURCE_HOOKS, 'session-start.sh');

  it('hook file exists and is executable', () => {
    expect(fs.existsSync(HOOK), `${HOOK} not found`).toBe(true);
    const mode = fs.statSync(HOOK).mode;
    // Check owner-execute bit
    expect(mode & 0o100, 'session-start.sh is not executable').toBeGreaterThan(0);
  });

  it('exits 0 when CLAUDE_PLUGIN_ROOT is a valid directory', () => {
    const result = spawnSync('bash', [HOOK], {
      env: { ...process.env, CLAUDE_PLUGIN_ROOT: PLUGIN_ROOT },
      cwd: PLUGIN_ROOT,
      encoding: 'utf-8',
    });

    expect(
      result.status,
      `Hook exited ${result.status}. stderr: ${result.stderr}`,
    ).toBe(0);
  });

  // CI has no superpowers install and no ~/.claude.json; the developer machine
  // has both, so the test above passes locally and failed only on the runner.
  it('exits 0 on a bare HOME — nothing installed, no MCP config', () => {
    const bareHome = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-home-'));
    const result = spawnSync('bash', [HOOK], {
      env: { ...process.env, HOME: bareHome, CLAUDE_PLUGIN_ROOT: PLUGIN_ROOT },
      cwd: PLUGIN_ROOT,
      encoding: 'utf-8',
    });

    expect(
      result.status,
      `Hook exited ${result.status}. stderr: ${result.stderr}`,
    ).toBe(0);
  });

  it('outputs CONTEXTFORGE STATUS block', () => {
    const result = spawnSync('bash', [HOOK], {
      env: { ...process.env, CLAUDE_PLUGIN_ROOT: PLUGIN_ROOT },
      cwd: PLUGIN_ROOT,
      encoding: 'utf-8',
    });

    expect(result.stdout).toContain('CONTEXTFORGE STATUS');
  });

  it('exits non-zero when CLAUDE_PLUGIN_ROOT does not exist (regression: exit 127)', () => {
    // This is the exact failure mode that caused "startup hook error":
    // Claude Code sets CLAUDE_PLUGIN_ROOT to non-existent cache path.
    const result = spawnSync(
      'bash',
      ['-c', '"${CLAUDE_PLUGIN_ROOT}/hooks/session-start.sh"'],
      {
        env: { ...process.env, CLAUDE_PLUGIN_ROOT: '/nonexistent/path/context-forge/1.0.0' },
        encoding: 'utf-8',
      },
    );

    expect(result.status).not.toBe(0);
  });
});
