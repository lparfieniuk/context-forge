/**
 * emit-agents-md.ts — ContextForge → AGENTS.md emitter.
 *
 * Generates a single self-contained instruction file for the AGENTS.md family
 * of harnesses (opencode, Codex CLI, Copilot, Gemini CLI, Aider, Cline/Roo)
 * from core/_index.yaml + a capability profile in harnesses/<id>.yaml.
 *
 * Full profile layout (deterministic — no timestamps, stable ordering):
 *   1. Always-on doctrine   — verbatim bodies of every activation:always rule
 *   2. On-demand rule index — table of the rest, reached by reading the file
 *   3. Skills & scripts     — catalog with resolvable script paths
 *   4. Harness adaptation   — capability profile notes + model mapping
 * The small-project profile emits only its indexed instruction source and a
 * provenance header, with a UTF-8 byte limit checked before writing.
 *
 * Usage:
 *   npx ts-node scripts/emit-agents-md.ts --harness opencode [--profile full|small-project] [--project-notes notes.md] [--out dist/AGENTS.md]
 */

import * as fs from 'fs';
import * as path from 'path';
import * as yaml from 'js-yaml';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface IndexRule {
  id: string;
  type: 'rule';
  number: number;
  source: string;
  activation: 'always' | 'intelligent' | 'scoped';
}

interface IndexSkill {
  id: string;
  type: 'skill';
  category: string;
  source: string;
  installed_claude?: string;
  script?: string;
  tier: number;
}

interface ModuleIndex {
  version: string;
  rules: IndexRule[];
  skills: IndexSkill[];
  profiles?: { id: string; source: string; max_bytes: number }[];
}

interface HarnessProfile {
  id: string;
  display_name: string;
  family: string;
  instructions: Record<string, unknown>;
  capabilities: {
    hooks: string | null;
    subagent_tool: string | null;
    deterministic_enforcement: boolean;
  };
  models: { tier2: string | null; tier3: string | null; tier3plus: string | null };
  notes: string;
}

interface CliArgs {
  harness: string;
  out: string;
  pluginRoot: string;
  profile: string;
  projectNotes?: string;
}

const PLACEHOLDER = /<CF_PLUGIN_ROOT>/g;

function parseArgs(argv: string[]): CliArgs {
  const args = argv.slice(2);
  if (args.includes('--help')) {
    console.log('Usage: emit-agents-md.ts --harness <id> [--profile full|small-project] [--project-notes <path>] [--out <path>] [--plugin-root <path>]');
    console.log('Default: full. small-project emits a compact instruction file without the full catalogs.');
    process.exit(0);
  }
  const get = (flag: string): string | undefined => {
    const idx = args.indexOf(flag);
    const withEquals = args.find(a => a.startsWith(`${flag}=`));
    const value = idx !== -1 ? args[idx + 1] : withEquals?.slice(flag.length + 1);
    if ((idx !== -1 || withEquals !== undefined) && (!value || value.startsWith('--'))) {
      throw new Error(`${flag} requires a value`);
    }
    return value;
  };

  const harness = get('--harness');
  if (!harness) {
    console.error('[emit-agents-md] --harness is required (see harnesses/*.yaml)');
    process.exit(1);
  }
  return {
    harness,
    out: get('--out') ?? 'dist/AGENTS.md',
    pluginRoot: path.resolve(get('--plugin-root') ?? path.resolve(__dirname, '..')),
    profile: get('--profile') ?? 'full',
    projectNotes: get('--project-notes'),
  };
}

function loadYaml<T>(filePath: string): T {
  return yaml.load(fs.readFileSync(filePath, 'utf-8')) as T;
}

// ---------------------------------------------------------------------------
// Sections
// ---------------------------------------------------------------------------

