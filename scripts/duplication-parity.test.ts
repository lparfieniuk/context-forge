/**
 * duplication-parity.test.ts — pins the deliberately duplicated numbers.
 *
 * ContextForge repeats some facts in two places ON PURPOSE (a routing decision
 * should find the price in one place; doctrine should not depend on a helper
 * being loaded first). Deliberate duplication drifts silently, so each copy
 * pair below is pinned here: change one side without the other and this test
 * fails, forcing either a sync or a conscious decision that the duplication
 * no longer exists (then delete the pin — never weaken it).
 *
 *   1. Cache cost multipliers   — rule 006 (TTL selection) ↔ rule 018 (pricing)
 *   2. Tier token-cost ranges   — rule 003 ↔ repo CLAUDE.md routing table
 *   3. Tier model anchors       — rule 003 ↔ harnesses/claude-code.yaml
 */

import * as fs from 'fs';
import * as path from 'path';
import * as yaml from 'js-yaml';
import { describe, expect, it } from 'vitest';

const PLUGIN_ROOT = path.resolve(__dirname, '..');
const read = (rel: string) => fs.readFileSync(path.join(PLUGIN_ROOT, rel), 'utf-8');

/** Body of a `## Heading` section up to the next same-level heading. */
function section(doc: string, heading: string): string {
  const re = new RegExp(`^## ${heading}\\s*$`, 'm');
  const m = re.exec(doc);
  expect(m, `section "## ${heading}" not found`).toBeTruthy();
  const rest = doc.slice(m!.index + m![0].length);
  const next = /^## /m.exec(rest);
  return next ? rest.slice(0, next.index) : rest;
}

describe('cache cost multipliers — rule 006 ↔ rule 018', () => {
  // Both copies state: 5-min write 1.25×, 1-hour write 2×, cache read 0.1×.
  // Compare the SET of x-multipliers in each copy so adding/removing a row in
  // one copy alone also fails, not just value drift.
  const multipliers = (doc: string) =>
    [...new Set([...doc.matchAll(/\b(\d+(?:\.\d+)?)x\b/g)].map(m => m[1]))].sort();

  it('rule 006 Cache Cost Table agrees with rule 018 Cache Multipliers', () => {
    const r006 = multipliers(section(read('core/rules/006-cf-prompt-caching.md'), 'Cache Cost Table'));
    const r018 = multipliers(section(read('core/rules/018-cf-cost-model.md'), 'Cache Multipliers \\(relative to base input\\)'));
    expect(r006.length, 'no multipliers parsed from rule 006').toBeGreaterThan(0);
    expect(r018.length, 'no multipliers parsed from rule 018').toBeGreaterThan(0);
    expect(r006).toEqual(r018);
  });

  it('both copies still carry the three canonical values', () => {
    for (const rel of ['core/rules/006-cf-prompt-caching.md', 'core/rules/018-cf-cost-model.md']) {
      const doc = read(rel);
      expect(doc, rel).toMatch(/1\.25x/);
      expect(doc, rel).toMatch(/0\.1x/);
      expect(doc, rel).toMatch(/2x base input|2x\s*\|/);
    }
  });
});

describe('tier token-cost ranges — rule 003 ↔ CLAUDE.md', () => {
  const tierRange = (rowRe: RegExp, doc: string): string[] | null => {
    const row = doc.split('\n').find(l => rowRe.test(l));
    if (!row) return null;
    // Token-cost cell only: "~200–1k" / "~600–5k" — ignore IDs and other numbers.
    const m = /~\s*(\d+k?)\s*[–—-]\s*(\d+k?)/.exec(row);
    return m ? [m[1], m[2]] : null;
  };

  const cases: Array<[RegExp, RegExp]> = [
    [/^\| 2 \|/, /^\| 2 \| `.*/],
    [/^\| 3 \|(?!.*opus)/, /^\| 3 \| `.*/],
  ];

  it.each(cases.map((_, i) => i))('tier row %i matches between copies', i => {
    const r003 = read('core/rules/003-cf-tier-routing.md');
    const cmd = read('CLAUDE.md');
    const a = tierRange(cases[i][0], r003);
    const b = tierRange(cases[i][1], cmd);
    expect(a, 'row in rule 003').toBeTruthy();
    expect(b, 'row in CLAUDE.md').toBeTruthy();
    expect(a).toEqual(b);
  });
});

describe('tier model anchors — rule 003 ↔ harnesses/claude-code.yaml', () => {
  const profile = yaml.load(
    fs.readFileSync(path.join(PLUGIN_ROOT, 'harnesses/claude-code.yaml'), 'utf-8'),
  ) as { models: { tier2: string; tier3: string; tier3plus: string } };

  const anchorFromRule = (tierRow: RegExp): string => {
    const doc = read('core/rules/003-cf-tier-routing.md');
    const row = doc.split('\n').find(l => tierRow.test(l));
    expect(row, 'tier row in rule 003').toBeTruthy();
    const id = /`claude-[a-z0-9-]+`/.exec(row!);
    expect(id, 'model anchor in rule 003 row').toBeTruthy();
    return id![0].replace(/`/g, '');
  };

  it('profile models.tier2 equals rule 003 Tier 2 anchor', () => {
    expect(profile.models.tier2).toBe(anchorFromRule(/^\| 2 \|/));
  });
  it('profile models.tier3 equals rule 003 Tier 3 anchor', () => {
    expect(profile.models.tier3).toBe(anchorFromRule(/^\| 3 \|(?=.*sonnet)/));
  });
  it('profile models.tier3plus equals rule 003 Tier 3+ anchor', () => {
    expect(profile.models.tier3plus).toBe(anchorFromRule(/^\| 3\+ \|/));
  });
});
