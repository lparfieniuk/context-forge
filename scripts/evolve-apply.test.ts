import { spawnSync } from 'child_process';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { describe, expect, it } from 'vitest';

const PLUGIN_ROOT = path.resolve(__dirname, '..');
const SCRIPT = path.join(PLUGIN_ROOT, 'core/scripts/tools/evolve-apply.sh');

function initRepo(): string {
  const repo = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-apply-'));
  spawnSync('git', ['init', '-q'], { cwd: repo });
  spawnSync('git', ['config', 'user.email', 't@t'], { cwd: repo });
  spawnSync('git', ['config', 'user.name', 't'], { cwd: repo });
  fs.writeFileSync(path.join(repo, 'target.txt'), 'line one\n');
  spawnSync('git', ['add', '-A'], { cwd: repo });
  spawnSync('git', ['commit', '-qm', 'init'], { cwd: repo });
  return repo;
}

function writeProposal(
  repo: string,
  id: string,
  patch: string,
  meta: { verdict?: string; target?: string; confidence?: string } = {},
) {
  const dir = path.join(repo, '.claude/evolve/pending');
  fs.mkdirSync(dir, { recursive: true });
  const header = [
    `id: ${id}`,
    meta.verdict ? `verdict: ${meta.verdict}` : null,
    meta.target ? `target: ${meta.target}` : null,
    meta.confidence ? `confidence: ${meta.confidence}` : null,
  ].filter(Boolean).join('\n');
  fs.writeFileSync(
    path.join(dir, `${id}.yaml`),
    `${header}\npatch_text: |\n${patch.split('\n').map(l => '  ' + l).join('\n')}\n`,
  );
}

function readLedger(repo: string): string[] {
  const p = path.join(repo, '.claude/evolve/ledger.tsv');
  if (!fs.existsSync(p)) return [];
  return fs.readFileSync(p, 'utf-8').trim().split('\n');
}

describe('evolve-apply.sh', () => {
  it('applies a valid patch and moves the proposal to applied/', () => {
    const repo = initRepo();
    const patch = [
      '--- a/target.txt',
      '+++ b/target.txt',
      '@@ -1 +1,2 @@',
      ' line one',
      '+line two',
      '',
    ].join('\n');
    writeProposal(repo, 'abc12345', patch, { verdict: 'ADD', target: '015-cf-mcp-tools', confidence: '0.82' });

    const r = spawnSync('bash', [SCRIPT, 'abc12345', '--skip-audit'], { cwd: repo, encoding: 'utf-8' });
    expect(r.status).toBe(0);
    expect(r.stdout).toContain('[EVOLVE-APPLY] abc12345 applied');
    expect(fs.readFileSync(path.join(repo, 'target.txt'), 'utf-8')).toContain('line two');
    expect(fs.existsSync(path.join(repo, '.claude/evolve/applied/abc12345.yaml'))).toBe(true);
    expect(fs.existsSync(path.join(repo, '.claude/evolve/pending/abc12345.yaml'))).toBe(false);

    // Ledger: header + one applied row carrying the proposal metadata.
    const ledger = readLedger(repo);
    expect(ledger[0]).toBe('ts\tid\tverdict\ttarget\tstatus\tconfidence');
    const cols = ledger[1].split('\t');
    expect(cols[1]).toBe('abc12345');
    expect(cols[2]).toBe('ADD');
    expect(cols[3]).toBe('015-cf-mcp-tools');
    expect(cols[4]).toBe('applied');
    expect(cols[5]).toBe('0.82');
  });

  it('reverts and exits non-zero when the patch does not apply', () => {
    const repo = initRepo();
    const badPatch = [
      '--- a/target.txt',
      '+++ b/target.txt',
      '@@ -1 +1,2 @@',
      ' WRONG CONTEXT',
      '+line two',
      '',
    ].join('\n');
    writeProposal(repo, 'bad00001', badPatch, { verdict: 'MODIFY', target: '003-cf-tier-routing', confidence: '0.55' });

    const r = spawnSync('bash', [SCRIPT, 'bad00001', '--skip-audit'], { cwd: repo, encoding: 'utf-8' });
    expect(r.status).not.toBe(0);
    expect(r.stdout + r.stderr).toContain('reverted');
    expect(fs.readFileSync(path.join(repo, 'target.txt'), 'utf-8')).toBe('line one\n');
    expect(fs.existsSync(path.join(repo, '.claude/evolve/pending/bad00001.yaml'))).toBe(true);

    // A patch that never applied is logged as reverted-patch (autoresearch "crash").
    const cols = readLedger(repo)[1].split('\t');
    expect(cols[1]).toBe('bad00001');
    expect(cols[4]).toBe('reverted-patch');
  });

  it('logs a row with default dashes when proposal omits verdict/target/confidence', () => {
    const repo = initRepo();
    const patch = [
      '--- a/target.txt',
      '+++ b/target.txt',
      '@@ -1 +1,2 @@',
      ' line one',
      '+line two',
      '',
    ].join('\n');
    writeProposal(repo, 'def67890', patch); // no meta

    const r = spawnSync('bash', [SCRIPT, 'def67890', '--skip-audit'], { cwd: repo, encoding: 'utf-8' });
    expect(r.status).toBe(0);
    const cols = readLedger(repo)[1].split('\t');
    expect(cols[2]).toBe('-');
    expect(cols[3]).toBe('-');
    expect(cols[4]).toBe('applied');
    expect(cols[5]).toBe('-');
  });
});
