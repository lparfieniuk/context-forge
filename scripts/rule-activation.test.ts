/**
 * rule-activation.test.ts — Guards the on-demand rule contract.
 *
 * Every file in .claude/rules/ is loaded as a project instruction on EVERY
 * session. Measured 2026-08-17: 12 rules authored as `activation: intelligent`
 * were installed there anyway and cost 14968 tokens per session for nothing.
 *
 * This suite catches the two ways that regresses:
 *   1. An `intelligent`/`scoped` rule regaining an installed_claude path
 *      (silently re-adding always-on cost).
 *   2. rule-index pointing at a rule file that does not exist, or omitting an
 *      on-demand rule (making it unreachable — worse than expensive).
 */

import { describe, it, expect } from 'vitest';
import * as fs from 'fs';
import * as path from 'path';

const PLUGIN_ROOT = path.resolve(__dirname, '..');
const INDEX = path.join(PLUGIN_ROOT, 'core/_index.yaml');
const RULE_INDEX_SKILL = path.join(PLUGIN_ROOT, 'core/skills/rule-index/SKILL.md');

interface Rule { id: string; activation: string; installedClaude: string | null; source: string }

function parseRules(): Rule[] {
  const lines = fs.readFileSync(INDEX, 'utf-8').split('\n');
  const rules: Rule[] = [];
  let cur: Partial<Rule> | null = null;
  let inRules = false;

  for (const line of lines) {
    if (/^rules:/.test(line)) { inRules = true; continue; }
    if (/^[a-z_]+:/.test(line)) { inRules = false; }
    if (!inRules) continue;

    const idMatch = line.match(/^ {2}- id: (.+)$/);
    if (idMatch) {
      if (cur?.id) rules.push(cur as Rule);
      cur = { id: idMatch[1].trim(), installedClaude: null };
      continue;
    }
    if (!cur) continue;
    const ic = line.match(/^ {4}installed_claude: (.+)$/);
    if (ic) cur.installedClaude = ic[1].trim() === 'null' ? null : ic[1].trim();
    const act = line.match(/^ {4}activation: (.+)$/);
    if (act) cur.activation = act[1].trim();
    const src = line.match(/^ {4}source: (.+)$/);
    if (src) cur.source = src[1].trim();
  }
  if (cur?.id) rules.push(cur as Rule);
  return rules;
}

describe('rule activation contract', () => {
  const rules = parseRules();

  it('parses the rule list from core/_index.yaml', () => {
    expect(rules.length).toBeGreaterThan(10);
  });

  it('only `always` rules occupy .claude/rules/ (always-on cost)', () => {
    const offenders = rules
      .filter((r) => r.installedClaude !== null && r.activation !== 'always')
      .map((r) => `${r.id} (${r.activation})`);
    expect(offenders).toEqual([]);
  });

  it('every installed always-on rule file exists on disk', () => {
    const missing = rules
      .filter((r) => r.activation === 'always' && r.installedClaude)
      .filter((r) => !fs.existsSync(path.join(PLUGIN_ROOT, r.installedClaude!)))
      .map((r) => r.installedClaude);
    expect(missing).toEqual([]);
  });

  it('rule-index lists every on-demand rule, and each file exists', () => {
    const skill = fs.readFileSync(RULE_INDEX_SKILL, 'utf-8');
    const onDemand = rules.filter((r) => r.installedClaude === null);
    expect(onDemand.length).toBeGreaterThan(0);

    const unlisted = onDemand.filter((r) => !skill.includes(path.basename(r.source)));
    expect(unlisted.map((r) => r.id)).toEqual([]);

    const referenced = [...skill.matchAll(/0\d{2}-cf-[a-z-]+\.md/g)].map((m) => m[0]);
    const broken = [...new Set(referenced)].filter(
      (f) => !fs.existsSync(path.join(PLUGIN_ROOT, 'core/rules', f)),
    );
    expect(broken).toEqual([]);
  });

  it('rule-index never lists an always-on rule (it is already loaded)', () => {
    const skillBody = fs.readFileSync(RULE_INDEX_SKILL, 'utf-8').split('## How to read one')[0];
    const alwaysOn = rules.filter((r) => r.activation === 'always');
    const wronglyListed = alwaysOn.filter((r) => skillBody.includes(path.basename(r.source)));
    expect(wronglyListed.map((r) => r.id)).toEqual([]);
  });
});
