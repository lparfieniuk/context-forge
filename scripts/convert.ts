/**
 * convert.ts — ContextForge source → installed conversion pipeline.
 *
 * Reads core/_index.yaml and distributes modules to IDE-specific installed paths:
 *   - Skills:  core/skills/<id>/SKILL.md → skills/<id>/SKILL.md  (Claude Code)
 *   - Rules:   core/rules/<NNN>-cf-<id>.md + .yaml → .cursor/rules/<NNN>-cf-<id>.mdc
 *              core/rules/<NNN>-cf-<id>.md → .claude/rules/<id>.md
 *   - Agents:  core/agents/<id>.md → agents/<id>.md AND .cursor/agents/<id>.md
 *
 * Usage:
 *   npx ts-node scripts/convert.ts --target cursor|claude|both [--dry-run]
 */

import * as path from 'path';
import * as fs from 'fs';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface RuleEntry {
  id: string;
  type: 'rule';
  number: number;
  source: string;
  yaml: string;
  installed_cursor?: string;
  installed_claude?: string;
  activation: 'always' | 'intelligent' | 'scoped';
  tags: string[];
}

interface SkillEntry {
  id: string;
  type: 'skill';
  category: string;
  source: string;
  yaml: string;
  installed_claude?: string;
  installed_cursor: null;
  script?: string;
  tier: number;
  model: string;
  tags: string[];
}

interface AgentEntry {
  id: string;
  type: 'agent';
  source: string;
  yaml: string;
  installed_claude?: string;
  installed_cursor?: string;
  model: string;
  tags: string[];
}

interface ModuleIndex {
  version: string;
  description: string;
  rules: RuleEntry[];
  skills: SkillEntry[];
  agents: AgentEntry[];
}

interface ConvertResult {
  written: string[];
  skipped: string[];
  errors: Array<{ file: string; error: string }>;
}

// ---------------------------------------------------------------------------
// CLI argument parsing
// ---------------------------------------------------------------------------

interface CliArgs {
  target: 'cursor' | 'claude' | 'both';
  dryRun: boolean;
}

function parseArgs(argv: string[]): CliArgs {
  const args = argv.slice(2);
  const get = (flag: string): string | undefined => {
    const idx = args.indexOf(flag);
    if (idx !== -1) return args[idx + 1];
    const withEquals = args.find(a => a.startsWith(`${flag}=`));
    if (withEquals) return withEquals.split('=').slice(1).join('=');
    return undefined;
  };
  const has = (flag: string): boolean =>
    args.includes(flag) || args.some(a => a.startsWith(`${flag}=`));

  const targetRaw = get('--target');
  if (!targetRaw || !['cursor', 'claude', 'both'].includes(targetRaw)) {
    console.error('[convert] --target must be one of: cursor | claude | both');
    process.exit(1);
  }

  return {
    target: targetRaw as CliArgs['target'],
    dryRun: has('--dry-run'),
  };
}

// ---------------------------------------------------------------------------
// YAML parser (minimal — no yq dependency)
// ---------------------------------------------------------------------------

/**
 * Minimal YAML loader using js-yaml if available, else regex fallback for simple values.
 * For _index.yaml we only need top-level structure; js-yaml handles the rest.
 */
function loadIndex(indexPath: string): ModuleIndex {
  const raw = fs.readFileSync(indexPath, 'utf-8');

  // Try js-yaml first
  try {
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const yaml = require('js-yaml') as { load(s: string): unknown };
    return yaml.load(raw) as ModuleIndex;
  } catch {
    console.error('[convert] js-yaml not available — install devDependencies first (npm install)');
    process.exit(1);
  }
}

// ---------------------------------------------------------------------------
// Rules: Cursor gets .mdc frontmatter; Claude gets source markdown as-is
// ---------------------------------------------------------------------------

function buildCursorMdc(ruleEntry: RuleEntry, pluginRoot: string): string {
  const sourcePath = path.join(pluginRoot, ruleEntry.source);

  if (!fs.existsSync(sourcePath)) {
    throw new Error(`source file not found: ${ruleEntry.source}`);
  }

  const yamlPath = path.join(pluginRoot, ruleEntry.yaml);
  let ruleYaml: Record<string, unknown> = {};

  if (fs.existsSync(yamlPath)) {
    try {
      // eslint-disable-next-line @typescript-eslint/no-var-requires
      const yaml = require('js-yaml') as { load(s: string): unknown };
      ruleYaml = (yaml.load(fs.readFileSync(yamlPath, 'utf-8')) ?? {}) as Record<string, unknown>;
    } catch {
      // use defaults
    }
  }

  const alwaysApply = ruleEntry.activation === 'always';
  const globs = (ruleYaml['patterns'] as string[] | undefined) ?? [];

  const frontmatter = [
    '---',
    `description: ${ruleYaml['name'] ?? ruleEntry.id}`,
    `alwaysApply: ${alwaysApply}`,
    globs.length > 0 ? `globs: [${globs.map(g => `"${g}"`).join(', ')}]` : 'globs: []',
    '---',
    '',
  ].join('\n');

  const body = fs.readFileSync(sourcePath, 'utf-8');
  return frontmatter + body;
}

