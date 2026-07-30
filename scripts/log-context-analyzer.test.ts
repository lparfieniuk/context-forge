import { spawnSync, type SpawnSyncReturns } from 'child_process';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { describe, it, expect } from 'vitest';

const PLUGIN_ROOT = path.resolve(__dirname, '..');
const SCRIPT = path.join(PLUGIN_ROOT, 'core/scripts/tools/log-context-analyzer.sh');

function writeTempLog(content: string): string {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'log-context-analyzer-'));
  const file = path.join(dir, 'failure.log');
  fs.writeFileSync(file, content, 'utf-8');
  return file;
}

function runAnalyzer(args: string[]): SpawnSyncReturns<string> {
  return spawnSync('bash', [SCRIPT, ...args], {
    cwd: PLUGIN_ROOT,
    encoding: 'utf-8',
  });
}

describe('log-context-analyzer CLI', () => {
  it('accepts canonical --file flag', () => {
    const logFile = writeTempLog('ERROR: build failed\n');

    const result = runAnalyzer(['--file', logFile]);

    expect(result.status).toBe(0);
    expect(result.stdout).toContain('[RCA]');
    expect(result.stdout).toContain('ERROR: build failed');
    expect(result.stdout).toContain('[END RCA]');
  });

  it('accepts --log and --log-file as file aliases', () => {
    const logFile = writeTempLog('ERROR: test failed\n');

    const logResult = runAnalyzer(['--log', logFile]);
    const logFileResult = runAnalyzer(['--log-file', logFile]);

    expect(logResult.status).toBe(0);
    expect(logResult.stdout).toContain('ERROR: test failed');
    expect(logFileResult.status).toBe(0);
    expect(logFileResult.stdout).toContain('ERROR: test failed');
  });

  it('accepts --format as a type alias', () => {
    const logFile = writeTempLog('ERROR: generic failure\n');

    const result = runAnalyzer(['--file', logFile, '--format', 'generic']);

    expect(result.status).toBe(0);
    expect(result.stdout).toContain('ERROR: generic failure');
  });

  it('extracts non-empty RCA from safe-exec observation logs', () => {
    const logFile = writeTempLog(`
<status>failed</status>
<signal>exit_code: 1</signal>
<instruction>Run npm test and summarize failures</instruction>
Failed Tests 1
scripts/hooks.test.ts > session-start.sh execution
ERROR: Hook exited 1
`);

    const result = runAnalyzer(['--file', logFile]);

    expect(result.status).toBe(0);
    expect(result.stdout).toContain('[RCA]');
    expect(result.stdout).toContain('Hook exited 1');
    expect(result.stdout).toContain('[END RCA]');
  });

  it('returns an RCA with exit 0 when no clear error is found', () => {
    const logFile = writeTempLog('All output was truncated before the interesting lines.\n');

    const result = runAnalyzer(['--file', logFile]);

    expect(result.status).toBe(0);
    expect(result.stdout).toContain('No clear error found');
  });
});
