import { spawnSync } from 'child_process';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { describe, expect, it } from 'vitest';

const PLUGIN_ROOT = path.resolve(__dirname, '..');
const SAFE_EXEC = path.join(PLUGIN_ROOT, 'core/scripts/tools/safe-exec.sh');
const CHECK_PARITY = path.join(PLUGIN_ROOT, 'core/scripts/tools/check-parity.sh');
const AUDIT_DOC_CLAIMS = path.join(PLUGIN_ROOT, 'core/scripts/tools/audit-doc-claims.sh');

function makeTempPluginCopy(): string {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'context-forge-parity-'));
  fs.cpSync(PLUGIN_ROOT, dir, {
    recursive: true,
    filter: source => !source.includes(`${path.sep}node_modules${path.sep}`),
  });
  return dir;
}

describe('safe-exec CLI', () => {
  it('compresses huge single-line output by byte threshold', () => {
    const cwd = fs.mkdtempSync(path.join(os.tmpdir(), 'context-forge-safe-exec-'));
    const result = spawnSync(
      'bash',
      [SAFE_EXEC, '--intent', 'test huge output', '--', 'python3', '-c', 'print("x"*6000)'],
      {
        cwd,
        encoding: 'utf-8',
      },
    );

    expect(result.status).toBe(0);
    expect(result.stdout).toContain('<bytes>');
    expect(result.stdout).toContain('<compressed>true</compressed>');
    expect(result.stdout.length).toBeLessThan(2000);
  });
});

describe('check-parity CLI', () => {
  it('detects missing and stale cursor rules from core index', () => {
    const tempPlugin = makeTempPluginCopy();
    const staleRule = path.join(tempPlugin, '.cursor/rules/001-cf-token-efficiency.mdc');
    const missingRule = path.join(tempPlugin, '.cursor/rules/002-cf-shadow-index.mdc');

    fs.appendFileSync(staleRule, '\nSTALE CONTENT\n', 'utf-8');
    fs.rmSync(missingRule);

    const result = spawnSync('bash', [CHECK_PARITY, '--plugin-root', tempPlugin], {
      cwd: PLUGIN_ROOT,
      encoding: 'utf-8',
    });

    expect(result.status).toBe(0);
    expect(result.stdout).toContain('DRIFT:');
    expect(result.stdout).toContain('NOT_INSTALLED:');
    expect(result.stdout).toContain('001-cf-token-efficiency.mdc');
    expect(result.stdout).toContain('002-cf-shadow-index.mdc');
  });

  it('detects drift, missing, and orphan claude rules from core index', () => {
    const tempPlugin = makeTempPluginCopy();
    const staleRule = path.join(tempPlugin, '.claude/rules/cf-token-efficiency.md');
    // cf-shadow-index moved to on-demand and is no longer installed here;
    // any still-always-on rule serves as the "missing" fixture.
    const missingRule = path.join(tempPlugin, '.claude/rules/cf-circuit-breaker.md');
    const orphanRule = path.join(tempPlugin, '.claude/rules/cf-orphan.md');

    fs.appendFileSync(staleRule, '\nSTALE CONTENT\n', 'utf-8');
    fs.rmSync(missingRule);
    fs.writeFileSync(orphanRule, '# Orphan\n', 'utf-8');

    const result = spawnSync('bash', [CHECK_PARITY, '--plugin-root', tempPlugin], {
      cwd: PLUGIN_ROOT,
      encoding: 'utf-8',
    });

    expect(result.status).toBe(0);
    expect(result.stdout).toContain('DRIFT:');
    expect(result.stdout).toContain('NOT_INSTALLED:');
    expect(result.stdout).toContain('ORPHAN:');
    expect(result.stdout).toContain('cf-token-efficiency.md');
    expect(result.stdout).toContain('cf-circuit-breaker.md');
    expect(result.stdout).toContain('cf-orphan.md');
  });
});

describe('audit-doc-claims CLI', () => {
  it('ignores stale counts inside a historical CHANGELOG section but still catches mismatches under Unreleased', () => {
    const tempPlugin = makeTempPluginCopy();
    const changelogPath = path.join(tempPlugin, 'CHANGELOG.md');

    // Stale count "99 skills" inside a historical released section must be
    // ignored (it is a frozen record of what shipped). The same stale claim
    // under [Unreleased] must still be caught against the current index count.
    const changelog = [
      '# Changelog',
      '',
      '## [Unreleased]',
      '',
      '### Added',
      '',
      '- **99 skills** across four categories',
      '',
      '## [1.0.0] - 2026-04-14',
      '',
      '### Added',
      '',
      '- **99 skills** across four categories',
      '',
    ].join('\n');
    fs.writeFileSync(changelogPath, changelog, 'utf-8');

    const result = spawnSync('bash', [AUDIT_DOC_CLAIMS, '--plugin-root', tempPlugin], {
      cwd: PLUGIN_ROOT,
      encoding: 'utf-8',
    });

    expect(result.status).toBe(1);
    expect(result.stdout).toContain('final: FAIL');

    const failureLines = result.stdout
      .split('\n')
      .filter(line => line.includes('CHANGELOG.md') && line.includes('skills count'));
    expect(failureLines).toHaveLength(1);
    expect(failureLines[0]).toContain('CHANGELOG.md:7:');
  });
});
