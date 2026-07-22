import { describe, it, expect, afterEach } from 'vitest';
import {
  mkdtempSync,
  rmSync,
  mkdirSync,
  writeFileSync,
  readFileSync,
  existsSync,
} from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { readFrameworkVersion, writeFrameworkVersion } from '../src/upgrade/version.js';
import {
  readFrameworkManifest,
  writeFrameworkManifest,
  computeFileSha256,
  buildManifestFromInstalledTree,
} from '../src/upgrade/manifest.js';
import type { FrameworkVersion, FrameworkManifest } from '../src/upgrade/types.js';
import { copyFrameworkFiles, resolveTemplateDir } from '../src/installer/copy-framework.js';
import { sanitizeState } from '../src/installer/sanitize.js';
import { VERSION } from '../src/index.js';

const tempDirs: string[] = [];

function makeTempDir(prefix: string): string {
  const dir = mkdtempSync(join(tmpdir(), `${prefix}-`));
  tempDirs.push(dir);
  return dir;
}

function writeFile(path: string, content: string): void {
  mkdirSync(join(path, '..'), { recursive: true });
  writeFileSync(path, content);
}

afterEach(() => {
  for (const d of tempDirs) {
    try { rmSync(d, { recursive: true, force: true }); } catch { /* ignore */ }
  }
  tempDirs.length = 0;
});

describe('version: readFrameworkVersion / writeFrameworkVersion', () => {
  const sampleVersion: FrameworkVersion = {
    framework_version: '0.1.0',
    installer_name: '@rwn34/multi-cli-install',
    installer_version: '0.0.2',
    installed_at: '2026-05-29T10:00:00Z',
    upgrade_history: [
      { from: '0.0.9', to: '0.1.0', at: '2026-05-29T10:00:00Z' },
    ],
  };

  it('round-trips all fields via write then read', () => {
    const tmp = makeTempDir('ver-rt');
    writeFrameworkVersion(tmp, sampleVersion);
    const read = readFrameworkVersion(tmp);
    expect(read).toEqual(sampleVersion);
  });

  it('returns null when file missing', () => {
    const tmp = makeTempDir('ver-missing');
    expect(readFrameworkVersion(tmp)).toBeNull();
  });

  it('throws on malformed JSON, error message names the path', () => {
    const tmp = makeTempDir('ver-bad-json');
    mkdirSync(join(tmp, '.ai'), { recursive: true });
    writeFileSync(join(tmp, '.ai', '.framework-version'), '{not valid json');
    expect(() => readFrameworkVersion(tmp)).toThrow(/Invalid JSON/);
    expect(() => readFrameworkVersion(tmp)).toThrow(/\.framework-version/);
  });

  it('throws when required field framework_version is missing', () => {
    const tmp = makeTempDir('ver-no-fw');
    mkdirSync(join(tmp, '.ai'), { recursive: true });
    const partial = { ...sampleVersion } as Partial<FrameworkVersion>;
    delete partial.framework_version;
    writeFileSync(join(tmp, '.ai', '.framework-version'), JSON.stringify(partial));
    expect(() => readFrameworkVersion(tmp)).toThrow(/framework_version/);
  });

  it('throws when upgrade_history is not an array', () => {
    const tmp = makeTempDir('ver-bad-history');
    mkdirSync(join(tmp, '.ai'), { recursive: true });
    const bad = { ...sampleVersion, upgrade_history: 'oops' };
    writeFileSync(join(tmp, '.ai', '.framework-version'), JSON.stringify(bad));
    expect(() => readFrameworkVersion(tmp)).toThrow(/upgrade_history/);
  });

  it('creates .ai/ directory if absent', () => {
    const tmp = makeTempDir('ver-mkdir');
    expect(existsSync(join(tmp, '.ai'))).toBe(false);
    writeFrameworkVersion(tmp, sampleVersion);
    expect(existsSync(join(tmp, '.ai'))).toBe(true);
    expect(existsSync(join(tmp, '.ai', '.framework-version'))).toBe(true);
  });

  it('writes pretty-printed JSON with 2-space indent and trailing newline', () => {
    const tmp = makeTempDir('ver-format');
    writeFrameworkVersion(tmp, sampleVersion);
    const raw = readFileSync(join(tmp, '.ai', '.framework-version'), 'utf-8');
    expect(raw).toMatch(/\n  "framework_version"/);
    expect(raw.endsWith('\n')).toBe(true);
  });

  it('caps upgrade_history at the most recent 20 entries', () => {
    const tmp = makeTempDir('ver-cap');
    const history = Array.from({ length: 25 }, (_, i) => ({
      from: `0.0.${i}`,
      to: `0.0.${i + 1}`,
      at: '2026-05-29T10:00:00Z',
    }));
    writeFrameworkVersion(tmp, { ...sampleVersion, upgrade_history: history });
    const read = readFrameworkVersion(tmp);
    expect(read?.upgrade_history).toHaveLength(20);
    expect(read?.upgrade_history[0]).toEqual(history[5]); // oldest 5 dropped
    expect(read?.upgrade_history[19]).toEqual(history[24]);
  });
});

