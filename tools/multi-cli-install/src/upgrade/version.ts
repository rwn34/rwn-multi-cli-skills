import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import type { FrameworkVersion } from './types.js';

const REQUIRED_FIELDS: (keyof FrameworkVersion)[] = [
  'framework_version',
  'installer_name',
  'installer_version',
  'installed_at',
  'upgrade_history',
];

function versionPath(projectDir: string): string {
  return join(projectDir, '.ai', '.framework-version');
}

export function readFrameworkVersion(projectDir: string): FrameworkVersion | null {
  const path = versionPath(projectDir);
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
  for (const field of REQUIRED_FIELDS) {
    if (!(field in obj)) {
      throw new Error(`Invalid schema in ${path}: missing field '${field}'`);
    }
  }
  if (!Array.isArray(obj.upgrade_history)) {
    throw new Error(`Invalid schema in ${path}: 'upgrade_history' must be an array`);
  }
  return obj as unknown as FrameworkVersion;
}

export function writeFrameworkVersion(projectDir: string, version: FrameworkVersion): void {
  for (const field of REQUIRED_FIELDS) {
    if (!(field in version)) {
      throw new Error(`Missing required field '${field}' in FrameworkVersion`);
    }
  }
  const path = versionPath(projectDir);
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, JSON.stringify(version, null, 2) + '\n');
}
