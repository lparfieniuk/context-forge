import { spawnSync } from 'child_process';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { describe, expect, it } from 'vitest';

const PLUGIN_ROOT = path.resolve(__dirname, '..');
const SCRIPT = path.join(PLUGIN_ROOT, 'core/scripts/tools/quality-score.sh');

function run(root: string) {
  return spawnSync('bash', [SCRIPT, '--plugin-root', root], { encoding: 'utf-8' });
}

function scaffold(): string {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-qs-'));
  fs.mkdirSync(path.join(root, 'core/rules'), { recursive: true });
  fs.mkdirSync(path.join(root, 'core/skills/good-skill'), { recursive: true });

  // A rule that passes all 7 dimensions.
  fs.writeFileSync(path.join(root, 'core/rules/900-cf-good.md'), [
    '# Good Rule',
    '',
    '## SYSTEM CONSTRAINTS',
    'ALWAYS do the right thing. NEVER do the wrong thing. BANNED: nonsense.',
    'ALWAYS verify. NEVER assume. ALWAYS check.',
    '',
    '## Few-shot example',
    '**Input:** x  **Reasoning:** y  **Output:** z',
    '',
    '## Validation gate',
    '- [ ] checked?',
    '',
  ].join('\n'));
  fs.writeFileSync(path.join(root, 'core/rules/900-cf-good.yaml'), 'id: good\n');

  // A rule that fails several dimensions: no gate, no few-shot, soft language, no yaml.
  fs.writeFileSync(path.join(root, 'core/rules/901-cf-bad.md'), [
    '# Bad Rule',
    '',
    '## SYSTEM CONSTRAINTS',
    'You should probably consider maybe doing this. It might help.',
    '',
    '## Some Section',
    'prose',
    '',
  ].join('\n'));

  // A skill that passes all skill dimensions.
  fs.writeFileSync(path.join(root, 'core/skills/good-skill/SKILL.md'), [
    '---',
    'name: good-skill',
    'description: >',
    '  Does a thing.',
    '  <example>',
    '  user: "/good-skill"',
    '  assistant: "done"',
    '  </example>',
    'model: haiku',
    '---',
    '',
    '## What This Does',
    'A thing.',
    '',
    '## Constraints',
    'NEVER break.',
    '',
  ].join('\n'));

  return root;
}

describe('quality-score.sh', () => {
  it('emits a TSV header and one row per rule and skill', () => {
    const root = scaffold();
    const r = run(root);
    expect(r.status).toBe(0);
    const lines = r.stdout.trim().split('\n');
    expect(lines[0]).toBe('kind\tfile\tscore\tpassed\ttotal\tmissing');
    const rows = lines.slice(1).filter(l => l.includes('\t'));
    // 2 rules + 1 skill = 3 scored rows (aggregate line has no leading kind col).
    const scored = rows.filter(l => /^(rule|skill)\t/.test(l));
    expect(scored.length).toBe(3);
  });

  it('scores a complete rule 1.00 (7/7) and a deficient rule below 0.6', () => {
    const root = scaffold();
    const r = run(root);
    const rows = r.stdout.trim().split('\n');
    const good = rows.find(l => l.includes('900-cf-good.md'))!.split('\t');
    const bad = rows.find(l => l.includes('901-cf-bad.md'))!.split('\t');
    expect(good[2]).toBe('1.00');
    expect(good[3]).toBe('7');
    expect(good[4]).toBe('7');
    // Bad rule misses: few-shot, gate, yaml, soft-language, (hard density) -> well under 0.6
    expect(parseFloat(bad[2])).toBeLessThan(0.6);
    expect(bad[5]).toContain('gate');
  });

  it('scores the complete skill 1.00 against the skill dimension set', () => {
    const root = scaffold();
    const r = run(root);
    const rows = r.stdout.trim().split('\n');
    const skill = rows.find(l => /^skill\t/.test(l) && l.includes('good-skill'))!.split('\t');
    expect(skill[2]).toBe('1.00');
    expect(skill[3]).toBe(skill[4]); // passed === total
  });

  it('prints an aggregate average line', () => {
    const root = scaffold();
    const r = run(root);
    expect(r.stdout).toMatch(/^average\t/m);
  });
});
