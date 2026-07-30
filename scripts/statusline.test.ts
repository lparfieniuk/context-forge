import { spawnSync } from 'child_process';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { describe, expect, it } from 'vitest';

const PLUGIN_ROOT = path.resolve(__dirname, '..');
const SCRIPT = path.join(PLUGIN_ROOT, 'core/scripts/tools/statusline.sh');

function run(payload: object): string {
  const r = spawnSync('bash', [SCRIPT], { input: JSON.stringify(payload), encoding: 'utf-8' });
  expect(r.status).toBe(0);
  return r.stdout;
}

describe('statusline.sh', () => {
  it('renders model, context, cache and cost on one line', () => {
    const out = run({
      model: { id: 'claude-opus-4-8', display_name: 'Opus 4.8' },
      workspace: { current_dir: '/tmp/demo-project' },
      transcript_path: '/nonexistent.jsonl',
      cost: { total_cost_usd: 0.1234 },
    });
    expect(out.split('\n').filter(Boolean).length).toBe(1); // single line
    expect(out).toContain('Opus 4.8');
    expect(out).toContain('demo-project');
    expect(out).toMatch(/ctx/);
    expect(out).toMatch(/cache/);
    expect(out).toContain('$0.12');
  });

  it('marks cache cold when the transcript is older than 5 minutes', () => {
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-sl-'));
    const transcript = path.join(tmp, 't.jsonl');
    fs.writeFileSync(transcript, '{}\n');
    // Backdate mtime by 10 minutes.
    const old = new Date(Date.now() - 10 * 60 * 1000);
    fs.utimesSync(transcript, old, old);
    const out = run({
      model: { display_name: 'Haiku' },
      workspace: { current_dir: tmp },
      transcript_path: transcript,
      cost: { total_cost_usd: 0 },
    });
    expect(out).toContain('cold');
  });

  it('marks cache warm when the transcript is fresh', () => {
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-sl-'));
    const transcript = path.join(tmp, 't.jsonl');
    fs.writeFileSync(transcript, '{}\n');
    const out = run({
      model: { display_name: 'Haiku' },
      workspace: { current_dir: tmp },
      transcript_path: transcript,
      cost: { total_cost_usd: 0 },
    });
    expect(out).toContain('warm');
  });

  it('degrades gracefully on empty/malformed input', () => {
    const r = spawnSync('bash', [SCRIPT], { input: '', encoding: 'utf-8' });
    expect(r.status).toBe(0); // never crashes the status line
    expect(r.stdout).toContain('CF');
  });
});
