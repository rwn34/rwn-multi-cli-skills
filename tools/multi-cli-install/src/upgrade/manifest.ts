import { readFileSync, writeFileSync, readdirSync, statSync, mkdirSync, existsSync } from 'node:fs';
import { join, dirname, relative, sep, posix } from 'node:path';
import { createHash } from 'node:crypto';
import type { FrameworkManifest, ManifestEntry, FileClassification } from './types.js';

const FRAMEWORK_DIRS = ['.ai', '.claude', '.kimi', '.kiro', '.archive'];
const FRAMEWORK_FILES = [
  'CLAUDE.md',
  'AGENTS.md',
  'opencode.json',
  'docs/architecture/0001-root-file-exceptions.md',
  '.github/workflows/framework-check.yml',
  '.codegraph/config.json',
  '.gitignore',
];

// Runtime-state paths excluded from manifest (sanitized to empty on install).
const EXCLUDE_PREFIXES = [
  '.ai/handoffs/to-claude/open/',
  '.ai/handoffs/to-claude/done/',
  '.ai/handoffs/to-kimi/open/',
  '.ai/handoffs/to-kimi/done/',
  '.ai/handoffs/to-kiro/open/',
  '.ai/handoffs/to-kiro/done/',
  '.ai/activity/',
  '.ai/reports/',
  '.ai/research/',
  '.archive/',
];

const EXCLUDE_PATHS = new Set([
  '.claude/settings.local.json',
]);

const ADOPTER_PATHS = new Set<string>([
  'AGENTS.md',
  'CLAUDE.md',
  '.ai/sync.md',
  'docs/architecture/0001-root-file-exceptions.md',
  '.gitignore',
]);

function manifestPath(projectDir: string): string {
  return join(projectDir, '.ai', '.framework-manifest.json');
}

export function readFrameworkManifest(projectDir: string): FrameworkManifest | null {
  const path = manifestPath(projectDir);
  if (!existsSync(path)) return null;
  const raw = readFileSync(path, 'utf-8');
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch (err) {
    throw new Error(`Invalid JSON in ${path}: ${(err as Error).message}`);
  }
  if (typeof parsed !== 'object' || parsed === null) {
    throw new Error(`Invalid schema in ${path}: expected object`);
  }
  const obj = parsed as Record<string, unknown>;
  if (typeof obj.version !== 'string' || typeof obj.files !== 'object' || obj.files === null) {
    throw new Error(`Invalid schema in ${path}: expected { version: string, files: object }`);
  }
  return obj as unknown as FrameworkManifest;
}

export function writeFrameworkManifest(projectDir: string, manifest: FrameworkManifest): void {
  if (typeof manifest.version !== 'string' || typeof manifest.files !== 'object') {
    throw new Error('Invalid FrameworkManifest: missing version or files');
  }
  const path = manifestPath(projectDir);
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, JSON.stringify(manifest, null, 2) + '\n');
}

export function computeFileSha256(absolutePath: string): string {
  return createHash('sha256').update(readFileSync(absolutePath)).digest('hex');
}

function toPosixRel(absolutePath: string, projectDir: string): string {
  const rel = relative(projectDir, absolutePath);
  return sep === posix.sep ? rel : rel.split(sep).join(posix.sep);
}

function isExcluded(relPath: string): boolean {
  if (EXCLUDE_PATHS.has(relPath)) return true;
  for (const prefix of EXCLUDE_PREFIXES) {
    if (relPath.startsWith(prefix)) return true;
  }
  return false;
}

function classify(relPath: string): FileClassification {
  if (ADOPTER_PATHS.has(relPath)) return 'adopter-customized-expected';
  return 'framework-owned';
}

function walkFiles(absRoot: string, projectDir: string, out: string[]): void {
  if (!existsSync(absRoot)) return;
  const stack: string[] = [absRoot];
  while (stack.length > 0) {
    const current = stack.pop()!;
    let entries: string[];
    try {
      entries = readdirSync(current);
    } catch {
      continue;
    }
    for (const entry of entries) {
      const full = join(current, entry);
      const st = statSync(full);
      const rel = toPosixRel(full, projectDir);
      if (st.isDirectory()) {
        if (isExcluded(rel + '/')) continue;
        stack.push(full);
      } else if (st.isFile()) {
        if (isExcluded(rel)) continue;
        out.push(full);
      }
    }
  }
}

export function buildManifestFromInstalledTree(
  projectDir: string,
  frameworkVersion: string,
): FrameworkManifest {
  const files: Record<string, ManifestEntry> = {};
  const collected: string[] = [];

  for (const d of FRAMEWORK_DIRS) {
    walkFiles(join(projectDir, d), projectDir, collected);
  }
  for (const f of FRAMEWORK_FILES) {
    const abs = join(projectDir, f);
    if (existsSync(abs) && statSync(abs).isFile()) {
      const rel = toPosixRel(abs, projectDir);
      if (!isExcluded(rel)) collected.push(abs);
    }
  }

  for (const abs of collected) {
    const rel = toPosixRel(abs, projectDir);
    files[rel] = {
      sha256: computeFileSha256(abs),
      version_first_seen: frameworkVersion,
      classification: classify(rel),
    };
  }

  return { version: frameworkVersion, files };
}
