import { cpSync, copyFileSync, mkdirSync, existsSync, rmSync } from 'node:fs';
import { join, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execSync } from 'node:child_process';

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

// Copy framework dirs (dotfolders + the versioned git-hooks backstop, ADR-0005).
// .opencode ships the mechanical guard layer (contract.md + plugin/framework-guard.js);
// without it onboarded projects run OpenCode on prompt-level rules only (ADR-0002
// amendment 2026-07-09 — the guard layer is WHY OpenCode replaced Crush).
// Keep in step with FRAMEWORK_DIRS in src/installer/copy-framework.ts —
// .ai/tools/check-asset-drift.sh FAILS CI if the two manifests diverge.
// Copy only tracked files under each framework dir. Runtime/gitignored files
// (e.g., .ai/.heartbeat-*.json, .ai/activity/log.md) must not be bundled into
// the installer payload.
function copyTrackedDir(srcRel: string, dstRel: string) {
  const srcRoot = join(repoRoot, srcRel);
  const dstRoot = join(assetsDir, dstRel);
  if (!existsSync(srcRoot)) return;
  let files: string[];
  try {
    files = execSync(`git ls-files -- "${srcRel}"`, { cwd: repoRoot, encoding: 'utf-8', shell: 'bash' })
      .split('\n')
      .filter(Boolean);
  } catch {
    // Not a git repo or git unavailable: fall back to recursive copy. This path
    // is used only in unusual standalone builds; normal framework development
    // always runs inside the repo.
    mkdirSync(dirname(dstRoot), { recursive: true });
    cpSync(srcRoot, dstRoot, { recursive: true });
    return;
  }
  for (const file of files) {
    const relInside = file.slice(srcRel.length).replace(/^\//, '');
    if (!relInside) continue;
    const srcFile = join(repoRoot, file);
    const dstFile = join(dstRoot, relInside);
    mkdirSync(dirname(dstFile), { recursive: true });
    copyFileSync(srcFile, dstFile);
  }
}

for (const d of ['.ai', '.claude', '.kimi', '.kiro', '.opencode', '.archive', 'scripts/git-hooks']) {
  copyTrackedDir(d, d);
}

// Copy framework files
for (const f of ['CLAUDE.md', 'AGENTS.md', 'opencode.json', 'docs/architecture/0001-root-file-exceptions.md', '.github/workflows/framework-check.yml', '.codegraph/config.json', '.gitignore']) {
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
