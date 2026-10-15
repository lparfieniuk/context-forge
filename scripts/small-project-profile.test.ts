import { spawnSync } from 'node:child_process';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { afterEach, describe, expect, it } from 'vitest';

const root = path.resolve(__dirname, '..');
const temporary: string[] = [];
function temp(): string {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-small-profile-'));
  temporary.push(dir);
  return dir;
}
function emit(args: string[], pluginRoot = root) {
  return spawnSync(path.join(root, 'node_modules/.bin/ts-node'), [
    path.join(root, 'scripts/emit-agents-md.ts'), '--plugin-root', pluginRoot, ...args,
  ], { encoding: 'utf8', timeout: 15000 });
}
function copyInputs(): string {
  const dir = temp();
  for (const name of ['core', 'harnesses', 'package.json']) {
    fs.cpSync(path.join(root, name), path.join(dir, name), { recursive: true });
  }
  return dir;
}
afterEach(() => temporary.splice(0).forEach(dir => fs.rmSync(dir, { recursive: true, force: true })));

describe('small-project instruction profile', () => {
  it('emits a bounded, deterministic payload without the full catalogs', () => {
    const dir = temp();
    const out = path.join(dir, 'AGENTS.md');
    const args = ['--harness', 'opencode', '--profile', 'small-project', '--out', out];
    expect(emit(args).status).toBe(0);
    const text = fs.readFileSync(out, 'utf8');
    expect(Buffer.byteLength(text)).toBeLessThanOrEqual(2400);
    expect(text).toContain('small-project');
    expect(text).toContain('Preserve');
    expect(text).toMatch(/verify/i);
    for (const excluded of ['Always-on doctrine', 'On-demand rule index', 'Skills & scripts', 'anthropic/', '<CF_PLUGIN_ROOT>']) {
      expect(text).not.toContain(excluded);
    }
    expect(emit(args).status).toBe(0);
    expect(fs.readFileSync(out, 'utf8')).toBe(text);
  });

  it('keeps the default full output byte-identical to explicit full selection', () => {
    const dir = temp();
    const before = path.join(dir, 'before.md');
    const after = path.join(dir, 'after.md');
    expect(emit(['--harness', 'opencode', '--out', before]).status).toBe(0);
    expect(emit(['--harness', 'opencode', '--profile', 'full', '--out', after]).status).toBe(0);
    expect(fs.readFileSync(after, 'utf8')).toBe(fs.readFileSync(before, 'utf8'));
  });

  it.each([['--profile', 'missing'], ['--profile'], ['--profile='], ['--profile', '--out', 'lost.md']])(
    'rejects invalid profile arguments %j without overwriting output', (...profileArgs) => {
      const out = path.join(temp(), 'keep.md');
      fs.writeFileSync(out, 'user instructions');
      const result = emit(['--harness', 'opencode', '--out', out, ...profileArgs]);
      expect(result.status).not.toBe(0);
      expect(fs.readFileSync(out, 'utf8')).toBe('user instructions');
    },
  );

  it('rejects a missing source without overwriting output', () => {
    const dir = copyInputs();
    fs.rmSync(path.join(dir, 'core/profiles/small-project.md'), { force: true });
    const out = path.join(dir, 'keep.md');
    fs.writeFileSync(out, 'user instructions');
    expect(emit(['--harness', 'opencode', '--profile', 'small-project', '--out', out], dir).status).not.toBe(0);
    expect(fs.readFileSync(out, 'utf8')).toBe('user instructions');
  });

  it('rejects over-budget UTF-8 output before touching its destination', () => {
    const dir = copyInputs();
    fs.mkdirSync(path.join(dir, 'core/profiles'), { recursive: true });
    // 1200 characters but 3600 bytes: a character-count guard is insufficient.
    fs.writeFileSync(path.join(dir, 'core/profiles/small-project.md'), '界'.repeat(1200));
    const out = path.join(dir, 'keep.md');
    fs.writeFileSync(out, 'user instructions');
    const result = emit(['--harness', 'opencode', '--profile', 'small-project', '--out', out], dir);
    expect(result.status).not.toBe(0);
    expect(result.stderr).toContain('byte budget');
    expect(fs.readFileSync(out, 'utf8')).toBe('user instructions');
  });

  it('documents profile selection in --help without generating a file', () => {
    const out = path.join(temp(), 'absent.md');
    const result = emit(['--help', '--out', out]);
    expect(result.status).toBe(0);
    expect(result.stdout).toContain('--profile');
    expect(result.stdout).toContain('small-project');
    expect(fs.existsSync(out)).toBe(false);
  });

  it('includes explicit project notes without changing the input or revealing its path', () => {
    const dir = temp();
    const notes = path.join(dir, 'project facts.md');
    const out = path.join(dir, 'AGENTS.md');
    const content = '# Project facts\n\n- Run `node --test`.\n- Source data is read-only.\n';
    fs.writeFileSync(notes, content);
    const result = emit(['--harness', 'opencode', '--profile', 'small-project', '--project-notes', notes, '--out', out]);
    expect(result.status).toBe(0);
    expect(fs.readFileSync(out, 'utf8')).toContain(content.trim());
    expect(fs.readFileSync(out, 'utf8')).not.toContain(notes);
    expect(fs.readFileSync(notes, 'utf8')).toBe(content);
  });

  it.each(['missing', 'empty', 'oversized'])('rejects %s project notes before replacing output', kind => {
    const dir = temp();
    const notes = path.join(dir, 'facts.md');
    const out = path.join(dir, 'keep.md');
    fs.writeFileSync(out, 'user instructions');
    if (kind === 'empty') fs.writeFileSync(notes, ' \n');
    if (kind === 'oversized') fs.writeFileSync(notes, '界'.repeat(600));
    const result = emit(['--harness', 'opencode', '--profile', 'small-project', '--project-notes', notes, '--out', out]);
    expect(result.status).not.toBe(0);
    expect(fs.readFileSync(out, 'utf8')).toBe('user instructions');
    if (kind === 'oversized') expect(result.stderr).toContain('byte budget');
  });
});
