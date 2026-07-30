import { spawnSync } from 'child_process';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { describe, expect, it } from 'vitest';

const PLUGIN_ROOT = path.resolve(__dirname, '..');
const HOOK = path.join(PLUGIN_ROOT, 'hooks/session-start.sh');

describe('session-start.sh self-evolve surface', () => {
  it('prints a SELF-EVOLVE readiness line when signal is ready', () => {
    const diary = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-d-'));
    const lessons = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-l-'));
    const learn = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-e-'));
    fs.mkdirSync(path.join(diary, '2026', '06'), { recursive: true });
    // Enriched diaries — baseline stubs (empty decisions/worked/failed) are not signal.
    for (let i = 0; i < 6; i++)
      fs.writeFileSync(
        path.join(diary, '2026', '06', `e${i}.yaml`),
        'decisions:\n  - what: "chose X"\n    outcome: worked\n',
      );

    const r = spawnSync('bash', [HOOK], {
      cwd: PLUGIN_ROOT,
      encoding: 'utf-8',
      env: {
        ...process.env,
        CLAUDE_PLUGIN_ROOT: PLUGIN_ROOT,
        CF_DIARY_ROOT: diary,
        CF_LESSONS_ROOT: lessons,
        CF_LEARN_ROOT: learn,
        CF_EVOLVE_THRESHOLD: '5',
      },
      input: '{}',
    });
    expect(r.stdout).toContain('SELF-EVOLVE: 6 new signals — run /evolve');
  });
});
