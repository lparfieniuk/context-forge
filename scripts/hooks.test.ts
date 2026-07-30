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

  it('blocks a commit from a path that is not a git repo', () => {
    const nogit = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-nogit-'));
    expect(runCommit(nogit).status).toBe(2);
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