describe('manifest: read/write round-trip', () => {
  const sampleManifest: FrameworkManifest = {
    version: '0.1.0',
    files: {
      'CLAUDE.md': {
        sha256: 'a'.repeat(64),
        version_first_seen: '0.1.0',
        classification: 'adopter-customized-expected',
      },
      '.ai/instructions/foo.md': {
        sha256: 'b'.repeat(64),
        version_first_seen: '0.1.0',
        classification: 'framework-owned',
      },
    },
  };

  it('round-trips all fields including files Record', () => {
    const tmp = makeTempDir('man-rt');
    writeFrameworkManifest(tmp, sampleManifest);
    const read = readFrameworkManifest(tmp);
    expect(read).toEqual(sampleManifest);
  });

  it('returns null when manifest missing', () => {
    const tmp = makeTempDir('man-missing');
    expect(readFrameworkManifest(tmp)).toBeNull();
  });

  it('throws on malformed JSON, error names the path', () => {
    const tmp = makeTempDir('man-bad-json');
    mkdirSync(join(tmp, '.ai'), { recursive: true });
    writeFileSync(join(tmp, '.ai', '.framework-manifest.json'), 'not json');
    expect(() => readFrameworkManifest(tmp)).toThrow(/Invalid JSON/);
    expect(() => readFrameworkManifest(tmp)).toThrow(/\.framework-manifest\.json/);
  });

  it('throws on schema mismatch (missing version or files)', () => {
    const tmp = makeTempDir('man-bad-schema');
    mkdirSync(join(tmp, '.ai'), { recursive: true });
    writeFileSync(join(tmp, '.ai', '.framework-manifest.json'), JSON.stringify({ version: '0.1.0' }));
    expect(() => readFrameworkManifest(tmp)).toThrow(/Invalid schema/);
  });

  it('writes pretty-printed JSON with trailing newline', () => {
    const tmp = makeTempDir('man-format');
    writeFrameworkManifest(tmp, sampleManifest);
    const raw = readFileSync(join(tmp, '.ai', '.framework-manifest.json'), 'utf-8');
    expect(raw).toMatch(/\n  "version"/);
    expect(raw.endsWith('\n')).toBe(true);
  });
});

describe('manifest: computeFileSha256', () => {
  it('returns expected sha256 for "hello world"', () => {
    const tmp = makeTempDir('sha-known');
    const f = join(tmp, 'h.txt');
    writeFileSync(f, 'hello world');
    expect(computeFileSha256(f)).toBe(
      'b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9',
    );
  });

  it('returns 64-character lowercase hex', () => {
    const tmp = makeTempDir('sha-shape');
    const f = join(tmp, 'h.txt');
    writeFileSync(f, 'some content');
    const digest = computeFileSha256(f);
    expect(digest).toMatch(/^[0-9a-f]{64}$/);
  });

  it('throws for missing file', () => {
    const tmp = makeTempDir('sha-miss');
    expect(() => computeFileSha256(join(tmp, 'nope.txt'))).toThrow();
  });
});

