import { defineConfig } from 'vitest/config';

// Test discovery is pinned to `scripts/` on purpose. The default glob
// (`**/*.test.*`) once collected every test file many times over through a
// stray self-referential symlink (`repo/context-forge -> ~/.claude/skills/
// context-forge -> repo`), inflating the suite and colliding on cpSync/symlink
// operations. Scoping `include` here makes `npm test` deterministic even if
// such a symlink reappears; the explicit excludes are belt-and-suspenders.
export default defineConfig({
  test: {
    include: ['scripts/**/*.test.ts'],
    // These tests copy the plugin tree and shell out to the bash audit scripts;
    // the 5s default is not enough headroom on a cold cache or in CI.
    testTimeout: 30000,
    exclude: [
      '**/node_modules/**',
      '**/dist/**',
      'context-forge/**',
      '**/context-forge/context-forge/**',
    ],
  },
});
