/**
 * firecrawl-budget.test.ts — calls run without a prompt, are estimated and logged;
 * malformed/uncapped calls and floor breaches are denied; unknown credits ask.
 */
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { spawnSync } from 'child_process';

const HOOK = path.resolve(__dirname, '..', 'hooks', 'firecrawl-budget.sh');
let dir: string;

// HOME points at an empty dir so no API key is found and no network call is made.
function run(tool: string, input: object | string) {
  const r = spawnSync('bash', [HOOK], {
    input: typeof input === 'string' ? input : JSON.stringify({ tool_name: `mcp__firecrawl-mcp__${tool}`, tool_input: input }),
    encoding: 'utf-8',
    env: { ...process.env, HOME: dir, FIRECRAWL_API_KEY: '', CF_FIRECRAWL_DIR: dir, CF_FIRECRAWL_FLOOR: '50' },
  });
  expect(r.status).toBe(0);
  const o = r.stdout.trim() ? JSON.parse(r.stdout).hookSpecificOutput : null;
  return { decision: o ? o.permissionDecision : 'pass', reason: o?.permissionDecisionReason ?? '' };
}
const seed = (remaining: number, fetched = Date.now() / 1000) =>
  fs.writeFileSync(path.join(dir, 'firecrawl-credits.json'), JSON.stringify({ fetched, remaining, plan: 1000 }));
const state = () => JSON.parse(fs.readFileSync(path.join(dir, 'firecrawl-credits.json'), 'utf-8'));

beforeEach(() => { dir = fs.mkdtempSync(path.join(os.tmpdir(), 'fc-budget-')); });
afterEach(() => fs.rmSync(dir, { recursive: true, force: true }));

describe('firecrawl-budget.sh', () => {
  it.each(['firecrawl_map', 'firecrawl_credit_usage', 'firecrawl_check_crawl_status', 'firecrawl_agent_status',
    'firecrawl_interact_stop', 'firecrawl_find_tools', 'firecrawl_feedback', 'firecrawl_search_feedback',
    'firecrawl_monitor_list', 'firecrawl_monitor_get', 'firecrawl_monitor_checks', 'firecrawl_monitor_check',
    'firecrawl_monitor_delete'])('free %s passes silently', (tool) => expect(run(tool, {}).decision).toBe('pass'));

  it.each([
    ['firecrawl_scrape', { url: 'u', formats: ['markdown'] }, 1],
    ['firecrawl_scrape', { url: 'u', formats: ['json'] }, 5],
    ['firecrawl_search', { query: 'q' }, 2],
    ['firecrawl_search', { query: 'q', limit: 20 }, 4],
    ['firecrawl_search', { query: 'q', limit: 5, scrapeOptions: { formats: ['markdown'] } }, 7],
    ['firecrawl_crawl', { url: 'u', limit: 5 }, 5],
  ])('allows %s %j, decrements %i credits', (tool, input, cost) => {
    seed(500);
    const r = run(tool, input);
    expect(r.decision).toBe('allow');
    expect(r.reason).toContain(`${500 - cost}/1000 left`);
    expect(state().remaining).toBe(500 - cost);
  });

  it('allows unpriced tools with an unknown estimate', () => {
    seed(500);
    expect(run('firecrawl_agent', { prompt: 'p' }).reason).toContain('~? credits');
  });

  it('asks when remaining credits are unknown (no key, no state)', () =>
    expect(run('firecrawl_crawl', { url: 'u', limit: 100000 }).decision).toBe('ask'));

  it('asks when the state file is corrupt and no key exists', () => {
    fs.writeFileSync(path.join(dir, 'firecrawl-credits.json'), '{oops');
    expect(run('firecrawl_scrape', { url: 'u' }).decision).toBe('ask');
  });

  it.each([
    ['firecrawl_crawl', { url: 'u' }],
    ['firecrawl_crawl', { url: 'u', limit: -1000 }],
    ['firecrawl_crawl', { url: 'u', limit: 0.5 }],
    ['firecrawl_search', { query: 'q', limit: 0 }],
    ['firecrawl_scrape', { url: 'u', formats: 'json' }],
    ['firecrawl_scrape', { url: 'u', formats: [5, 'json'] }],
  ])('denies malformed or uncapped %s %j without touching credits', (tool, input) => {
    seed(500);
    expect(run(tool, input).decision).toBe('deny');
    expect(state().remaining).toBe(500);
  });

  it('keeps the API fetch time on local decrements, so the TTL still expires', () => {
    const fetched = Date.now() / 1000 - 200;
    seed(500, fetched);
    run('firecrawl_scrape', { url: 'u' });
    expect(state().fetched).toBeCloseTo(fetched, 3);
  });

  it('denies a call that would cross the floor', () => {
    seed(52);
    expect(run('firecrawl_search', { query: 'q' }).decision).toBe('allow');   // 52 - 2 = 50
    expect(run('firecrawl_search', { query: 'q' }).decision).toBe('deny');    // 50 - 2 < 50
  });

  it('logs every paid call and counts them', () => {
    seed(500);
    run('firecrawl_scrape', { url: 'u' });
    const r = run('firecrawl_scrape', { url: 'u' });
    expect(r.reason).toContain('2 paid calls today');
    expect(fs.readFileSync(path.join(dir, 'firecrawl-usage.tsv'), 'utf-8').trim().split('\n')).toHaveLength(2);
  });

  it('asks, never passes, on garbage input', () => expect(run('', 'not json').decision).toBe('ask'));

  it('asks on a missing tool name', () => expect(run('', JSON.stringify({ tool_input: {} })).decision).toBe('ask'));
});
