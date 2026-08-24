/**
 * replay-and-contracts.test.ts — proofs for the two incident-to-gate mechanisms.
 *
 * 1. Output contracts (idea: schema contracts as a gate, not prose). A skill
 *    declaring `output_contract` in skill.yaml must ship an executable validator
 *    whose conforming sample passes AND whose empty input fails. A validator
 *    that accepts anything is decoration, so the negative case is asserted too.
 *
 * 2. Failure replay (idea: every recorded incident becomes a regression case).
 *    failure-replay.sh classifies a rule-004 ledger and scaffolds a DRAFT
 *    cf-bench case under tasks/_drafts/ — a directory the matrix glob never
 *    reads, so an unfinished case can neither run nor silently pass.
 */

import { spawnSync } from 'child_process';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { describe, expect, it } from 'vitest';

const PLUGIN_ROOT = path.resolve(__dirname, '..');
const SURFACE = path.join(PLUGIN_ROOT, 'core/scripts/tools/audit-plugin-surface.sh');
const REPLAY = path.join(PLUGIN_ROOT, 'core/scripts/tools/failure-replay.sh');

function makeTempCopy(): string {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'context-forge-contract-'));
  fs.cpSync(PLUGIN_ROOT, dir, {
    recursive: true,
    filter: source => !source.includes(`${path.sep}node_modules${path.sep}`),
  });
  return dir;
}

