import { spawnSync } from 'child_process';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { afterEach, describe, expect, it } from 'vitest';

const ROOT = path.resolve(__dirname, '..');
const LOOKUP = path.join(ROOT, 'core/scripts/tools/shadow-lookup.sh');
const CONTRACT = path.join(ROOT, 'core/skills/shadow-lookup/contract.sh');
const temporary: string[] = [];

function repo(files: Record<string, string>) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-small-lookup-'));
  temporary.push(dir);
  expect(spawnSync('git', ['init', '-q', dir]).status).toBe(0);
  for (const [name, content] of Object.entries(files)) {
    fs.mkdirSync(path.dirname(path.join(dir, name)), { recursive: true });
    fs.writeFileSync(path.join(dir, name), content);
  }
  return dir;
}

function lookup(cwd: string, ...args: string[]) {
  return spawnSync('bash', [LOOKUP, ...args], { cwd, encoding: 'utf8' });
}

afterEach(() => temporary.splice(0).forEach(dir => fs.rmSync(dir, { recursive: true, force: true })));

describe('small-project text lookup', () => {
  it('finds literal occurrences from a subdirectory without creating an index', () => {
    const dir = repo({ 'src/a space.ts': 'export const price$ = 1;', 'test/a.ts': 'price$;', 'src/unrelated.ts': 'price = 0;' });
    const result = lookup(path.join(dir, 'src'), '--symbol', 'price$', '--text');
    expect(result.status, result.stderr).toBe(0);
    const rows = result.stdout.trim().split('\n').sort();
    expect(rows).toEqual([
      `price$\ttext-match\tsrc/a space.ts\t${path.basename(dir)}`,
      `price$\ttext-match\ttest/a.ts\t${path.basename(dir)}`,
    ]);
    expect(result.stderr).toContain('not declarations');
    expect(fs.existsSync(path.join(dir, '.claude'))).toBe(false);
    expect(fs.existsSync(path.join(dir, '.cursor'))).toBe(false);
    const sample = path.join(dir, 'result.tsv');
    fs.writeFileSync(sample, result.stdout);
    expect(spawnSync('bash', [CONTRACT, sample], { encoding: 'utf8' }).status).toBe(0);
  });

  it('excludes ignored dependencies from matches and the size limit', () => {
    const files: Record<string, string> = { '.gitignore': 'node_modules/\n', 'src/a.ts': 'alpha' };
    for (let i = 0; i < 35; i++) files[`node_modules/lib/${i}.ts`] = 'alpha';
    const result = lookup(repo(files), '--text', '--symbol', 'alpha');
    expect(result.status, result.stderr).toBe(0);
    expect(result.stdout.trim().split('\n')).toHaveLength(1);
    expect(result.stdout).not.toContain('node_modules');
  });

  it.each([0, 29, 30])('enforces the small-project boundary at %i files', count => {
    const files = Object.fromEntries(Array.from({ length: count }, (_, i) => [`src/${i}.ts`, 'alpha']));
    const result = lookup(repo(files), '--text', '--symbol', 'alpha');
    expect(result.status).toBe(count === 29 ? 0 : 1);
    if (count !== 29) expect(result.stdout).toBe('');
    if (count === 30) expect(result.stderr).toContain('30');
  });

  it('reports no match without inventing a declaration or creating files', () => {
    const dir = repo({ 'src/a.py': 'def beta(): pass' });
    const result = lookup(dir, '--text', '--symbol', 'alpha');
    expect(result.status).toBe(1);
    expect(result.stdout).toBe('');
    expect(result.stderr).toContain('No text matches');
  });

  it('does not reinterpret a kind filter or a different repo as text search', () => {
    const dir = repo({ 'src/a.ts': 'alpha' });
    for (const args of [['--kind', 'class'], ['--repo', 'another-repo']]) {
      const result = lookup(dir, '--text', '--symbol', 'alpha', ...args);
      expect(result.status).toBe(1);
      expect(result.stdout).toBe('');
    }
  });

  it('rejects missing flag values and TSV-breaking names without partial rows', () => {
    const dir = repo({ 'src/a\tfile.ts': 'alpha' });
    for (const args of [['--symbol'], ['--symbol', '--text'], ['--symbol', 'alpha', '--text']]) {
      const result = lookup(dir, ...args);
      expect(result.status).toBe(1);
      expect(result.stdout).toBe('');
    }
  });

  it('keeps the default missing-manifest result distinct from text matches', () => {
    const result = lookup(repo({ 'src/a.ts': 'alpha' }), '--symbol', 'alpha');
    expect(result.status).toBe(1);
    expect(result.stdout).not.toContain('\ttext-match\t');
    expect(result.stdout + result.stderr).toContain('--text');
  });

  it('fails before emitting an oversized TSV result', () => {
    const files = Object.fromEntries(Array.from({ length: 29 }, (_, i) => [`src/${'a'.repeat(150)}${i}.ts`, 'alpha']));
    const result = lookup(repo(files), '--text', '--symbol', 'alpha');
    expect(result.status).toBe(1);
    expect(result.stdout).toBe('');
    expect(result.stderr).toContain('3000 bytes');
  });

  it('honours .gitignore outside a git repository', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-small-nogit-'));
    temporary.push(dir);
    const files: Record<string, string> = { '.gitignore': 'node_modules/\n', 'src/a.ts': 'alpha' };
    for (let i = 0; i < 35; i++) files[`node_modules/pkg/f${i}.js`] = 'alpha';
    for (const [name, content] of Object.entries(files)) {
      fs.mkdirSync(path.dirname(path.join(dir, name)), { recursive: true });
      fs.writeFileSync(path.join(dir, name), content);
    }
    const result = lookup(dir, '--symbol', 'alpha', '--text');
    expect(result.status, result.stderr).toBe(0);
    expect(result.stdout.trim().split('\n')).toEqual([`alpha\ttext-match\tsrc/a.ts\t${path.basename(dir)}`]);
  });

  it('preserves ripgrep errors instead of reporting an empty search', () => {
    const realRg = spawnSync('sh', ['-c', 'command -v rg'], { encoding: 'utf8' }).stdout.trim();
    const shim = `#!/bin/sh\nif [ "$1" = "--files" ]; then exec "${realRg}" "$@"; fi\necho search-failed >&2\nexit 2\n`;
    const dir = repo({ 'src/a.ts': 'alpha', 'bin/rg': shim });
    fs.chmodSync(path.join(dir, 'bin/rg'), 0o755);
    const result = spawnSync('bash', [LOOKUP, '--text', '--symbol', 'alpha'], {
      cwd: dir, encoding: 'utf8', env: { ...process.env, PATH: `${dir}/bin:${process.env.PATH}` },
    });
    expect(result.status).toBe(2);
    expect(result.stdout).toBe('');
    expect(result.stderr).toContain('search-failed');
  });
});
