import { spawnSync } from 'child_process';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { describe, expect, it } from 'vitest';

const PLUGIN_ROOT = path.resolve(__dirname, '..');
const HOOK = path.join(PLUGIN_ROOT, 'hooks/diary-capture.sh');

function run(diaryRoot: string, runsRoot: string, cwd: string) {
  return spawnSync('bash', [HOOK], {
    cwd,
    encoding: 'utf-8',
    env: { ...process.env, CF_DIARY_ROOT: diaryRoot, CF_RUNS_ROOT: runsRoot },
    input: '',
  });
}

describe('diary-capture.sh', () => {
  it('writes a baseline entry with required keys for a fresh session', () => {
    const diaryRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-diary-'));
    const runsRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-runs-'));
    const cwd = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-cwd-'));

    const result = run(diaryRoot, runsRoot, cwd);
    expect(result.status).toBe(0);

    const files = spawnSync('find', [diaryRoot, '-name', '*.yaml', '!', '-name', 'INDEX.yaml'], {
      encoding: 'utf-8',
    }).stdout.trim().split('\n').filter(Boolean);
    expect(files.length).toBe(1);

    const body = fs.readFileSync(files[0], 'utf-8');
    expect(body).toMatch(/^session: \d{4}-\d{2}-\d{2}-[0-9a-f]{8}$/m);
    expect(body).toContain('task_type:');
    expect(body).toContain('decisions: []');
    expect(body).toContain('worked: []');
    expect(body).toContain('signals:');

    const index = fs.readFileSync(path.join(diaryRoot, 'INDEX.yaml'), 'utf-8');
    expect(index).toContain('total_entries: 1');
    expect(index).toContain('last_processed_total: 0');
  });

  it('is idempotent — a second run does not duplicate the baseline', () => {
    const diaryRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-diary-'));
    const runsRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-runs-'));
    const cwd = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-cwd-'));

    run(diaryRoot, runsRoot, cwd);
    run(diaryRoot, runsRoot, cwd);

    const index = fs.readFileSync(path.join(diaryRoot, 'INDEX.yaml'), 'utf-8');
    expect(index).toContain('total_entries: 1');
  });

  it('preserves /diary enrichment by appending baseline keys when file exists without a session key', () => {
    const diaryRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-diary-'));
    const runsRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-runs-'));
    const cwd = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-cwd-'));

    // Simulate a /diary-created file lacking baseline keys.
    const ym = new Date();
    const dir = path.join(
      diaryRoot,
      String(ym.getFullYear()),
      String(ym.getMonth() + 1).padStart(2, '0'),
    );
    fs.mkdirSync(dir, { recursive: true });
    // Mirror the hook's session hash by calling the exact same helper it uses
    // (repo_root_hash: git-root-normalized, keyed with whoami). Shelling out to the
    // real function guarantees the test can never drift from the source of truth.
    const hash = spawnSync(
      'bash',
      ['-c', '. "$1/hooks/lib/common.sh"; repo_root_hash', '_', PLUGIN_ROOT],
      { cwd, encoding: 'utf-8' },
    ).stdout.trim();
    const dateStr = `${ym.getFullYear()}-${String(ym.getMonth() + 1).padStart(2, '0')}-${String(ym.getDate()).padStart(2, '0')}`;
    const file = path.join(dir, `${dateStr}-${hash}.yaml`);
    fs.writeFileSync(file, 'decisions:\n  - what: chose X\n    why: faster\n    outcome: worked\n');

    run(diaryRoot, runsRoot, cwd);

    const body = fs.readFileSync(file, 'utf-8');
    expect(body).toContain('chose X'); // enrichment preserved
    expect(body).toMatch(/^session: /m); // baseline appended
  });
});
