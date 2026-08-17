/**
 * gates.test.ts — Failure proofs for the three gates that had none.
 *
 * A gate that has only ever been observed passing is not a gate; it is a green
 * light with no bulb behind it. `check-parity.sh`, `audit-runtime-artifacts.sh`
 * and `mcp-context-guard.sh` already carry failure tests (tooling.test.ts,
 * audit-runtime-artifacts.test.ts, mcp-context-guard.test.ts). These three did
 * not:
 *
 *   - hooks/enforce-rg.sh            — shipped exempting every piped command,
 *                                      i.e. nearly every real grep
 *   - hooks/enforce-tier-routing.sh  — inert until route-to-tier.sh's plugin
 *                                      root was fixed; it never blocked anything
 *   - core/scripts/tools/audit-plugin-surface.sh
 *
 * Each test below breaks something specific and asserts the gate reacts, then
 * asserts it stays quiet on the matching legitimate case.
 */

import { spawnSync } from 'child_process';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { describe, expect, it } from 'vitest';

const PLUGIN_ROOT = path.resolve(__dirname, '..');
const ENFORCE_RG = path.join(PLUGIN_ROOT, 'hooks/enforce-rg.sh');
const ENFORCE_TIER = path.join(PLUGIN_ROOT, 'hooks/enforce-tier-routing.sh');
const AUDIT_SURFACE = path.join(PLUGIN_ROOT, 'core/scripts/tools/audit-plugin-surface.sh');

function runHook(script: string, payload: unknown) {
  return spawnSync('bash', [script], {
    input: JSON.stringify(payload),
    encoding: 'utf-8',
    cwd: PLUGIN_ROOT,
  });
}

const bash = (command: string) => runHook(ENFORCE_RG, { tool_input: { command } });
const task = (prompt: string) => runHook(ENFORCE_TIER, { tool_input: { prompt } });

function makeTempPluginCopy(): string {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'context-forge-gates-'));
  fs.cpSync(PLUGIN_ROOT, dir, {
    recursive: true,
    filter: source => !source.includes(`${path.sep}node_modules${path.sep}`),
  });
  return dir;
}

describe('enforce-rg.sh', () => {
  it('blocks a bare grep with exit 2 and names the replacement', () => {
    const r = bash('grep foo file.txt');
    expect(r.status).toBe(2);
    expect(r.stderr).toContain('[BLOCKED]');
    expect(r.stderr).toContain('rg');
  });

  it('blocks grep as the head of a pipeline (regression: the pipe exemption)', () => {
    // `grep p f | head` is the shape most greps actually take. The hook used to
    // allow any command containing a pipe, so this sailed through and the ban
    // was decorative.
    expect(bash('grep foo file.txt | head').status).toBe(2);
  });

  it('blocks grep as a downstream pipeline stage', () => {
    expect(bash('cat file.txt | grep foo').status).toBe(2);
  });

  it('blocks recursive grep over a directory', () => {
    expect(bash('grep -r foo src/').status).toBe(2);
  });

  it('allows the `grep -v grep` process-listing idiom', () => {
    expect(bash('ps aux | grep -v grep').status).toBe(0);
  });

  it('allows rg, including piped', () => {
    expect(bash('rg foo src/').status).toBe(0);
    expect(bash('rg foo src/ | wc -l').status).toBe(0);
  });

  it('never crashes on empty or malformed input', () => {
    expect(runHook(ENFORCE_RG, {}).status).toBe(0);
    const r = spawnSync('bash', [ENFORCE_RG], { input: 'not json', encoding: 'utf-8' });
    expect(r.status).toBe(0);
  });
});

describe('enforce-tier-routing.sh', () => {
  it('blocks a Task() whose work a Tier 1 script already does', () => {
    const r = task('extract signatures from src/auth/auth.service.ts');
    expect(r.status).toBe(2);
    expect(r.stderr).toContain('[BLOCKED]');
    expect(r.stderr).toContain('USE INSTEAD');
  });

  it('allows a Task() that genuinely needs a model (architecture work)', () => {
    expect(task('design the new billing subsystem architecture').status).toBe(0);
  });

  it('allows a multi-file refactor (Tier 2 territory)', () => {
    expect(task('refactor AuthService across 6 files to add tenantId').status).toBe(0);
  });

  it('fails open when route-to-tier.sh is unreachable', () => {
    // A routing script that cannot be found must not block work. Point
    // CLAUDE_PLUGIN_ROOT at an empty dir and confirm the call is allowed.
    const empty = fs.mkdtempSync(path.join(os.tmpdir(), 'context-forge-noroute-'));
    const r = spawnSync('bash', [ENFORCE_TIER], {
      input: JSON.stringify({ tool_input: { prompt: 'extract signatures from a.ts' } }),
      encoding: 'utf-8',
      env: { ...process.env, CLAUDE_PLUGIN_ROOT: empty },
    });
    expect(r.status).toBe(0);
  });

  it('never crashes on empty input', () => {
    expect(runHook(ENFORCE_TIER, {}).status).toBe(0);
  });
});

