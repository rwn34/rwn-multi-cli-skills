import { cpSync, copyFileSync, mkdirSync, existsSync, rmSync } from 'node:fs';
import { join, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

// Resolve repo root (walk up from this script)
const __dirname = dirname(fileURLToPath(import.meta.url));
let repoRoot = resolve(__dirname, '..');
for (let i = 0; i < 10; i++) {
  if (existsSync(join(repoRoot, '.ai')) && existsSync(join(repoRoot, 'tools', 'multi-cli-install'))) break;
  repoRoot = dirname(repoRoot);
}

const assetsDir = join(__dirname, '..', 'assets');

// Clean and recreate
if (existsSync(assetsDir)) rmSync(assetsDir, { recursive: true });
mkdirSync(assetsDir, { recursive: true });

// Copy framework dirs
for (const d of ['.ai', '.claude', '.kimi', '.kiro', '.archive']) {
  const src = join(repoRoot, d);
  if (existsSync(src)) cpSync(src, join(assetsDir, d), { recursive: true });
}

// Copy framework files
for (const f of ['CLAUDE.md', 'AGENTS.md', 'CRUSH.md', '.crush.json', 'docs/architecture/0001-root-file-exceptions.md', '.github/workflows/framework-check.yml', '.codegraph/config.json', '.gitignore']) {
  const src = join(repoRoot, f);
  if (existsSync(src)) {
    const dst = join(assetsDir, f);
    mkdirSync(dirname(dst), { recursive: true });
    copyFileSync(src, dst);
    // npm strips top-level .gitignore from tarballs; bundle a no-dot copy so
    // adapt-policy.ts can still find it in published mode.
    if (f === '.gitignore') {
      copyFileSync(src, join(assetsDir, 'gitignore'));
    }
  }
}

console.log('Assets synced to', assetsDir);
