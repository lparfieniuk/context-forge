/**
 * pack-context.test.ts — guards the head+tail truncation of large files.
 *
 * Regression for: a file matched (therefore relevant) that is over the line budget
 * used to collapse to its first 30 lines, silently dropping up to 94% of its body —
 * including anything near the end (the change site is often there).
 */
import { spawnSync } from 'child_process';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { describe, expect, it } from 'vitest';

const PLUGIN_ROOT = path.resolve(__dirname, '..');
const SCRIPT = path.join(PLUGIN_ROOT, 'core/scripts/tools/pack-context.sh');

function pack(cwd: string, pattern: string, extra: string[] = []) {
  return spawnSync('bash', [SCRIPT, '--pattern', pattern, '--search-path', '.', ...extra], {
    cwd,
    encoding: 'utf-8',
  }).stdout;
}

describe('pack-context.sh large-file truncation', () => {
  it('keeps BOTH the head and the tail of an over-budget file', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-pack-'));
    const lines = ['MATCHME top sentinel', ...Array.from({ length: 600 }, (_, i) => `line ${i}`), 'MATCHME bottom sentinel'];
    fs.writeFileSync(path.join(dir, 'big.txt'), lines.join('\n') + '\n');

    const out = pack(dir, 'MATCHME');
    expect(out).toContain('MATCHME top sentinel');    // head shown
    expect(out).toContain('MATCHME bottom sentinel'); // tail shown (the old bug dropped this)
    expect(out).toMatch(/TRUNCATED: \d+ lines/);      // truncation is loud
    expect(out).toMatch(/\d+ lines elided/);          // reports the loss
  });

  it('emits a small file in full, untruncated', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-pack-'));
    fs.writeFileSync(path.join(dir, 'small.txt'), 'MATCHME unique\nb\nc\n');

    const out = pack(dir, 'MATCHME unique');
    expect(out).toContain('MATCHME unique');
    expect(out).not.toContain('TRUNCATED');
  });

  it('--max-lines widens the window', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-pack-'));
    const lines = ['MATCHME x', ...Array.from({ length: 300 }, (_, i) => `line ${i}`)];
    fs.writeFileSync(path.join(dir, 'mid.txt'), lines.join('\n') + '\n');

    // 301 lines: truncated at default 400? no — under budget. Force a low budget to truncate.
    expect(pack(dir, 'MATCHME x', ['--max-lines', '100'])).toMatch(/TRUNCATED/);
    expect(pack(dir, 'MATCHME x', ['--max-lines', '1000'])).not.toContain('TRUNCATED');
  });
});