function readRuleSource(ruleEntry: RuleEntry, pluginRoot: string): string {
  const sourcePath = path.join(pluginRoot, ruleEntry.source);

  if (!fs.existsSync(sourcePath)) {
    throw new Error(`source file not found: ${ruleEntry.source}`);
  }

  return fs.readFileSync(sourcePath, 'utf-8');
}

// ---------------------------------------------------------------------------
// Conversion functions
// ---------------------------------------------------------------------------

function convertSkills(
  skills: SkillEntry[],
  pluginRoot: string,
  dryRun: boolean,
): ConvertResult {
  const result: ConvertResult = { written: [], skipped: [], errors: [] };

  for (const skill of skills) {
    if (!skill.installed_claude) continue;

    const sourcePath = path.join(pluginRoot, skill.source);
    const destPath = path.join(pluginRoot, skill.installed_claude);

    if (!fs.existsSync(sourcePath)) {
      result.errors.push({ file: skill.source, error: 'source file not found (expected — source files not created yet)' });
      continue;
    }

    if (dryRun) {
      result.skipped.push(skill.installed_claude);
      continue;
    }

    try {
      fs.mkdirSync(path.dirname(destPath), { recursive: true });
      fs.copyFileSync(sourcePath, destPath);
      result.written.push(skill.installed_claude);
    } catch (err) {
      result.errors.push({ file: skill.installed_claude, error: String(err) });
    }
  }

  return result;
}

function convertCursorRules(
  rules: RuleEntry[],
  pluginRoot: string,
  dryRun: boolean,
): ConvertResult {
  const result: ConvertResult = { written: [], skipped: [], errors: [] };

  for (const rule of rules) {
    if (!rule.installed_cursor) continue;

    const destPath = path.join(pluginRoot, rule.installed_cursor);

    try {
      const content = buildCursorMdc(rule, pluginRoot);

      if (dryRun) {
        result.skipped.push(rule.installed_cursor);
        continue;
      }

      fs.mkdirSync(path.dirname(destPath), { recursive: true });
      fs.writeFileSync(destPath, content, 'utf-8');
      result.written.push(rule.installed_cursor);
    } catch (err) {
      const errMsg = String(err);
      if (errMsg.includes('source file not found')) {
        // Expected during Phase A/B — source files not created yet
        result.errors.push({ file: rule.source, error: 'source file not found (expected — source files not created yet)' });
      } else {
        result.errors.push({ file: rule.installed_cursor, error: errMsg });
      }
    }
  }

  return result;
}

function convertClaudeRules(
  rules: RuleEntry[],
  pluginRoot: string,
  dryRun: boolean,
): ConvertResult {
  const result: ConvertResult = { written: [], skipped: [], errors: [] };

  for (const rule of rules) {
    if (!rule.installed_claude) continue;

    const destPath = path.join(pluginRoot, rule.installed_claude);

    try {
      const content = readRuleSource(rule, pluginRoot);

      if (dryRun) {
        result.skipped.push(rule.installed_claude);
        continue;
      }

      fs.mkdirSync(path.dirname(destPath), { recursive: true });
      fs.writeFileSync(destPath, content, 'utf-8');
      result.written.push(rule.installed_claude);
    } catch (err) {
      const errMsg = String(err);
      if (errMsg.includes('source file not found')) {
        result.errors.push({ file: rule.source, error: 'source file not found (expected — source files not created yet)' });
      } else {
        result.errors.push({ file: rule.installed_claude, error: errMsg });
      }
    }
  }

  return result;
}

function convertAgents(
  agents: AgentEntry[],
  pluginRoot: string,
  target: 'cursor' | 'claude' | 'both',
  dryRun: boolean,
): ConvertResult {
  const result: ConvertResult = { written: [], skipped: [], errors: [] };

  for (const agent of agents) {
    const sourcePath = path.join(pluginRoot, agent.source);

    if (!fs.existsSync(sourcePath)) {
      result.errors.push({ file: agent.source, error: 'source file not found (expected — source files not created yet)' });
      continue;
    }

    const targets: Array<{ path: string; label: string }> = [];

    if ((target === 'claude' || target === 'both') && agent.installed_claude) {
      targets.push({ path: path.join(pluginRoot, agent.installed_claude), label: agent.installed_claude });
    }
    if ((target === 'cursor' || target === 'both') && agent.installed_cursor) {
      targets.push({ path: path.join(pluginRoot, agent.installed_cursor), label: agent.installed_cursor });
    }

    for (const t of targets) {
      if (dryRun) {
        result.skipped.push(t.label);
        continue;
      }

      try {
        fs.mkdirSync(path.dirname(t.path), { recursive: true });
        fs.copyFileSync(sourcePath, t.path);
        result.written.push(t.label);
      } catch (err) {
        result.errors.push({ file: t.label, error: String(err) });
      }
    }
  }

  return result;
}

// ---------------------------------------------------------------------------
// Reporting
// ---------------------------------------------------------------------------

