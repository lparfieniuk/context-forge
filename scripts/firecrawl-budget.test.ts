/**
 * firecrawl-budget.test.ts — cheap Firecrawl calls pass silently, credit-scaling ones get "ask".
 */
import { describe, it, expect } from 'vitest';
import * as path from 'path';
import { spawnSync } from 'child_process';

const HOOK = path.resolve(__dirname, '..', 'hooks', 'firecrawl-budget.sh');

function decision(tool: string, input: object): string {
  const r = spawnSync('bash', [HOOK], {
    input: JSON.stringify({ tool_name: `mcp__firecrawl-mcp__${tool}`, tool_input: input }),
    encoding: 'utf-8',
  });
  expect(r.status).toBe(0);
  return r.stdout.trim() ? JSON.parse(r.stdout).hookSpecificOutput.permissionDecision : 'pass';
}

describe('firecrawl-budget.sh', () => {
  it.each([
    ['firecrawl_scrape', { url: 'https://x.dev', formats: ['markdown'] }],
    ['firecrawl_search', { query: 'q' }],
    ['firecrawl_search', { query: 'q', limit: 5 }],
    ['firecrawl_developer_search', { query: 'q' }],
    ['firecrawl_map', { url: 'https://x.dev' }],
    ['firecrawl_credit_usage', {}],
  ])('passes %s %j', (tool, input) => expect(decision(tool, input)).toBe('pass'));

  it.each([
    ['firecrawl_crawl', { url: 'https://x.dev', limit: 5 }],
    ['firecrawl_agent', { prompt: 'p' }],
    ['firecrawl_interact', { url: 'https://x.dev' }],
    ['firecrawl_monitor_create', {}],
    ['firecrawl_search', { query: 'q', limit: 20 }],
    ['firecrawl_search', { query: 'q', scrapeOptions: { formats: ['markdown'] } }],
    ['firecrawl_scrape', { url: 'https://x.dev', formats: ['json'] }],
    ['firecrawl_scrape', { url: 'https://x.dev', formats: [{ type: 'query', prompt: 'p' }] }],
    ['firecrawl_scrape', { url: 'https://x.dev', lockdown: true }],
  ])('asks before %s %j', (tool, input) => expect(decision(tool, input)).toBe('ask'));

  it.each([
    ['firecrawl_search', { query: 'q', limit: '50.0' }],
    ['firecrawl_scrape', { url: 'https://x.dev', formats: [5, 'json'] }],
    ['firecrawl_scrape', { url: 'https://x.dev', alexandria: { provider: 'p' } }],
    ['firecrawl_research_search_papers', { query: 'q' }],
  ])('asks on odd or unpriced input %s %j', (tool, input) => expect(decision(tool, input)).toBe('ask'));

  it('asks, never passes, on garbage input', () => {
    const r = spawnSync('bash', [HOOK], { input: 'not json', encoding: 'utf-8' });
    expect(r.status).toBe(0);
    expect(JSON.parse(r.stdout).hookSpecificOutput.permissionDecision).toBe('ask');
  });
});