describe('extract-signatures.sh', () => {
  const EXTRACT = path.join(PLUGIN_ROOT, 'core/scripts/tools/extract-signatures.sh');
  const run = (file: string) =>
    spawnSync('bash', [EXTRACT, '--file', file], { encoding: 'utf-8', cwd: PLUGIN_ROOT });

  function tempSource(lines: string[]): string {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'context-forge-sig-'));
    const file = path.join(dir, 'sample.ts');
    fs.writeFileSync(file, lines.join('\n'), 'utf-8');
    return file;
  }

  it('never emits more bytes than the source it replaces', () => {
    // The whole point of the tool. It shipped emitting three overlapping
    // sections, and on a real 3456-byte module produced 4213 bytes — more
    // expensive than the Read it was meant to avoid.
    const body: string[] = ['// dense module'];
    for (let i = 0; i < 60; i++) body.push(`export function fn${i}(a: number, b: string): void { /* ${'x'.repeat(20)} */ }`);
    const file = tempSource(body);
    const r = run(file);
    expect(r.status).toBe(0);
    expect(Buffer.byteLength(r.stdout)).toBeLessThan(fs.statSync(file).size);
  });

  it('lists each declaration once, not once per section', () => {
    const body = ['// header'];
    for (let i = 0; i < 60; i++) {
      body.push(`export function uniqueName${i}(): number {`, `  const acc = ${i} * 2;`, '  return acc;', '}');
    }
    const r = run(tempSource(body));
    const hits = r.stdout.split('\n').filter((l) => l.includes('uniqueName7(')).length;
    expect(hits).toBe(1);
  });

  it('omits the class-members section for a file with no class', () => {
    const body = ['// header'];
    for (let i = 0; i < 60; i++) {
      body.push(`export function value${i}(): number {`, `  return ${i};`, '}');
    }
    const r = run(tempSource(body));
    expect(r.stdout).not.toContain('Public class members');
  });

  it('keeps the class-members section when a class is present', () => {
    const body = ['export class Service {'];
    for (let i = 0; i < 60; i++) body.push(`  method${i}(): void {}`);
    body.push('}');
    const r = run(tempSource(body));
    expect(r.stdout).toContain('Public class members');
  });

  it('extracts PHP, which was claimed as supported but matched nothing', () => {
    // The pattern only ever matched `export …`, so every PHP file produced an
    // empty extraction — and a class file with no public members aborted the
    // script under `set -e` with exit 1.
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'context-forge-php-'));
    const file = path.join(dir, 'sample.php');
    const body = [
      '<?php',
      'class Billing {',
      '    public function charge(int $amount): bool { return true; }',
      '    private function secret(): void {}',
      '}',
      'function helper(string $s): string { return $s; }',
    ];
    for (let i = 0; i < 60; i++) body.push(`// filler ${i}`);
    fs.writeFileSync(file, body.join('\n'), 'utf-8');

    const r = run(file);
    expect(r.status).toBe(0);
    expect(r.stdout).toContain('class Billing');
    expect(r.stdout).toContain('function helper');
    expect(r.stdout).toContain('charge');
    expect(r.stdout).not.toContain('secret'); // private stays private
  });

  it('exits 0 on a class file whose members are all private', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'context-forge-priv-'));
    const file = path.join(dir, 'sample.php');
    const body = ['<?php', 'class Vault {'];
    for (let i = 0; i < 60; i++) body.push(`    private function h${i}(): void {}`);
    body.push('}');
    fs.writeFileSync(file, body.join('\n'), 'utf-8');
    expect(run(file).status).toBe(0);
  });

  it('reads a short file directly instead of extracting', () => {
    const r = run(tempSource(['export const a = 1;', 'export const b = 2;']));
    expect(r.stdout).toContain('reading directly');
    expect(r.stdout).toContain('export const b = 2;');
  });
});