function printResult(label: string, result: ConvertResult): void {
  console.log(`\n[${label}]`);

  if (result.written.length > 0) {
    console.log(`  written (${result.written.length}):`);
    for (const f of result.written) console.log(`    + ${f}`);
  }

  if (result.skipped.length > 0) {
    console.log(`  planned (dry-run, ${result.skipped.length}):`);
    for (const f of result.skipped) console.log(`    ~ ${f}`);
  }

  if (result.errors.length > 0) {
    console.log(`  errors (${result.errors.length}):`);
    for (const e of result.errors) console.log(`    ! ${e.file}: ${e.error}`);
  }
}

function totalErrors(results: ConvertResult[]): number {
  return results.reduce((sum, r) => sum + r.errors.length, 0);
}

// ---------------------------------------------------------------------------
// Hooks sync — keep .local-marketplace hooks in sync with source
// ---------------------------------------------------------------------------

function syncHooks(pluginRoot: string, dryRun: boolean): ConvertResult {
  const result: ConvertResult = { written: [], skipped: [], errors: [] };

  const sourceHooksDir = path.join(pluginRoot, 'hooks');
  const marketplaceHooksDir = path.resolve(pluginRoot, '../.local-marketplace/plugins/context-forge/hooks');

  if (!fs.existsSync(sourceHooksDir)) {
    result.errors.push({ file: sourceHooksDir, error: 'source hooks/ directory not found' });
    return result;
  }

  if (!fs.existsSync(marketplaceHooksDir)) {
    if (!dryRun) fs.mkdirSync(marketplaceHooksDir, { recursive: true });
  }

  // Recursive: hooks/lib/common.sh is sourced by every hook, so a top-level-only
  // copy ships a marketplace plugin whose hooks all die on their first `.` line.
  const files = fs.readdirSync(sourceHooksDir, { recursive: true }) as string[];
  for (const file of files) {
    const src = path.join(sourceHooksDir, file);
    const dest = path.join(marketplaceHooksDir, file);

    if (!fs.statSync(src).isFile()) continue;

    const srcContent = fs.readFileSync(src, 'utf-8');
    const destContent = fs.existsSync(dest) ? fs.readFileSync(dest, 'utf-8') : null;

    if (srcContent === destContent) continue;

    if (dryRun) {
      result.skipped.push(dest);
    } else {
      fs.mkdirSync(path.dirname(dest), { recursive: true });
      fs.writeFileSync(dest, srcContent, 'utf-8');
      result.written.push(dest);
    }
  }

  return result;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

function main(): void {
  const args = parseArgs(process.argv);
  const pluginRoot = path.resolve(__dirname, '..');
  const indexPath = path.join(pluginRoot, 'core', '_index.yaml');

  console.log(`[convert] plugin-root=${pluginRoot}`);
  console.log(`[convert] target=${args.target}  dry-run=${args.dryRun}`);

  if (!fs.existsSync(indexPath)) {
    console.error(`[convert] core/_index.yaml not found at ${indexPath}`);
    process.exit(1);
  }

  const index = loadIndex(indexPath);
  console.log(`[convert] loaded ${index.rules.length} rules, ${index.skills.length} skills, ${index.agents.length} agents`);

  const allResults: ConvertResult[] = [];

  // Skills — Claude Code only
  if (args.target === 'claude' || args.target === 'both') {
    const result = convertSkills(index.skills, pluginRoot, args.dryRun);
    printResult('skills → claude', result);
    allResults.push(result);
  }

  // Rules — IDE-specific installed paths
  if (args.target === 'claude' || args.target === 'both') {
    const result = convertClaudeRules(index.rules, pluginRoot, args.dryRun);
    printResult('rules → claude (.md)', result);
    allResults.push(result);
  }

  if (args.target === 'cursor' || args.target === 'both') {
    const result = convertCursorRules(index.rules, pluginRoot, args.dryRun);
    printResult('rules → cursor (.mdc)', result);
    allResults.push(result);
  }

  // Agents — both IDEs
  const agentResult = convertAgents(index.agents, pluginRoot, args.target, args.dryRun);
  printResult('agents', agentResult);
  allResults.push(agentResult);

  // Hooks — sync source hooks/ to .local-marketplace
  const hooksResult = syncHooks(pluginRoot, args.dryRun);
  printResult('hooks → marketplace', hooksResult);
  allResults.push(hooksResult);

  // Summary
  const written = allResults.reduce((s, r) => s + r.written.length, 0);
  const planned = allResults.reduce((s, r) => s + r.skipped.length, 0);
  const errors = totalErrors(allResults);

  console.log('\n[convert] SUMMARY');
  if (args.dryRun) {
    console.log(`  planned: ${planned} files would be written`);
  } else {
    console.log(`  written: ${written} files`);
  }
  console.log(`  errors:  ${errors} (source-not-found errors expected until Phase C)`);

  if (errors > 0 && written === 0 && planned === 0) {
    console.log('\n[convert] NOTE: All errors are "source file not found" — this is expected.');
    console.log('         Source files are created in later implementation phases.');
    console.log('         Run convert again after creating source files in core/.');
  }
}

main();
