/**
 * generate-manifest.ts — Tree-sitter based symbol extraction for Shadow Index
 *
 * Usage:
 *   npx ts-node scripts/generate-manifest.ts --target /path/to/repo [--paths libs/,apps/] [--repo-name my-repo]
 *
 * Outputs:
 *   <target>/.claude/shadow/<repo>/_manifest.lightweight.yaml
 *   <target>/.cursor/shadow/<repo>/_manifest.lightweight.yaml
 */

import * as fs from 'fs';
import * as path from 'path';
import * as yaml from 'js-yaml';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface Symbol {
  name: string;
  kind: string;
  file: string;
  exported: boolean;
}

interface ManifestMetadata {
  repo: string;
  generated: string;
  stale_threshold_days: number;
  source_paths: string[];
  total_symbols: number;
}

interface Manifest {
  _metadata: ManifestMetadata;
  symbols: Symbol[];
}

// ---------------------------------------------------------------------------
// CLI argument parsing
// ---------------------------------------------------------------------------

interface CliArgs {
  target: string;
  paths: string[];
  repoName: string;
}

function parseArgs(argv: string[]): CliArgs {
  const args = argv.slice(2);
  const get = (flag: string): string | undefined => {
    const idx = args.indexOf(flag);
    if (idx !== -1 && idx + 1 < args.length) return args[idx + 1];
    return undefined;
  };

  const target = get('--target');
  if (!target) {
    console.error('Usage: generate-manifest.ts --target <repo-path> [--paths libs/,apps/] [--repo-name <name>]');
    process.exit(1);
  }

  const resolvedTarget = path.resolve(target);
  if (!fs.existsSync(resolvedTarget)) {
    console.error(`Target directory does not exist: ${resolvedTarget}`);
    process.exit(1);
  }

  const pathsRaw = get('--paths');
  const paths = pathsRaw ? pathsRaw.split(',').map(p => p.trim()) : ['.'];

  const repoName = get('--repo-name') || path.basename(resolvedTarget);

  return { target: resolvedTarget, paths, repoName };
}

// ---------------------------------------------------------------------------
// File discovery
// ---------------------------------------------------------------------------

const SKIP_DIRS = new Set([
  'node_modules', 'dist', '.git', '.next', '.nuxt', 'coverage',
  '__pycache__', '.cache', 'build', 'out', '.turbo',
]);

const TS_EXTENSIONS = new Set(['.ts', '.tsx', '.js', '.jsx']);

const SKIP_PATTERNS = [/\.spec\.ts$/, /\.test\.ts$/, /\.spec\.tsx$/, /\.test\.tsx$/, /\.d\.ts$/];

function findSourceFiles(baseDir: string, subPaths: string[]): string[] {
  const files: string[] = [];

  function walk(dir: string): void {
    let entries: fs.Dirent[];
    try {
      entries = fs.readdirSync(dir, { withFileTypes: true });
    } catch {
      return;
    }

    for (const entry of entries) {
      if (entry.isDirectory()) {
        if (!SKIP_DIRS.has(entry.name) && !entry.name.startsWith('.')) {
          walk(path.join(dir, entry.name));
        }
      } else if (entry.isFile()) {
        const ext = path.extname(entry.name);
        if (TS_EXTENSIONS.has(ext)) {
          const fullPath = path.join(dir, entry.name);
          if (!SKIP_PATTERNS.some(p => p.test(fullPath))) {
            files.push(fullPath);
          }
        }
      }
    }
  }

  for (const sub of subPaths) {
    const scanDir = sub === '.' ? baseDir : path.join(baseDir, sub);
    if (fs.existsSync(scanDir)) {
      walk(scanDir);
    }
  }

  return files;
}

// ---------------------------------------------------------------------------
// Tree-sitter AST extraction
// ---------------------------------------------------------------------------

type ParserType = any;
let Parser: any;
let TypeScriptLang: any;
let JavaScriptLang: any;

function initParser(): ParserType {
  try {
    Parser = require('tree-sitter');
    const tsModule = require('tree-sitter-typescript');
    TypeScriptLang = tsModule.typescript;
    JavaScriptLang = require('tree-sitter-javascript');
  } catch (e: any) {
    console.error('Failed to load tree-sitter. Run: npm install tree-sitter tree-sitter-typescript tree-sitter-javascript');
    console.error(e.message);
    process.exit(1);
  }

  const parser = new Parser();
  return parser;
}

const DECLARATION_TYPES = new Set([
  'class_declaration',
  'abstract_class_declaration',
  'interface_declaration',
  'enum_declaration',
  'function_declaration',
  'type_alias_declaration',
]);

