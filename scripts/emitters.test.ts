/**
 * emitters.test.ts — proofs for the AGENTS.md emitter and the portability gate.
 *
 * The AGENTS.md emitter is the harness-agnostic contract made executable: one
 * source of truth in core/, a capability profile per harness, and an emitted
 * artifact that must be fully resolved (no <CF_PLUGIN_ROOT>, no Claude Code
 * env var). These tests pin the contract from both sides:
 *
 *   - emit-agents-md.ts  — content completeness, determinism, placeholder
 *                          resolution, loud failure on unknown/non-family
 *                          harness profiles
 *   - audit-portability.sh — reacts when a neutral source carries a harness
 *                          env var; stays quiet on the placeholder form
 */

import { spawnSync } from 'child_process';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { describe, expect, it } from 'vitest';

const PLUGIN_ROOT = path.resolve(__dirname, '..');
const EMITTER = path.join(PLUGIN_ROOT, 'scripts/emit-agents-md.ts');
const PORTABILITY = path.join(PLUGIN_ROOT, 'core/scripts/tools/audit-portability.sh');

interface RunResult {
  status: number;
  stdout: string;
  stderr: string;
}

function runEmitter(args: string[], cwd = PLUGIN_ROOT, pluginRoot?: string): RunResult {
  const full = pluginRoot ? [...args, '--plugin-root', pluginRoot] : args;
  const r = spawnSync('npx', ['ts-node', EMITTER, ...full], { encoding: 'utf-8', cwd });
  return { status: r.status ?? 1, stdout: r.stdout ?? '', stderr: r.stderr ?? '' };
}

function runPortability(pluginRoot: string): RunResult {
  const r = spawnSync('bash', [PORTABILITY, '--plugin-root', pluginRoot], { encoding: 'utf-8' });
  return { status: r.status ?? 1, stdout: r.stdout ?? '', stderr: r.stderr ?? '' };
}

function makeTempCopy(): string {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'context-forge-emit-'));
  fs.cpSync(PLUGIN_ROOT, dir, {
    recursive: true,
    filter: source => !source.includes(`${path.sep}node_modules${path.sep}`),
  });
  return dir;
}