function declaredContracts(): Array<{ id: string; contract: string }> {
  const out: Array<{ id: string; contract: string }> = [];
  for (const dir of fs.readdirSync(path.join(PLUGIN_ROOT, 'core/skills'))) {
    const yamlPath = path.join(PLUGIN_ROOT, 'core/skills', dir, 'skill.yaml');
    if (!fs.existsSync(yamlPath)) continue;
    const m = /^output_contract:\s*(.+)$/m.exec(fs.readFileSync(yamlPath, 'utf-8'));
    if (m) out.push({ id: dir, contract: m[1].trim().replace(/"/g, '') });
  }
  return out;
}

describe('output contracts', () => {
  it('at least the three envelope skills declare contracts', () => {
    const ids = declaredContracts().map(c => c.id);
    for (const required of ['safe-exec', 'log-analyzer', 'shadow-lookup']) {
      expect(ids, `${required} should declare output_contract`).toContain(required);
    }
  });

  it.each(declaredContracts())('$id validator accepts its sample, rejects empty input', ({ id, contract }) => {
    const validator = path.join(PLUGIN_ROOT, contract);
    const sample = path.join(PLUGIN_ROOT, `core/skills/${id}/contract-sample.txt`);

    expect(fs.existsSync(validator), 'validator exists').toBe(true);
    const stat = fs.statSync(validator);
    // Executed via `bash` everywhere, so the exec bit is convention, not function.
    expect(stat.isFile()).toBe(true);

    const positive = spawnSync('bash', [validator, sample], { encoding: 'utf-8' });
    expect(positive.status, `sample must pass (${positive.stderr})`).toBe(0);

    const negative = spawnSync('bash', [validator, '/dev/null'], { encoding: 'utf-8' });
    expect(negative.status, 'empty input must FAIL — a validator that accepts anything validates nothing').not.toBe(0);
  });

  it('surface audit fails when a declared contract loses its sample', () => {
    const dir = makeTempCopy();
    fs.rmSync(path.join(dir, 'core/skills/safe-exec/contract-sample.txt'));

    const r = spawnSync('bash', [SURFACE, '--plugin-root', dir], { encoding: 'utf-8' });
    expect(r.status).toBe(1);
    expect(r.stdout).toMatch(/\[safe-exec\] contract-sample\.txt missing/);
  });

  it('surface audit fails when a validator accepts everything', () => {
    const dir = makeTempCopy();
    fs.writeFileSync(path.join(dir, 'core/skills/shadow-lookup/contract.sh'), '#!/usr/bin/env true\n');
    fs.chmodSync(path.join(dir, 'core/skills/shadow-lookup/contract.sh'), 0o755);

    const r = spawnSync('bash', [SURFACE, '--plugin-root', dir], { encoding: 'utf-8' });
    expect(r.status).toBe(1);
    expect(r.stdout).toMatch(/accepts empty input/);
  });
});

// ---------------------------------------------------------------------------
// failure-replay.sh
// ---------------------------------------------------------------------------

function writeLedger(dir: string, body: string): string {
  const p = path.join(dir, 'a1b2c3d4-barrel-export-missing.yaml');
  fs.writeFileSync(p, body, 'utf-8');
  return p;
}

const BENCH_LEDGER = `execution_context:
  goal: "npm run build after adding cancelSubscription"
  tool: "Terminal (npm run build)"
error_trajectory: |
  billing.facade.ts:10:14 - error TS2305: Module has no exported member 'BillingFacade'.
agent_reflection: "Assumed barrel export existed; failed to verify index.ts."
`;

describe('failure-replay.sh', () => {
  let benchDir: string;

  function makeFakeBench(): string {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'cfbench-fake-'));
    fs.mkdirSync(path.join(dir, 'runner'), { recursive: true });
    fs.writeFileSync(path.join(dir, 'runner/run-task.sh'), '#!/usr/bin/env bash\n');
    fs.chmodSync(path.join(dir, 'runner/run-task.sh'), 0o755);
    return dir;
  }

  it('scaffolds an inert DRAFT case for a bench-classified ledger', () => {
    benchDir = makeFakeBench();
    const ledger = writeLedger(benchDir, BENCH_LEDGER);

    const r = spawnSync('bash', [REPLAY, '--ledger', ledger, '--bench-root', benchDir], { encoding: 'utf-8' });
    expect(r.status, r.stderr).toBe(0);
    expect(r.stdout).toMatch(/verdict: REPLAYABLE/);

    const taskPath = path.join(benchDir, 'tasks/_drafts/replay-barrel-export-missing.task');
    const fixture = path.join(benchDir, 'fixtures/replay-barrel-export-missing');

    expect(fs.existsSync(taskPath)).toBe(true);
    expect(fs.readFileSync(taskPath, 'utf-8')).toContain('npm run build after adding cancelSubscription');
    expect(fs.existsSync(fixture)).toBe(true);

    // The stub check must fail (exit != 0) so a promoted-by-accident case cannot pass.
    const stubRun = spawnSync('bash', [path.join(fixture, 'check.sh')], { encoding: 'utf-8' });
    expect(stubRun.status).not.toBe(0);

    // Ledger context travels with the fixture — no transcription by hand.
    const ledgerMd = fs.readFileSync(path.join(fixture, 'LEDGER.md'), 'utf-8');
    expect(ledgerMd).toContain("error TS2305");
    expect(ledgerMd).toContain('Assumed barrel export existed');

    // Drafts are invisible to the matrix glob (tasks/*.task is non-recursive).
    const globView = fs.readdirSync(path.join(benchDir, 'tasks')).filter(f => f.endsWith('.task'));
    expect(globView).toEqual([]);
  });

  it('creates nothing for a process-only failure', () => {
    const bench = makeFakeBench();
    const ledger = writeLedger(
      bench,
      `execution_context:
  goal: "escalate cross-currency invoices"
  tool: "human decision"
error_trajectory: |
  stakeholder contradiction on contractor inclusion
agent_reflection: "contradiction resolved by engineering judgement"
`,
    );
    const r = spawnSync('bash', [REPLAY, '--ledger', ledger, '--bench-root', bench], { encoding: 'utf-8' });
    expect(r.status).toBe(0);
    expect(r.stdout).toMatch(/NOT REPLAYABLE/);
    expect(fs.existsSync(path.join(bench, 'tasks/_drafts'))).toBe(false);
    expect(fs.existsSync(path.join(bench, 'fixtures'))).toBe(false);
  });

  it('fails loudly on a missing ledger or non-bench root', () => {
    const missingLedger = spawnSync('bash', [REPLAY, '--ledger', '/nonexistent/x.yaml'], { encoding: 'utf-8' });
    expect(missingLedger.status).not.toBe(0);

    const emptyDir = fs.mkdtempSync(path.join(os.tmpdir(), 'not-a-bench-'));
    const ledger = writeLedger(emptyDir, BENCH_LEDGER);
    const notBench = spawnSync('bash', [REPLAY, '--ledger', ledger, '--bench-root', emptyDir], { encoding: 'utf-8' });
    expect(notBench.status).toBe(1);
    expect(notBench.stderr).toMatch(/does not look like cf-bench|bench root not found/);
  });
});
