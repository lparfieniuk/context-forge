/**
 * bump-version.test.ts — the release writer touches every version claim and cuts the CHANGELOG.
 */
import { describe, it, expect } from 'vitest';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { spawnSync } from 'child_process';

const SRC = path.resolve(__dirname, '..', 'core', 'scripts', 'tools', 'bump-version.sh');

function fixture(unreleased: string): string {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-bump-'));
  const w = (rel: string, body: string) => {
    fs.mkdirSync(path.dirname(path.join(root, rel)), { recursive: true });
    fs.writeFileSync(path.join(root, rel), body);
  };
  w('core/scripts/tools/bump-version.sh', fs.readFileSync(SRC, 'utf-8'));
  const field = '{\n  "version": "1.3.0"\n}\n';
  w('.claude-plugin/plugin.json', field);
  w('.claude-plugin/marketplace.json', field);
  w('.cursor-plugin/plugin.json', field);
  w('package.json', field);
  w('package-lock.json', '{\n  "version": "1.3.0",\n  "packages": {\n    "": {\n      "version": "1.3.0"\n    },\n    "x": {\n      "version": "1.3.0"\n    }\n  }\n}\n');
  w('README.md', '![v](https://img.shields.io/badge/version-1.3.0-blue)\n');
  w('CLAUDE.md', '**Version:** 1.3.0\n');
  w('CHANGELOG.md', `# Changelog\n\n## [Unreleased]\n${unreleased}\n## [1.3.0] - 2026-09-05\n`);
  return root;
}

const run = (root: string, ...args: string[]) =>
  spawnSync('bash', [path.join(root, 'core/scripts/tools/bump-version.sh'), ...args], { encoding: 'utf-8' });

describe('bump-version.sh', () => {
  it('writes the version everywhere and cuts the CHANGELOG', () => {
    const root = fixture('\n### Added\n\n- thing\n');
    const r = run(root, '1.4.0', '--date', '2026-10-15');
    expect(r.status).toBe(0);
    for (const rel of ['.claude-plugin/plugin.json', '.claude-plugin/marketplace.json', '.cursor-plugin/plugin.json', 'package.json', 'README.md', 'CLAUDE.md']) {
      const t = fs.readFileSync(path.join(root, rel), 'utf-8');
      expect(t, rel).toContain('1.4.0');
      expect(t, rel).not.toContain('1.3.0');
    }
    const lock = fs.readFileSync(path.join(root, 'package-lock.json'), 'utf-8');
    expect(lock.match(/1\.4\.0/g)).toHaveLength(2); // root entries only, dependency "x" untouched
    expect(fs.readFileSync(path.join(root, 'CHANGELOG.md'), 'utf-8'))
      .toContain('## [Unreleased]\n\n## [1.4.0] - 2026-10-15\n\n### Added');
  });

  it('refuses an empty [Unreleased] and a non-newer version', () => {
    expect(run(fixture('\n'), '1.4.0').status).not.toBe(0);
    expect(run(fixture('\n- x\n'), '1.3.0').status).not.toBe(0);
  });

  it('writes nothing when one file lacks its version claim', () => {
    const root = fixture('\n- x\n');
    fs.writeFileSync(path.join(root, 'README.md'), 'no badge here\n');
    expect(run(root, '1.4.0').status).not.toBe(0);
    expect(fs.readFileSync(path.join(root, 'package.json'), 'utf-8')).toContain('1.3.0');
    expect(fs.readFileSync(path.join(root, 'CHANGELOG.md'), 'utf-8')).not.toContain('[1.4.0]');
  });
});
