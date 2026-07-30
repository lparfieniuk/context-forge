import { spawnSync } from 'child_process';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { describe, expect, it } from 'vitest';

const PLUGIN_ROOT = path.resolve(__dirname, '..');
const SCRIPT = path.join(PLUGIN_ROOT, 'core/scripts/tools/session-digest.sh');

function git(cwd: string, ...args: string[]) {
  return spawnSync('git', args, { cwd, encoding: 'utf-8' });
}

function initRepo(): string {
  const repo = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-digest-'));
  git(repo, 'init', '-q');
  git(repo, 'config', 'user.email', 't@t');
  git(repo, 'config', 'user.name', 't');
  fs.writeFileSync(path.join(repo, 'a.txt'), 'one\n');
  git(repo, 'add', '-A');
  git(repo, 'commit', '-qm', 'init');
  return repo;
}

function run(cwd: string): string {
  const r = spawnSync('bash', [SCRIPT], { cwd, encoding: 'utf-8' });
  expect(r.status).toBe(0);
  return r.stdout;
}

describe('session-digest.sh', () => {
  it('reports changed / staged / untracked counts for the working tree', () => {
    const repo = initRepo();
    fs.appendFileSync(path.join(repo, 'a.txt'), 'two\n');      // unstaged change
    fs.writeFileSync(path.join(repo, 'b.txt'), 'new\n');
    git(repo, 'add', 'b.txt');                                  // staged
    fs.writeFileSync(path.join(repo, 'c.txt'), 'untracked\n'); // untracked

    const out = run(repo);
    expect(out).toMatch(/changed:\s*1/);
    expect(out).toMatch(/staged:\s*1/);
    expect(out).toMatch(/untracked:\s*1/);
  });

  it('always includes a confidence gate reminder', () => {
    const repo = initRepo();
    expect(run(repo)).toMatch(/gate:/);
  });

  it('shows the last commit short hash and subject', () => {
    const repo = initRepo();
    expect(run(repo)).toMatch(/last:\s*[0-9a-f]{7,}\s+init/);
  });

  it('reports ahead/behind against a configured upstream', () => {
    const repo = initRepo();
    const branch = git(repo, 'rev-parse', '--abbrev-ref', 'HEAD').stdout.trim();
    // Real bare remote so upstream tracking is set up the normal way.
    const remote = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-remote-'));
    git(remote, 'init', '--bare', '-q');
    git(repo, 'remote', 'add', 'origin', remote);
    git(repo, 'push', '-u', '-q', 'origin', branch);
    fs.appendFileSync(path.join(repo, 'a.txt'), 'more\n');
    git(repo, 'commit', '-aqm', 'second'); // now 1 ahead, 0 behind

    expect(run(repo)).toMatch(/sync:\s*ahead 1, behind 0/);
  });

  it('degrades gracefully outside a git repository', () => {
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-nogit-'));
    const r = spawnSync('bash', [SCRIPT], { cwd: tmp, encoding: 'utf-8' });
    expect(r.status).toBe(0);
    expect(r.stdout).toMatch(/not a git repo/i);
  });
});
