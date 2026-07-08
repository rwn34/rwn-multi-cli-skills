import { cpSync, copyFileSync, mkdirSync, existsSync } from 'node:fs';
import { join, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const FRAMEWORK_DIRS = ['.ai', '.claude', '.kimi', '.kiro', '.archive'];
const FRAMEWORK_FILES = [
  'CLAUDE.md',
  'AGENTS.md',
  'CRUSH.md',
  '.crush.json',
  'docs/architecture/0001-root-file-exceptions.md',
  '.github/workflows/framework-check.yml',
  '.codegraph/config.json',
];

export function resolveTemplateDir(): string {
  // Try bundled assets first (npm-published path)
  // dist/src/installer/copy-framework.js → package root → assets/
  const bundled = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..', '..', 'assets');
  if (existsSync(resolve(bundled, '.ai'))) return bundled;
  // Fallback for in-repo dev: walk up to repo root
  let dir = dirname(fileURLToPath(import.meta.url));
  for (let i = 0; i < 10; i++) {
    if (existsSync(resolve(dir, '.ai')) && existsSync(resolve(dir, 'tools', 'multi-cli-install'))) return dir;
    dir = dirname(dir);
  }
  throw new Error('Could not find template root (no .ai/ directory found)');
}

export function copyFrameworkFiles(templateDir: string, targetDir: string, dryRun: boolean): string[] {
  const copied: string[] = [];

  for (const d of FRAMEWORK_DIRS) {
    const src = join(templateDir, d);
    if (!existsSync(src)) continue;
    copied.push(d + '/');
    if (!dryRun) {
      cpSync(src, join(targetDir, d), { recursive: true });
    }
  }

  for (const f of FRAMEWORK_FILES) {
    const src = join(templateDir, f);
    if (!existsSync(src)) continue;
    copied.push(f);
    if (!dryRun) {
      const dst = join(targetDir, f);
      mkdirSync(dirname(dst), { recursive: true });
      copyFileSync(src, dst);
    }
  }

  return copied;
}