function demoteHeadings(body: string): string {
  return body.replace(/^(#{2,5}) /gm, '$1# ');
}

function alwaysOnSection(rules: IndexRule[], pluginRoot: string): string {
  const parts: string[] = [
    '## Always-on doctrine',
    '',
    'These rules apply to EVERY task in this project. They are reproduced',
    'verbatim from ContextForge and are not optional guidance.',
    '',
  ];

  const always = rules.filter(r => r.activation === 'always');
  if (always.length === 0) {
    throw new Error('no activation:always rules found in core/_index.yaml — nothing to emit');
  }

  for (const rule of always) {
    const body = fs.readFileSync(path.join(pluginRoot, rule.source), 'utf-8');
    const nameLine = body.split('\n').find(l => l.startsWith('# ')) ?? `# ${rule.id}`;
    const title = nameLine.replace(/^# /, '');
    parts.push(`### Rule ${String(rule.number).padStart(3, '0')} — ${title}`, '', demoteHeadings(body.replace(nameLine, '').trim()), '');
  }
  return parts.join('\n');
}

function onDemandSection(rules: IndexRule[], pluginRoot: string): string {
  const onDemand = rules.filter(r => r.activation !== 'always' && r.number < 800);
  const lines = onDemand.map(
    r => `| ${String(r.number).padStart(3, '0')} | ${r.id} | \`${path.join(pluginRoot, r.source)}\` |`,
  );
  return [
    '## On-demand rule index',
    '',
    'Read one of these files BEFORE acting on its concern — reading afterwards is an audit, not a guardrail.',
    'Read at most 2 per task. NEVER quote a rule body back; apply it and cite it.',
    '',
    '| # | Rule | Path |',
    '|---|------|------|',
    ...lines,
    '',
    'Rules numbered 800–899 are local-only (machine-specific, gitignored) — use them only if present on this machine.',
    '',
  ].join('\n');
}

function skillsSection(skills: IndexSkill[], pluginRoot: string): string {
  const lines = skills.map(
    s =>
      `| ${s.id} | ${s.category} | ${s.tier} | ${s.script ? `\`${path.join(pluginRoot, s.script)}\`` : '—'} |`,
  );
  return [
    '## Skills & scripts',
    '',
    'Tier 0 = inline CLI, Tier 1 = run the script below, Tier 2/3 = subagent dispatch (cheapest correct tier wins).',
    'Script paths are absolute — they work from any project directory.',
    '',
    '| Skill | Category | Tier | Script |',
    '|-------|----------|------|--------|',
    ...lines,
    '',
  ].join('\n');
}

function adaptationSection(profile: HarnessProfile): string {
  const cap = profile.capabilities;
  // tier2/tier3 null = not configured (loud UNSET marker); tier3plus null =
  // a deliberate choice that bans escalation — never phrased as missing config.
  const fmtModel = (label: string, id: string | null) => {
    if (id) return `- ${label}: ${id}`;
    return label.startsWith('Tier 3+')
      ? `- ${label}: not configured — Tier 3+ escalation stays BANNED on this harness`
      : `- ${label}: **UNSET** — set \`models\` in harnesses/${profile.id}.yaml and re-emit`;
  };

  return [
    `## Harness adaptation — ${profile.display_name}`,
    '',
    `- Deterministic hook enforcement: ${cap.hooks === 'full' ? 'available' : 'NOT available — NEVER/ALWAYS rules bind by compliance only; prefer checklist gates and verify outcomes yourself'}.`,
    `- Subagent dispatch tool: ${cap.subagent_tool ?? 'none'}. Rule examples written against Claude Code's \`Task(...)\` map to this tool.`,
    `- Instruction loading: this whole file loads every session; there is no per-file rules directory.`,
    fmtModel('Tier 2 model', profile.models.tier2),
    fmtModel('Tier 3 model', profile.models.tier3),
    fmtModel('Tier 3+ model', profile.models.tier3plus),
    '',
    profile.notes.trim(),
    '',
  ].join('\n');
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

function main(): void {
  const args = parseArgs(process.argv);
  const pluginRoot = args.pluginRoot;

  const indexPath = path.join(pluginRoot, 'core', '_index.yaml');
  const profilePath = path.join(pluginRoot, 'harnesses', `${args.harness}.yaml`);

  if (!fs.existsSync(indexPath)) {
    console.error(`[emit-agents-md] ${indexPath} not found`);
    process.exit(1);
  }
  if (!fs.existsSync(profilePath)) {
    console.error(`[emit-agents-md] no such harness profile: ${profilePath}`);
    console.error(`[emit-agents-md] available: ${fs.readdirSync(path.join(pluginRoot, 'harnesses')).map(f => f.replace(/\.yaml$/, '')).join(', ')}`);
    process.exit(1);
  }

  const index = loadYaml<ModuleIndex>(indexPath);
  const profile = loadYaml<HarnessProfile>(profilePath);

  if (profile.family !== 'agents-md') {
    console.error(`[emit-agents-md] harness "${args.harness}" is family "${profile.family}", not agents-md — nothing to emit`);
    process.exit(1);
  }

  const pkgVersion = (loadYaml<{ version: string }>(path.join(pluginRoot, 'package.json'))).version;

  const instructionProfile = args.profile === 'full' ? undefined : index.profiles?.find(p => p.id === args.profile);
  if (args.profile !== 'full' && !instructionProfile) {
    throw new Error(`unknown instruction profile: ${args.profile}`);
  }
  if (instructionProfile && (!Number.isInteger(instructionProfile.max_bytes) || instructionProfile.max_bytes <= 0)) {
    throw new Error(`invalid byte budget for profile: ${args.profile}`);
  }

  let doc = instructionProfile ? [
    `<!-- Generated by ContextForge v${pkgVersion}; profile=${args.profile}. Edit ${instructionProfile.source} and re-emit. -->`,
    '',
    fs.readFileSync(path.join(pluginRoot, instructionProfile.source), 'utf-8').trim(),
    '',
  ].join('\n') : [
    `# ContextForge — agent instructions (${profile.display_name})`,
    '',
    `<!-- Generated by scripts/emit-agents-md.ts from context-forge v${pkgVersion}. DO NOT EDIT BY HAND. -->`,
    `<!-- Source of truth: ~/Projects/context-forge/core/. Re-emit: npm run emit:agents -->`,
    '',
    `ContextForge treats the context window as a budget: structure over search,`,
    `tokens over brute force, cheapest correct tier for every action.`,
    '',
    alwaysOnSection(index.rules, pluginRoot),
    onDemandSection(index.rules, pluginRoot),
    skillsSection(index.skills, pluginRoot),
    adaptationSection(profile),
    '---',
    '',
    `Regenerate: \`cd ${pluginRoot} && npm run emit:agents\`. Edits belong in core/, never here.`,
    '',
  ].join('\n');

  if (args.projectNotes) {
    const notes = fs.readFileSync(path.resolve(process.env.INIT_CWD ?? process.cwd(), args.projectNotes), 'utf-8').trim();
    if (!notes) throw new Error('--project-notes must contain non-empty project context');
    doc += `\n## Project context\n\n${notes}\n`;
  }

  const outPath = path.isAbsolute(args.out) ? args.out : path.join(pluginRoot, args.out);
  // Resolve the plugin-root placeholder everywhere, then prove none survived.
  const resolved = doc.replace(PLACEHOLDER, pluginRoot);
  const unresolved = resolved.includes('<CF_PLUGIN_ROOT>');
  if (instructionProfile && Buffer.byteLength(resolved, 'utf-8') > instructionProfile.max_bytes) {
    throw new Error(`profile ${args.profile} exceeds its ${instructionProfile.max_bytes} byte budget`);
  }
  fs.mkdirSync(path.dirname(outPath), { recursive: true });
  fs.writeFileSync(outPath, resolved, 'utf-8');

  const lines = resolved.split('\n').length;
  console.log(`[emit-agents-md] wrote ${outPath} (${lines} lines, harness=${args.harness}, v${pkgVersion})`);
  if (unresolved) {
    console.error('[emit-agents-md] FAIL: output still contains unresolved <CF_PLUGIN_ROOT> placeholders');
    process.exit(1);
  }
  if (!instructionProfile && (!profile.models.tier2 || !profile.models.tier3)) {
    console.warn('[emit-agents-md] WARNING: models.tier2/tier3 unset — emitted file marks them UNSET');
  }
}

main();