describe('refresh-manifest.sh + shadow-lookup.sh round trip', () => {
  const REFRESH = path.join(PLUGIN_ROOT, 'core/scripts/tools/refresh-manifest.sh');
  const LOOKUP = path.join(PLUGIN_ROOT, 'core/scripts/tools/shadow-lookup.sh');

  function makeRepo(files: Record<string, string>): string {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'cfrepo-'));
    spawnSync('git', ['init', '-q', '.'], { cwd: dir });
    for (const [rel, body] of Object.entries(files)) {
      const full = path.join(dir, rel);
      fs.mkdirSync(path.dirname(full), { recursive: true });
      fs.writeFileSync(full, body, 'utf-8');
    }
    return dir;
  }

  it('indexes a repo that has no config entry and no .claude dir', () => {
    // Both were hard failures: the config was the only source of targets, and a
    // missing .claude/ exited 1 — the foreign-repo case the tool exists for.
    const dir = makeRepo({ 'src/a.ts': 'export function alpha(): number { return 1; }\n' });
    const r = spawnSync('bash', [REFRESH], { cwd: dir, encoding: 'utf-8' });
    expect(r.status).toBe(0);
    const found = spawnSync('bash', [LOOKUP, '--symbol', 'alpha'], { cwd: dir, encoding: 'utf-8' });
    expect(found.status).toBe(0);
    expect(found.stdout.trim().split('\t')).toEqual(['alpha', 'function', 'src/a.ts', path.basename(dir)]);
  });

  it('survives a path containing the :CF field marker', () => {
    // The awk parser split on the FIRST ":CF"; a directory legally named with
    // that sequence truncated the path and glued its tail onto the kind.
    const dir = makeRepo({
      'src/we:CFird/mod.ts': 'export function alpha(): number { return 1; }\n',
    });
    spawnSync('bash', [REFRESH], { cwd: dir, encoding: 'utf-8' });
    const found = spawnSync('bash', [LOOKUP, '--symbol', 'alpha'], { cwd: dir, encoding: 'utf-8' });
    expect(found.stdout.trim().split('\t')[2]).toBe('src/we:CFird/mod.ts');
  });

  it('exits 1 and says so when the symbol is absent', () => {
    const dir = makeRepo({ 'src/a.ts': 'export function alpha(): number { return 1; }\n' });
    spawnSync('bash', [REFRESH], { cwd: dir, encoding: 'utf-8' });
    const miss = spawnSync('bash', [LOOKUP, '--symbol', 'nope'], { cwd: dir, encoding: 'utf-8' });
    expect(miss.status).toBe(1);
    expect(miss.stdout).toContain('not found');
  });

  it('stamps a timestamp the session-start freshness parser can read', () => {
    const dir = makeRepo({ 'src/a.ts': 'export function alpha(): number { return 1; }\n' });
    spawnSync('bash', [REFRESH], { cwd: dir, encoding: 'utf-8' });
    const manifest = fs.readFileSync(
      path.join(dir, '.claude/shadow', path.basename(dir), '_manifest.lightweight.yaml'),
      'utf-8',
    );
    // Raw epoch here made every manifest parse as epoch 0 and report BROKEN.
    expect(manifest).toMatch(/generated: "\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z"/);
    expect(manifest).toMatch(/total_symbols: 1/);
  });
});

describe('tool scripts expose --help', () => {
  // 30 of 32 did. `task-init.sh` answered "Unknown arg: --help" (exit 1) and
  // `evolve-apply.sh` treated the flag as a proposal id and went looking for
  // `pending/--help.yaml` (exit 2). A flag that is silently read as data is the
  // same defect class as a documented flag the parser never had.
  const toolsDir = path.join(PLUGIN_ROOT, 'core/scripts/tools');
  const scripts = fs.readdirSync(toolsDir).filter((f) => f.endsWith('.sh'));

  it('finds the tool scripts (guards against a vacuous scan)', () => {
    expect(scripts.length).toBeGreaterThan(20);
  });

  it.each(scripts)('%s --help exits 0 and prints usage', (script) => {
    const r = spawnSync('bash', [path.join(toolsDir, script), '--help'], {
      encoding: 'utf-8',
      cwd: PLUGIN_ROOT,
      timeout: 20000,
    });
    expect(r.status).toBe(0);
    expect(r.stdout.toLowerCase()).toContain('usage');
  });
});

