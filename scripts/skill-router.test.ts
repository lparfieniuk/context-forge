/**
 * skill-router.test.ts — UserPromptSubmit hook routes PL/EN prompts to the right skill, and
 * stays silent on everything else.
 */
import { describe, it, expect } from 'vitest';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { spawnSync } from 'child_process';

const HOOK = path.resolve(__dirname, '..', 'hooks', 'skill-router.sh');
const HOME = fs.mkdtempSync(path.join(os.tmpdir(), 'cf-router-'));

function route(prompt: string): string | null {
  const r = spawnSync('bash', [HOOK], {
    input: JSON.stringify({ prompt }),
    encoding: 'utf-8',
    env: { ...process.env, HOME },
  });
  expect(r.status).toBe(0);
  if (!r.stdout.trim()) return null;
  const ctx: string = JSON.parse(r.stdout).hookSpecificOutput.additionalContext;
  return ctx.match(/Skill\(([^)]+)\)/)![1];
}

const CASES: [string, string | null][] = [
  ['streść https://youtu.be/c9nRxEy1kUY', 'context-forge:youtube-transcript'],
  ['co mówi w https://www.youtube.com/watch?v=abc', 'context-forge:youtube-transcript'],
  ['jakie mamy MCP do przeglądarki?', 'context-forge:tool-scout'],
  ['czy jest jakaś biblioteka do wykresów w Angularze', 'context-forge:tool-scout'],
  ['is there a library for parsing PDFs', 'context-forge:tool-scout'],
  ['zbadaj co nowego w Angular 21', 'context-forge:web-research'],
  ['sprawdź w internecie ceny Hostinger VPS', 'context-forge:web-research'],
  ['look up the Vite 7 migration notes', 'context-forge:web-research'],
  ['build nie działa po aktualizacji nx', 'superpowers:systematic-debugging'],
  ['the test fails with a stack trace', 'superpowers:systematic-debugging'],
  ['zapisz to jako ADR', 'context-forge:adr-verbatim'],
  ['ok kończymy na dziś', 'context-forge:end-session'],
  ['sprawdź moje zmiany przed commitem', 'context-forge:pre-review'],
  ['dodaj eksport do CSV w raporcie', 'context-forge:before-building'],
  ['zbuduj mi dashboard', 'context-forge:before-building'],
  // silent
  ['/goal wykonaj plan', null],
  ['ok', null],
  ['tak, kontynuuj', null],
  ['wyjaśnij jak działa ten komponent', null],
  ['the build adds a new chunk', null],
  ['what package.json should I edit', null],
  ['what framework does this repo use', null],
  ['compare two arrays in the test', null],
  ['co nowego w tym pliku? napisz podsumowanie', null],
  ['show me the bug report template', null],
  ['compare Vitest vs Jest for Nx', 'context-forge:web-research'],
  ['there is a bug in the date picker', 'superpowers:systematic-debugging'],
];

describe('skill-router.sh', () => {
  it.each(CASES)('%s → %s', (prompt, skill) => expect(route(prompt)).toBe(skill));

  it('logs each hit to ~/worklogs/logs/skill-router.tsv', () => {
    const log = path.join(HOME, 'worklogs/logs/skill-router.tsv');
    expect(fs.readFileSync(log, 'utf-8')).toContain('context-forge:web-research');
  });

  it('survives a malformed payload', () => {
    const r = spawnSync('bash', [HOOK], { input: 'not json', encoding: 'utf-8', env: { ...process.env, HOME } });
    expect(r.status).toBe(0);
    expect(r.stdout).toBe('');
  });
});
