// scripts/audit-runtime-artifacts.test.ts
import { spawnSync } from 'child_process';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { afterEach, describe, expect, it } from 'vitest';

const PLUGIN_ROOT = path.resolve(__dirname, '..');
const SCRIPT = path.join(PLUGIN_ROOT, 'core/scripts/tools/audit-runtime-artifacts.sh');

const roots: string[] = [];

function mkRepo(): string {
  const root = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'cf-ra-')));
  roots.push(root);
  for (const args of [
    ['init', '-q'],
    ['config', 'user.email', 't@t'],
    ['config', 'user.name', 't'],
  ]) {
    spawnSync('git', ['-C', root, ...args]);
  }
  fs.writeFileSync(path.join(root, '.gitignore'), '.claude/lessons/\n');
  fs.writeFileSync(path.join(root, 'README.md'), 'x\n');
  spawnSync('git', ['-C', root, 'add', '.']);
  spawnSync('git', ['-C', root, 'commit', '-qm', 'init']);
  return root;
}

function writeLedger(root: string) {
  const dir = path.join(root, '.claude/lessons/2026/07/30/ab');
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, 'ab000000-x.yaml'), 'agent_reflection: "x"\n');
}

function run(root: string) {
  return spawnSync('bash', [SCRIPT, '--plugin-root', root], { encoding: 'utf-8' });
}

afterEach(() => {
  while (roots.length) fs.rmSync(roots.pop()!, { recursive: true, force: true });
});

describe('audit-runtime-artifacts.sh', () => {
  it('passes on a clean tree', () => {
    expect(run(mkRepo()).stdout).toContain('- runtime-artifacts: PASS');
  });

  // Rule 004 mandates writing failure ledgers here; .gitignore keeps them out of
  // every commit, so the gate must not fail on a purely local one.
  it('passes when .claude/lessons exists but is gitignored', () => {
    const root = mkRepo();
    writeLedger(root);
    const res = run(root);
    expect(res.stdout).toContain('- runtime-artifacts: PASS');
    expect(res.status).toBe(0);
  });

  it('fails when .claude/lessons is actually tracked by git', () => {
    const root = mkRepo();
    fs.writeFileSync(path.join(root, '.gitignore'), '\n');
    writeLedger(root);
    spawnSync('git', ['-C', root, 'add', '-A']);
    spawnSync('git', ['-C', root, 'commit', '-qm', 'oops']);
    const res = run(root);
    expect(res.stdout).toContain('- runtime-artifacts: FAIL');
    expect(res.stdout).toContain('.claude/lessons');
    expect(res.status).toBe(1);
  });

  // The audit runs before `git add`, so a stray artifact is typically untracked at
  // exactly the moment it most needs catching. Only untracked AND ignored is exempt.
  it('fails on an untracked artifact that is not gitignored', () => {
    const root = mkRepo();
    fs.writeFileSync(path.join(root, 'observation-1.yaml'), 'x: 1\n');
    const res = run(root);
    expect(res.stdout).toContain('- runtime-artifacts: FAIL');
    expect(res.stdout).toContain('observation-1.yaml');
    expect(res.status).toBe(1);
  });

  // An unquoted ${path#$root/} treats the root as a glob, leaving `rel` absolute.
  it('flags a stray log under a root containing glob metacharacters', () => {
    const parent = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'cf-ra-g-')));
    roots.push(parent);
    const root = path.join(parent, 'we[i]rd');
    fs.mkdirSync(root);
    fs.writeFileSync(path.join(root, 'run-9.log'), 'noise\n');
    const res = run(root);
    expect(res.stdout).toContain('- runtime-artifacts: FAIL');
    expect(res.stdout).toContain('run-9.log');
  });

  // Outside a git work tree nothing is tracked, so existence is the only signal.
  it('fails on an artifact in a non-git tree', () => {
    const root = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'cf-ra-nogit-')));
    roots.push(root);
    writeLedger(root);
    expect(run(root).stdout).toContain('- runtime-artifacts: FAIL');
  });

  it('fails on a tracked stray run log', () => {
    const root = mkRepo();
    fs.writeFileSync(path.join(root, 'run-42.log'), 'noise\n');
    spawnSync('git', ['-C', root, 'add', '-f', 'run-42.log']);
    spawnSync('git', ['-C', root, 'commit', '-qm', 'log']);
    const res = run(root);
    expect(res.stdout).toContain('- runtime-artifacts: FAIL');
    expect(res.stdout).toContain('run-42.log');
  });
});