describe('skill docs vs script argument parsers', () => {
  // Every flag a SKILL.md advertises must exist in the script it points at.
  // Three did not: extract-signatures documented `--kind` and `--repo`,
  // refresh-manifest `--force`, pack-context `--exclude`. All four are rejected
  // with "ERROR: Unknown flag" and exit 1 — the doc was the only place they
  // ever existed, and nothing compared the two.
  const skillsDir = path.join(PLUGIN_ROOT, 'core/skills');
  const toolsDir = path.join(PLUGIN_ROOT, 'core/scripts/tools');

  const cases = fs
    .readdirSync(skillsDir)
    .map((skill) => ({ skill, md: path.join(skillsDir, skill, 'SKILL.md') }))
    .filter(({ md }) => fs.existsSync(md))
    .flatMap(({ skill, md }) => {
      const body = fs.readFileSync(md, 'utf-8');
      // Which tool scripts does this skill actually invoke?
      const scripts = [...new Set([...body.matchAll(/tools\/([a-z0-9-]+)\.sh/g)].map((m) => m[1]))]
        .filter((name) => fs.existsSync(path.join(toolsDir, `${name}.sh`)));
      if (scripts.length !== 1) return []; // ambiguous or none — nothing to compare
      // Only count a flag as *documented* when it heads a bullet — the shape a
      // flag reference list uses. Prose that merely names a flag (including a
      // sentence saying one does not exist) is not a claim about the parser.
      const flags = [
        ...new Set([...body.matchAll(/^\s*[-*]\s+`(--[a-z][a-z-]*)/gm)].map((m) => m[1])),
      ];
      return flags.length ? [{ skill, script: scripts[0], flags }] : [];
    });

  it('finds skills that document flags (guards against the scan silently matching nothing)', () => {
    expect(cases.length).toBeGreaterThan(2);
  });

  it.each(cases)('$skill documents only flags $script accepts', ({ script, flags }) => {
    const src = fs.readFileSync(path.join(toolsDir, `${script}.sh`), 'utf-8');
    // Case labels alternate: `--log|--log-file)` accepts both.
    const accepted = new Set(
      [...src.matchAll(/^\s*(--[a-z][a-z-|]*)\)/gm)].flatMap((m) => m[1].split('|')),
    );
    const phantom = flags.filter((f) => !accepted.has(f));
    expect(phantom).toEqual([]);
  });
});

describe('audit-plugin-surface.sh', () => {
  const run = (root: string) =>
    spawnSync('bash', [AUDIT_SURFACE, '--plugin-root', root], {
      encoding: 'utf-8',
      cwd: PLUGIN_ROOT,
    });

  it('passes on the real tree', () => {
    const r = run(PLUGIN_ROOT);
    expect(r.stdout).toContain('- surface: PASS');
    expect(r.stdout).toContain('- final: PASS');
  });

  it('fails when hooks.json points at a hook file that does not exist', () => {
    const temp = makeTempPluginCopy();
    fs.rmSync(path.join(temp, 'hooks/enforce-rg.sh'));
    const r = run(temp);
    expect(r.stdout).toContain('- final: FAIL');
    expect(r.stdout).toContain('enforce-rg.sh');
  });

  it('fails when a required script drops out of core/scripts/_index.yaml', () => {
    const temp = makeTempPluginCopy();
    const idx = path.join(temp, 'core/scripts/_index.yaml');
    fs.writeFileSync(
      idx,
      fs.readFileSync(idx, 'utf-8').replace('  - id: audit-doc-claims', '  - id: audit-doc-claims-RENAMED'),
      'utf-8',
    );
    const r = run(temp);
    expect(r.stdout).toContain('- final: FAIL');
    expect(r.stdout).toContain('audit-doc-claims');
  });

  it('fails when a doc claims a different agent count than the index', () => {
    const temp = makeTempPluginCopy();
    const readme = path.join(temp, 'README.md');
    fs.appendFileSync(readme, '\nShips with **7 agents** for good measure.\n', 'utf-8');
    const r = run(temp);
    expect(r.stdout).toContain('- final: FAIL');
    expect(r.stdout).toContain('agent count claim 7');
  });

  it('fails when package.json loses the audit script entry', () => {
    const temp = makeTempPluginCopy();
    const pkg = path.join(temp, 'package.json');
    fs.writeFileSync(pkg, fs.readFileSync(pkg, 'utf-8').replace('"test:audit"', '"test:audit-DISABLED"'), 'utf-8');
    const r = run(temp);
    expect(r.stdout).toContain('- final: FAIL');
    expect(r.stdout).toContain('test:audit');
  });
});