const KIND_MAP: Record<string, string> = {
  'class_declaration': 'class',
  'abstract_class_declaration': 'abstract class',
  'interface_declaration': 'interface',
  'enum_declaration': 'enum',
  'function_declaration': 'function',
  'type_alias_declaration': 'type',
};

function isExported(node: any): boolean {
  const parent = node.parent;
  if (!parent) return false;
  // export class Foo {} — parent is export_statement
  if (parent.type === 'export_statement') return true;
  // export default class Foo {} — parent is export_statement
  if (parent.type === 'export_statement' && parent.text.startsWith('export default')) return true;
  return false;
}

function extractName(node: any): string | null {
  // Most declarations have a 'name' field child
  const nameNode = node.childForFieldName('name');
  if (nameNode) return nameNode.text;

  // Fallback: look for identifier child
  for (let i = 0; i < node.childCount; i++) {
    const child = node.child(i);
    if (child && (child.type === 'identifier' || child.type === 'type_identifier')) {
      return child.text;
    }
  }
  return null;
}

function extractSymbolsFromFile(
  parser: ParserType,
  filePath: string,
  baseDir: string,
): Symbol[] {
  const symbols: Symbol[] = [];
  let source: string;
  try {
    source = fs.readFileSync(filePath, 'utf-8');
  } catch {
    return symbols;
  }

  const ext = path.extname(filePath);
  const isTS = ext === '.ts' || ext === '.tsx';
  parser.setLanguage(isTS ? TypeScriptLang : JavaScriptLang);

  let tree: any;
  try {
    tree = parser.parse(source);
  } catch {
    return symbols;
  }

  const relativePath = path.relative(baseDir, filePath);

  function walk(node: any): void {
    if (DECLARATION_TYPES.has(node.type)) {
      const name = extractName(node);
      if (name) {
        symbols.push({
          name,
          kind: KIND_MAP[node.type] || node.type,
          file: relativePath,
          exported: isExported(node),
        });
      }
    }

    // Also handle: export { Foo } from './foo' — lexical_declaration with export
    // And: const Foo = ... (arrow function exports)
    if (node.type === 'lexical_declaration' && isExported(node)) {
      for (let i = 0; i < node.childCount; i++) {
        const child = node.child(i);
        if (child && child.type === 'variable_declarator') {
          const varName = child.childForFieldName('name');
          if (varName) {
            symbols.push({
              name: varName.text,
              kind: 'function', // const Foo = () => {} pattern
              file: relativePath,
              exported: true,
            });
          }
        }
      }
    }

    for (let i = 0; i < node.childCount; i++) {
      const child = node.child(i);
      if (child) walk(child);
    }
  }

  walk(tree.rootNode);
  return symbols;
}

// ---------------------------------------------------------------------------
// YAML output
// ---------------------------------------------------------------------------

function writeManifest(manifest: Manifest, targetDir: string, repoName: string): string[] {
  const writtenPaths: string[] = [];

  for (const ideDir of ['.claude', '.cursor']) {
    const shadowDir = path.join(targetDir, ideDir, 'shadow', repoName);
    fs.mkdirSync(shadowDir, { recursive: true });

    const outPath = path.join(shadowDir, '_manifest.lightweight.yaml');
    const yamlContent = yaml.dump(manifest, {
      lineWidth: 120,
      noRefs: true,
      sortKeys: false,
    });

    fs.writeFileSync(outPath, yamlContent, 'utf-8');
    writtenPaths.push(outPath);
  }

  return writtenPaths;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

function main(): void {
  const args = parseArgs(process.argv);
  const parser = initParser();

  console.log(`Scanning: ${args.target}`);
  console.log(`Paths: ${args.paths.join(', ')}`);
  console.log(`Repo: ${args.repoName}`);

  const files = findSourceFiles(args.target, args.paths);
  console.log(`Found ${files.length} source files`);

  const allSymbols: Symbol[] = [];
  for (const file of files) {
    const symbols = extractSymbolsFromFile(parser, file, args.target);
    allSymbols.push(...symbols);
  }

  // Deduplicate by name+file (same symbol may appear in re-exports)
  const seen = new Set<string>();
  const dedupedSymbols = allSymbols.filter(s => {
    const key = `${s.name}::${s.file}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });

  const manifest: Manifest = {
    _metadata: {
      repo: args.repoName,
      generated: new Date().toISOString(),
      stale_threshold_days: 7,
      source_paths: args.paths,
      total_symbols: dedupedSymbols.length,
    },
    symbols: dedupedSymbols,
  };

  const writtenPaths = writeManifest(manifest, args.target, args.repoName);

  console.log(`\nSymbols extracted: ${dedupedSymbols.length}`);
  console.log(`Written to:`);
  for (const p of writtenPaths) {
    console.log(`  ${p}`);
  }
}

main();
