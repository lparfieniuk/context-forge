import { spawnSync } from 'child_process';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { describe, expect, it } from 'vitest';

const PLUGIN_ROOT = path.resolve(__dirname, '..');
const HOOK = path.join(PLUGIN_ROOT, 'hooks/mcp-context-guard.sh');

function run(payload: object, stateDir: string, thresholdKb = 1): string {
  const r = spawnSync('bash', [HOOK], {
    input: JSON.stringify(payload),
    encoding: 'utf-8',
    env: { ...process.env, CF_MCP_COMPACT_KB: String(thresholdKb), CF_MCP_STATE_DIR: stateDir },
  });
  expect(r.status).toBe(0); // a PostToolUse hook must never break the tool flow
  return r.stdout;
}

function stateDir(): string {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'cf-mcpg-'));
}

const big = (n: number) => 'x'.repeat(n);

describe('mcp-context-guard.sh', () => {
  it('ignores non-MCP tools', () => {
    const out = run({ tool_name: 'Bash', tool_response: big(5000), session_id: 's1' }, stateDir());
    expect(out.trim()).toBe('');
  });

  it('stays silent while cumulative MCP output is below the threshold', () => {
    const dir = stateDir();
    const out = run({ tool_name: 'mcp__firecrawl-mcp__firecrawl_scrape', tool_response: big(400), session_id: 's2' }, dir);
    expect(out.trim()).toBe('');
  });

  it('emits a /compact nudge once cumulative MCP output crosses the threshold', () => {
    const dir = stateDir();
    const out = run(
      { tool_name: 'mcp__chrome-devtools__take_snapshot', tool_response: big(2048), session_id: 's3' },
      dir,
    );
    expect(out).toContain('additionalContext');
    expect(out).toContain('/compact');
    // Output must be valid JSON with the PostToolUse envelope.
    const parsed = JSON.parse(out);
    expect(parsed.hookSpecificOutput.hookEventName).toBe('PostToolUse');
  });

  it('accumulates across calls and nudges on the crossing call only', () => {
    const dir = stateDir();
    const p = { tool_name: 'mcp__glif__run_glif', session_id: 's4' };
    const first = run({ ...p, tool_response: big(600) }, dir);  // 600B < 1KB
    expect(first.trim()).toBe('');
    const second = run({ ...p, tool_response: big(600) }, dir); // 1200B crosses 1KB
    expect(second).toContain('/compact');
  });

  it('re-fires on each subsequent threshold multiple', () => {
    const dir = stateDir();
    const p = { tool_name: 'mcp__firecrawl-mcp__firecrawl_scrape', session_id: 's5' };
    expect(run({ ...p, tool_response: big(2048) }, dir)).toContain('/compact'); // ~2KB crosses 1KB
    expect(run({ ...p, tool_response: big(300) }, dir).trim()).toBe('');        // ~2.3KB, no new multiple
    expect(run({ ...p, tool_response: big(900) }, dir)).toContain('/compact');  // ~3.2KB crosses 3KB
  });

  it('counts object-valued tool_response payloads, not just strings', () => {
    const dir = stateDir();
    const bigObj: Record<string, string> = {};
    for (let i = 0; i < 40; i++) bigObj[`k${i}`] = big(40); // serializes well over 1KB
    const out = run(
      { tool_name: 'mcp__chrome-devtools__take_snapshot', session_id: 's6', tool_response: bigObj },
      dir,
    );
    expect(out).toContain('/compact');
  });

  it('never crashes on empty or malformed input', () => {
    const r = spawnSync('bash', [HOOK], { input: '', encoding: 'utf-8' });
    expect(r.status).toBe(0);
    expect(r.stdout.trim()).toBe('');
  });
});
