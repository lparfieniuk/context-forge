// scripts/evolve-signal.test.ts
import { spawnSync } from 'child_process';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { describe, expect, it } from 'vitest';

const PLUGIN_ROOT = path.resolve(__dirname, '..');
const SCRIPT = path.join(PLUGIN_ROOT, 'core/scripts/tools/evolve-signal.sh');

function mkYaml(dir: string, n: number) {
  fs.mkdirSync(dir, { recursive: true });
  for (let i = 0; i < n; i++) fs.writeFileSync(path.join(dir, `e${i}.yaml`), 'x: 1\n');
}

// Diaries only count as signal when enriched (non-empty decisions/worked/failed).
// A baseline stub is what the SessionEnd hook writes on its own.
function mkDiaries(dir: string, enriched: number, stubs = 0) {
  fs.mkdirSync(dir, { recursive: true });
  for (let i = 0; i < enriched; i++) {
    fs.writeFileSync(
      path.join(dir, `d${i}.yaml`),
      'decisions:\n  - what: "chose X"\n    outcome: worked\nworked: []\nfailed: []\n',
    );
  }
  for (let i = 0; i < stubs; i++) {
    fs.writeFileSync(
      path.join(dir, `s${i}.yaml`),
      'decisions: []\nworked: []\nfailed: []\nsignals: [baseline, "fails:0"]\n',
    );
  }
}

function run(env: Record<string, string>) {
  return spawnSync('bash', [SCRIPT], { encoding: 'utf-8', env: { ...process.env, ...env } });
}

describe('evolve-signal.sh', () => {
  it('reports NO-SIGNAL below threshold', () => {
    const diary = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-d-'));
    const lessons = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-l-'));
    const learn = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-e-'));
    mkDiaries(diary, 2);
    fs.writeFileSync(path.join(diary, 'INDEX.yaml'), 'last_processed_total: 0\n');
    const r = run({ CF_DIARY_ROOT: diary, CF_LESSONS_ROOT: lessons, CF_LEARN_ROOT: learn, CF_EVOLVE_THRESHOLD: '5' });
    expect(r.stdout.trim()).toMatch(/^SIGNAL 2 NO-SIGNAL$/);
  });

  it('reports READY at or above threshold using the delta', () => {
    const diary = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-d-'));
    const lessons = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-l-'));
    const learn = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-e-'));
    mkDiaries(diary, 4);
    mkYaml(lessons, 3); // INDEX.yaml under diary is excluded from counts
    fs.writeFileSync(path.join(diary, 'INDEX.yaml'), 'last_processed_total: 2\n');
    const r = run({ CF_DIARY_ROOT: diary, CF_LESSONS_ROOT: lessons, CF_LEARN_ROOT: learn, CF_EVOLVE_THRESHOLD: '5' });
    // current = 4 + 3 = 7; new = 7 - 2 = 5 >= 5
    expect(r.stdout.trim()).toMatch(/^SIGNAL 5 READY$/);
  });

  it('does not count baseline diary stubs as signal', () => {
    const diary = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-d-'));
    const lessons = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-l-'));
    const learn = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-e-'));
    mkDiaries(diary, 1, 20); // 1 enriched + 20 SessionEnd stubs
    const r = run({ CF_DIARY_ROOT: diary, CF_LESSONS_ROOT: lessons, CF_LEARN_ROOT: learn, CF_EVOLVE_THRESHOLD: '5' });
    // stubs carry no information; only the enriched diary counts
    expect(r.stdout.trim()).toMatch(/^SIGNAL 1 NO-SIGNAL$/);
  });

  it('does not count a bare key with no item as enriched', () => {
    const diary = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-d-'));
    const lessons = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-l-'));
    const learn = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-e-'));
    fs.mkdirSync(diary, { recursive: true });
    // /diary creates `decisions:` as an empty block before appending an item;
    // an interrupted call must not read as signal.
    fs.writeFileSync(path.join(diary, 'bare.yaml'), 'decisions:\n');
    // A blank line must not let the match run into the next key's content.
    fs.writeFileSync(path.join(diary, 'blank.yaml'), 'decisions:\n\n  worked: y\n');
    mkDiaries(diary, 1);
    const r = run({ CF_DIARY_ROOT: diary, CF_LESSONS_ROOT: lessons, CF_LEARN_ROOT: learn, CF_EVOLVE_THRESHOLD: '5' });
    expect(r.stdout.trim()).toMatch(/^SIGNAL 1 NO-SIGNAL$/);
  });

  it('treats a missing INDEX as last_processed_total=0', () => {
    const diary = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-d-'));
    const lessons = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-l-'));
    const learn = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-e-'));
    mkDiaries(diary, 6);
    const r = run({ CF_DIARY_ROOT: diary, CF_LESSONS_ROOT: lessons, CF_LEARN_ROOT: learn, CF_EVOLVE_THRESHOLD: '5' });
    expect(r.stdout.trim()).toMatch(/^SIGNAL 6 READY$/);
  });
});