describe('manifest: buildManifestFromInstalledTree', () => {
  function seedTree(root: string): void {
    // framework-owned content
    writeFile(join(root, '.ai/instructions/karpathy-guidelines/principles.md'), 'principles\n');
    writeFile(join(root, '.claude/skills/foo/SKILL.md'), 'skill\n');
    // reference / adopter-customized
    writeFile(join(root, 'AGENTS.md'), '# agents\n');
    writeFile(join(root, 'CLAUDE.md'), '# claude\n');
    // runtime state — must be excluded
    writeFile(join(root, '.ai/handoffs/to-claude/open/dummy.md'), 'handoff\n');
    writeFile(join(root, '.ai/activity/log.md'), 'log\n');
    writeFile(join(root, '.ai/activity/entries/20260713T000000Z-kimi-x-a1b2.md'), 'entry\n');
    writeFile(join(root, '.ai/reports/r.md'), 'report\n');
    writeFile(join(root, '.ai/research/foo.md'), 'research\n');
    writeFile(join(root, '.archive/old.md'), 'archived\n');
  }

  it('excludes runtime-state paths and includes framework-owned files', () => {
    const tmp = makeTempDir('build-skip');
    seedTree(tmp);
    const manifest = buildManifestFromInstalledTree(tmp, '0.1.0');
    const keys = Object.keys(manifest.files);

    expect(keys).toContain('.ai/instructions/karpathy-guidelines/principles.md');
    expect(keys).toContain('.claude/skills/foo/SKILL.md');

    expect(keys).not.toContain('.ai/handoffs/to-claude/open/dummy.md');
    expect(keys).not.toContain('.ai/activity/log.md');
    expect(keys).not.toContain('.ai/activity/entries/20260713T000000Z-kimi-x-a1b2.md');
    expect(keys).not.toContain('.ai/reports/r.md');
    expect(keys).not.toContain('.ai/research/foo.md');
    expect(keys).not.toContain('.archive/old.md');
  });

  it('classifies AGENTS.md and CLAUDE.md as adopter-customized-expected', () => {
    const tmp = makeTempDir('build-classify');
    seedTree(tmp);
    const manifest = buildManifestFromInstalledTree(tmp, '0.1.0');
    expect(manifest.files['AGENTS.md']?.classification).toBe('adopter-customized-expected');
    expect(manifest.files['CLAUDE.md']?.classification).toBe('adopter-customized-expected');
    expect(manifest.files['.ai/instructions/karpathy-guidelines/principles.md']?.classification)
      .toBe('framework-owned');
  });

  it('sets version_first_seen and top-level version to the version arg', () => {
    const tmp = makeTempDir('build-version');
    seedTree(tmp);
    const manifest = buildManifestFromInstalledTree(tmp, '9.9.9');
    expect(manifest.version).toBe('9.9.9');
    for (const entry of Object.values(manifest.files)) {
      expect(entry.version_first_seen).toBe('9.9.9');
    }
  });

  it('manifest sha256 matches independent computeFileSha256 recomputation', () => {
    const tmp = makeTempDir('build-sha');
    seedTree(tmp);
    const manifest = buildManifestFromInstalledTree(tmp, '0.1.0');
    const recomputed = computeFileSha256(join(tmp, 'CLAUDE.md'));
    expect(manifest.files['CLAUDE.md']?.sha256).toBe(recomputed);
  });

  it('uses relative POSIX paths (no leading slash, no backslashes)', () => {
    const tmp = makeTempDir('build-paths');
    seedTree(tmp);
    const manifest = buildManifestFromInstalledTree(tmp, '0.1.0');
    for (const key of Object.keys(manifest.files)) {
      expect(key.startsWith('/')).toBe(false);
      expect(key.includes('\\')).toBe(false);
      expect(key.includes(':')).toBe(false); // no Windows drive letters
    }
  });

  it('handles empty framework dirs without crashing', () => {
    const tmp = makeTempDir('build-empty');
    // create .ai/ but no files inside
    mkdirSync(join(tmp, '.ai'), { recursive: true });
    const manifest = buildManifestFromInstalledTree(tmp, '0.1.0');
    expect(manifest.version).toBe('0.1.0');
    expect(Object.keys(manifest.files)).toEqual([]);
  });
});

describe('Phase A integration: fixture install produces marker + manifest', () => {
  it('install flow writes .framework-version and .framework-manifest.json with sane content', () => {
    const target = makeTempDir('phase-a-install');
    const templateDir = resolveTemplateDir();

    // Mirror the bin install flow: copy → sanitize → marker + manifest.
    copyFrameworkFiles(templateDir, target, false);
    sanitizeState(target, VERSION, false);
    writeFrameworkVersion(target, {
      framework_version: VERSION,
      installer_name: '@rwn34/multi-cli-install',
      installer_version: VERSION,
      installed_at: new Date().toISOString(),
      upgrade_history: [],
    });
    const manifest = buildManifestFromInstalledTree(target, VERSION);
    writeFrameworkManifest(target, manifest);

    expect(existsSync(join(target, '.ai', '.framework-version'))).toBe(true);
    expect(existsSync(join(target, '.ai', '.framework-manifest.json'))).toBe(true);

    const version = readFrameworkVersion(target);
    expect(version?.framework_version).toBe(VERSION);
    expect(version?.installer_name).toBe('@rwn34/multi-cli-install');
    expect(version?.upgrade_history).toEqual([]);

    const read = readFrameworkManifest(target);
    expect(read?.version).toBe(VERSION);
    const keys = Object.keys(read!.files);
    expect(keys.length).toBeGreaterThan(50);
    expect(keys).toContain('CLAUDE.md');
    expect(keys).toContain('AGENTS.md');
    expect(keys).toContain('opencode.json');
    for (const entry of Object.values(read!.files)) {
      expect(entry.sha256).toMatch(/^[0-9a-f]{64}$/);
      expect(entry.version_first_seen).toBe(VERSION);
    }
  });
});