describe('emit-agents-md.ts', () => {
  it('emits every always-on rule body into the doctrine section', () => {
    const dir = makeTempCopy();
    const out = path.join(dir, 'dist/AGENTS.md');
    const r = runEmitter(['--harness', 'opencode', '--out', out]);
    expect(r.status).toBe(0);

    const doc = fs.readFileSync(out, 'utf-8');
    for (const id of ['Token Efficiency', 'Tier Routing', 'Circuit Breaker', 'Code Search', 'Context Budget', 'Critical Response']) {
      expect(doc).toContain(id);
    }
    // On-demand rules must NOT be inlined — they are indexed by path instead.
    expect(doc).toContain('On-demand rule index');
  });

  it('resolves every plugin-root placeholder and never leaks the Claude Code env var', () => {
    const dir = makeTempCopy();
    const out = path.join(dir, 'dist/AGENTS.md');
    const r = runEmitter(['--harness', 'opencode', '--out', out]);
    expect(r.status).toBe(0);

    const doc = fs.readFileSync(out, 'utf-8');
    expect(doc).not.toContain('<CF_PLUGIN_ROOT>');
    expect(doc).not.toContain('${CLAUDE_PLUGIN_ROOT}');
    expect(doc).toContain(path.resolve(PLUGIN_ROOT)); // absolute script paths present
  });

  it('is deterministic — two runs produce byte-identical output', () => {
    const dir = makeTempCopy();
    const outA = path.join(dir, 'dist/a.md');
    const outB = path.join(dir, 'dist/b.md');
    runEmitter(['--harness', 'opencode', '--out', outA]);
    runEmitter(['--harness', 'opencode', '--out', outB]);
    expect(fs.readFileSync(outA, 'utf-8')).toBe(fs.readFileSync(outB, 'utf-8'));
  });

  it('carries configured tier anchors verbatim and bans unset Tier 3+ by wording', () => {
    const dir = makeTempCopy();
    const out = path.join(dir, 'dist/AGENTS.md');
    runEmitter(['--harness', 'opencode', '--out', out]);

    const doc = fs.readFileSync(out, 'utf-8');
    const adaptation = doc.split(/## Harness adaptation/)[1] ?? '';
    // Configured anchors appear as written in the profile — no invention.
    expect(adaptation).toMatch(/Tier 2 model: anthropic\/claude-haiku-4-5/);
    expect(adaptation).toMatch(/Tier 3 model: anthropic\/claude-sonnet-4-5/);
    // tier3plus left null is a deliberate ban, phrased as policy, not missing config.
    expect(adaptation).toMatch(/Tier 3\+ model: not configured — Tier 3\+ escalation stays BANNED/);
  });

  it('marks genuinely unconfigured tier2/tier3 as UNSET instead of inventing an id', () => {
    const dir = makeTempCopy();
    const profilePath = path.join(dir, 'harnesses/opencode.yaml');
    fs.writeFileSync(
      profilePath,
      fs
        .readFileSync(profilePath, 'utf-8')
        .replace(/tier2: \S+/, 'tier2: null')
        .replace(/tier3: \S+$/, 'tier3: null'),
      'utf-8',
    );
    const out = path.join(dir, 'dist/AGENTS.md');
    runEmitter(['--harness', 'opencode', '--out', out], PLUGIN_ROOT, dir);

    const doc = fs.readFileSync(out, 'utf-8');
    expect(doc).toMatch(/Tier 2 model: \*\*UNSET\*\*/);
    // Doctrine quotes CC anchors verbatim (that is by design); the adaptation
    // section must NOT invent one for this harness when the profile leaves it unset.
    const adaptation = doc.split(/## Harness adaptation/)[1] ?? '';
    expect(adaptation).not.toMatch(/claude-haiku-[a-z0-9-]+/);
  });

  it('fails loudly for an unknown harness profile', () => {
    const r = runEmitter(['--harness', 'does-not-exist']);
    expect(r.status).not.toBe(0);
    expect(r.stderr).toMatch(/no such harness profile/);
  });

  it('refuses to emit a non-agents-md family profile', () => {
    const dir = makeTempCopy();
    const out = path.join(dir, 'dist/AGENTS.md');
    const r = runEmitter(['--harness', 'claude-code', '--out', out], PLUGIN_ROOT);
    expect(r.status).not.toBe(0);
    expect(r.stderr).toMatch(/family "claude-plugin", not agents-md/);
  });
});

describe('audit-portability.sh', () => {
  it('passes on the current tree and on a fresh emission', () => {
    const dir = makeTempCopy();
    runEmitter(['--harness', 'opencode', '--out', path.join(dir, 'dist/AGENTS.md')]);
    const r = runPortability(dir);
    expect(r.status).toBe(0);
    expect(r.stdout).toMatch(/STATUS: OK/);
  });

  it('reacts when a skill source carries the Claude Code env var', () => {
    const dir = makeTempCopy();
    const skill = path.join(dir, 'core/skills/safe-exec/SKILL.md');
    fs.writeFileSync(skill, fs.readFileSync(skill, 'utf-8').replace(/<CF_PLUGIN_ROOT>/g, '${CLAUDE_PLUGIN_ROOT}'), 'utf-8');

    const r = runPortability(dir);
    expect(r.status).toBe(1);
    expect(r.stdout).toMatch(/FAIL: harness env var in neutral sources/);
  });

  it('reacts when emitted AGENTS.md still holds an unresolved placeholder', () => {
    const dir = makeTempCopy();
    fs.mkdirSync(path.join(dir, 'dist'), { recursive: true });
    fs.writeFileSync(path.join(dir, 'dist/AGENTS.md'), '# x\nbash <CF_PLUGIN_ROOT>/core/scripts/tools/x.sh\n');

    const r = runPortability(dir);
    expect(r.status).toBe(1);
    expect(r.stdout).toMatch(/FAIL: dist\/AGENTS\.md contains unresolved/);
  });
});
