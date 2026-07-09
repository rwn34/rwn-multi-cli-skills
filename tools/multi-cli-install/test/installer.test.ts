import { describe, it, expect, afterEach, beforeAll, afterAll } from 'vitest';
import { scaffoldGreenfield } from '../src/installer/greenfield.js';
import { copyFrameworkFiles, resolveTemplateDir } from '../src/installer/copy-framework.js';
import { sanitizeState } from '../src/installer/sanitize.js';
import { adaptPolicy } from '../src/installer/adapt-policy.js';
import { wireMcp } from '../src/installer/wire-mcp.js';
import { execSync } from 'node:child_process';
import { existsSync, readFileSync, mkdirSync, writeFileSync, rmSync, readdirSync, mkdtempSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';

const MARKER = '# ADDED BY @rwn34/multi-cli-install';

const __dirname = dirname(fileURLToPath(import.meta.url));

function findTemplateDir(): string {
  let dir = __dirname;
  for (let i = 0; i < 10; i++) {
    if (existsSync(join(dir, '.ai'))) return dir;
    dir = dirname(dir);
  }
  throw new Error('Could not find template root');
}

const templateDir = findTemplateDir();
const tempDirs: string[] = [];

function makeTempDir(prefix: string): string {
  const dir = join(tmpdir(), `${prefix}-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`);
  mkdirSync(dir, { recursive: true });
  tempDirs.push(dir);
  return dir;
}

afterEach(() => {
  for (const d of tempDirs) {
    try { rmSync(d, { recursive: true, force: true }); } catch { /* ignore */ }
  }
  tempDirs.length = 0;
});

// Ensure git identity is available for tests that commit
const savedEnv: Record<string, string | undefined> = {};
beforeAll(() => {
  for (const k of ['GIT_AUTHOR_NAME', 'GIT_AUTHOR_EMAIL', 'GIT_COMMITTER_NAME', 'GIT_COMMITTER_EMAIL']) {
    savedEnv[k] = process.env[k];
  }
  if (!process.env.GIT_AUTHOR_NAME) process.env.GIT_AUTHOR_NAME = 'Test User';
  if (!process.env.GIT_AUTHOR_EMAIL) process.env.GIT_AUTHOR_EMAIL = 'test@example.com';
  if (!process.env.GIT_COMMITTER_NAME) process.env.GIT_COMMITTER_NAME = 'Test User';
  if (!process.env.GIT_COMMITTER_EMAIL) process.env.GIT_COMMITTER_EMAIL = 'test@example.com';
});
afterAll(() => {
  for (const [k, v] of Object.entries(savedEnv)) {
    if (v === undefined) delete process.env[k];
    else process.env[k] = v;
  }
});

describe('scaffoldGreenfield', () => {
  it('creates git repo with README and .gitignore', () => {
    const tmp = makeTempDir('greenfield');
    const target = join(tmp, 'my-project');
    scaffoldGreenfield(target, 'my-project');

    expect(existsSync(join(target, '.git'))).toBe(true);
    expect(readFileSync(join(target, 'README.md'), 'utf-8')).toBe('# my-project\n');
    expect(readFileSync(join(target, '.gitignore'), 'utf-8')).toBe('node_modules/\ndist/\n.env\n');
  });
});

describe('copyFrameworkFiles', () => {
  it('copies framework dirs and files to target', () => {
    const target = makeTempDir('copy-fw');
    copyFrameworkFiles(templateDir, target, false);

    expect(existsSync(join(target, '.ai'))).toBe(true);
    expect(existsSync(join(target, '.claude'))).toBe(true);
    expect(existsSync(join(target, '.kimi'))).toBe(true);
    expect(existsSync(join(target, '.kiro'))).toBe(true);
    expect(existsSync(join(target, 'CLAUDE.md'))).toBe(true);
    expect(existsSync(join(target, 'AGENTS.md'))).toBe(true);
    expect(existsSync(join(target, 'CRUSH.md'))).toBe(true);
    expect(existsSync(join(target, '.crush.json'))).toBe(true);
  });

  it('returns list of copied paths', () => {
    const target = makeTempDir('copy-fw-list');
    const copied = copyFrameworkFiles(templateDir, target, false);

    expect(copied).toContain('.ai/');
    expect(copied).toContain('.claude/');
    expect(copied).toContain('CLAUDE.md');
    expect(copied).toContain('AGENTS.md');
  });

  it('dry-run: returns paths but does not copy', () => {
    const target = makeTempDir('copy-fw-dry');
    const copied = copyFrameworkFiles(templateDir, target, true);

    expect(copied.length).toBeGreaterThan(0);
    expect(existsSync(join(target, '.ai'))).toBe(false);
    expect(existsSync(join(target, 'CLAUDE.md'))).toBe(false);
  });
});

describe('sanitizeState', () => {
  it('cleans activity log and handoff dirs', () => {
    const target = makeTempDir('sanitize');
    copyFrameworkFiles(templateDir, target, false);
    sanitizeState(target, '0.0.1', false);

    // Activity log should be clean header
    const log = readFileSync(join(target, '.ai', 'activity', 'log.md'), 'utf-8');
    expect(log).toContain('# Activity Log');
    expect(log).not.toContain('## 2026');

    // Handoff open/done dirs should be empty
    for (const cli of ['to-kiro', 'to-kimi', 'to-claude']) {
      for (const sub of ['open', 'done']) {
        const dir = join(target, '.ai', 'handoffs', cli, sub);
        if (existsSync(dir)) {
          expect(readdirSync(dir)).toHaveLength(0);
        }
      }
    }
  });

  it('appends attribution marker to known-limitations.md', () => {
    const target = makeTempDir('sanitize-kl');
    copyFrameworkFiles(templateDir, target, false);
    sanitizeState(target, '1.2.3', false);

    const kl = readFileSync(join(target, '.ai', 'known-limitations.md'), 'utf-8');
    expect(kl).toContain('# ADDED BY @rwn34/multi-cli-install v1.2.3');
  });

  it('preserves reports/README.md', () => {
    const target = makeTempDir('sanitize-readme');
    copyFrameworkFiles(templateDir, target, false);
    sanitizeState(target, '0.0.1', false);

    expect(existsSync(join(target, '.ai', 'reports', 'README.md'))).toBe(true);
  });
});

describe('adaptPolicy', () => {
  it('appends marker to .gitignore', () => {
    const target = makeTempDir('adapt');
    writeFileSync(join(target, '.gitignore'), 'node_modules/\n');
    // Create minimal ADR and hook files
    mkdirSync(join(target, 'docs', 'architecture'), { recursive: true });
    writeFileSync(join(target, 'docs', 'architecture', '0001-root-file-exceptions.md'), '# ADR\n');
    mkdirSync(join(target, '.claude', 'hooks'), { recursive: true });
    writeFileSync(join(target, '.claude', 'hooks', 'pretool-write-edit.sh'), 'case "$rel" in\n    *)\n        block "nope" ;;\nesac\n');

    adaptPolicy(target, 'typescript', 'npm', false);

    const gi = readFileSync(join(target, '.gitignore'), 'utf-8');
    expect(gi).toContain('# ADDED BY @rwn34/multi-cli-install');
  });

  it('amends ADR with Category F for typescript/npm', () => {
    const target = makeTempDir('adapt-adr');
    mkdirSync(join(target, 'docs', 'architecture'), { recursive: true });
    writeFileSync(join(target, 'docs', 'architecture', '0001-root-file-exceptions.md'), '# ADR\n');
    writeFileSync(join(target, '.gitignore'), '');

    adaptPolicy(target, 'typescript', 'npm', false);

    const adr = readFileSync(join(target, 'docs', 'architecture', '0001-root-file-exceptions.md'), 'utf-8');
    expect(adr).toContain('`package.json`');
    expect(adr).toContain('`package-lock.json`');
    expect(adr).toContain('Language manifests');
  });

  it('patches root-guard hook with manifest case arm', () => {
    const target = makeTempDir('adapt-hook');
    writeFileSync(join(target, '.gitignore'), '');
    mkdirSync(join(target, 'docs', 'architecture'), { recursive: true });
    writeFileSync(join(target, 'docs', 'architecture', '0001-root-file-exceptions.md'), '# ADR\n');
    mkdirSync(join(target, '.claude', 'hooks'), { recursive: true });
    writeFileSync(join(target, '.claude', 'hooks', 'pretool-write-edit.sh'),
      '#!/bin/bash\ncase "$rel" in\n    AGENTS.md) exit 0 ;;\n    *)\n        block "nope" ;;\nesac\n');

    adaptPolicy(target, 'typescript', 'npm', false);

    const hook = readFileSync(join(target, '.claude', 'hooks', 'pretool-write-edit.sh'), 'utf-8');
    expect(hook).toContain('package.json|package-lock.json) exit 0 ;;');
  });

  it('dry-run: returns paths but does not modify files', () => {
    const target = makeTempDir('adapt-dry');
    writeFileSync(join(target, '.gitignore'), 'node_modules/\n');
    mkdirSync(join(target, 'docs', 'architecture'), { recursive: true });
    writeFileSync(join(target, 'docs', 'architecture', '0001-root-file-exceptions.md'), '# ADR\n');

    const modified = adaptPolicy(target, 'typescript', 'npm', true);

    expect(modified.length).toBeGreaterThan(0);
    const gi = readFileSync(join(target, '.gitignore'), 'utf-8');
    expect(gi).not.toContain('# ADDED BY @rwn34/multi-cli-install');
  });
});


describe('CodeGraph wiring', () => {
  it('copies .codegraph/config.json verbatim to target', () => {
    const target = makeTempDir('codegraph-config');
    copyFrameworkFiles(templateDir, target, false);

    const dst = join(target, '.codegraph', 'config.json');
    expect(existsSync(dst)).toBe(true);

    const tplDir = resolveTemplateDir();
    const expected = readFileSync(join(tplDir, '.codegraph', 'config.json'), 'utf-8');
    expect(readFileSync(dst, 'utf-8')).toBe(expected);

    // Sanity: it is the CodeGraph config (has include/exclude), and the runtime
    // DB / cache are NOT shipped.
    const parsed = JSON.parse(readFileSync(dst, 'utf-8'));
    expect(parsed.include).toBeDefined();
    expect(parsed.exclude).toBeDefined();
    expect(existsSync(join(target, '.codegraph', 'cache'))).toBe(false);
  });

  // ADR-0003 matrix: Claude → codegraph only (when CodeGraph config present);
  // Kimi/Kiro → none; Crush → none, ever.
  function seedCodegraphConfig(target: string): void {
    mkdirSync(join(target, '.codegraph'), { recursive: true });
    writeFileSync(join(target, '.codegraph', 'config.json'), '{ "include": [], "exclude": [] }\n');
  }

  it('wireMcp wires codegraph only into .mcp.json — no other graphs, no .crush.json', () => {
    const target = makeTempDir('wire-mcp-create');
    seedCodegraphConfig(target);
    const touched = wireMcp(target, false);

    expect(touched).toEqual(['.mcp.json']);
    const mcp = JSON.parse(readFileSync(join(target, '.mcp.json'), 'utf-8'));
    expect(mcp.mcpServers.codegraph).toEqual({ command: 'codegraph', args: ['serve', '--mcp'] });
    expect(mcp.mcpServers.kirograph).toBeUndefined();
    expect(mcp.mcpServers.kimigraph).toBeUndefined();
    expect(existsSync(join(target, '.crush.json'))).toBe(false);
  });

  it('wireMcp is a no-op when the target has no CodeGraph config', () => {
    const target = makeTempDir('wire-mcp-no-cg');
    const touched = wireMcp(target, false);

    expect(touched).toHaveLength(0);
    expect(existsSync(join(target, '.mcp.json'))).toBe(false);
    expect(existsSync(join(target, '.crush.json'))).toBe(false);
  });

  it('wireMcp merges codegraph into an existing .mcp.json without clobbering other servers', () => {
    const target = makeTempDir('wire-mcp-merge');
    seedCodegraphConfig(target);
    writeFileSync(
      join(target, '.mcp.json'),
      JSON.stringify({ mcpServers: { other: { command: 'other-server', args: [] } } }, null, 2) + '\n',
    );

    const touched = wireMcp(target, false);
    expect(touched).toContain('.mcp.json');

    const mcp = JSON.parse(readFileSync(join(target, '.mcp.json'), 'utf-8'));
    expect(mcp.mcpServers.other).toEqual({ command: 'other-server', args: [] });
    expect(mcp.mcpServers.codegraph).toEqual({ command: 'codegraph', args: ['serve', '--mcp'] });
    expect(mcp.mcpServers.kirograph).toBeUndefined();
    expect(mcp.mcpServers.kimigraph).toBeUndefined();
  });

  it('wireMcp leaves an existing codegraph entry untouched', () => {
    const target = makeTempDir('wire-mcp-noop');
    seedCodegraphConfig(target);
    const existing = { mcpServers: { codegraph: { command: 'custom-codegraph', args: ['x'] } } };
    writeFileSync(join(target, '.mcp.json'), JSON.stringify(existing, null, 2) + '\n');

    const touched = wireMcp(target, false);
    expect(touched).toHaveLength(0);

    const mcp = JSON.parse(readFileSync(join(target, '.mcp.json'), 'utf-8'));
    expect(mcp.mcpServers.codegraph).toEqual({ command: 'custom-codegraph', args: ['x'] });
  });

  it('wireMcp never touches an existing .crush.json (Crush gets no graph, ever)', () => {
    const target = makeTempDir('wire-mcp-crush');
    seedCodegraphConfig(target);
    const crushBefore = JSON.stringify({ mcp: {} }, null, 2) + '\n';
    writeFileSync(join(target, '.crush.json'), crushBefore);

    const touched = wireMcp(target, false);
    expect(touched).toEqual(['.mcp.json']);
    expect(readFileSync(join(target, '.crush.json'), 'utf-8')).toBe(crushBefore);
  });

  it('wireMcp dry-run reports path but writes nothing', () => {
    const target = makeTempDir('wire-mcp-dry');
    seedCodegraphConfig(target);
    const touched = wireMcp(target, true);

    expect(touched).toContain('.mcp.json');
    expect(existsSync(join(target, '.mcp.json'))).toBe(false);
  });

  // ADR-0003 drift guard: the shipped .crush.json template must never carry
  // graph MCP servers — otherwise every install hands Crush a graph even
  // though wireMcp itself never touches .crush.json.
  it('template .crush.json ships with no graph MCP servers', () => {
    const tplDir = resolveTemplateDir();
    const raw = readFileSync(join(tplDir, '.crush.json'), 'utf-8');
    const parsed = JSON.parse(raw) as { mcp?: Record<string, unknown> };

    const graphServers = Object.keys(parsed.mcp ?? {}).filter((k) => /graph/i.test(k));
    expect(graphServers).toEqual([]);
    expect(raw).not.toMatch(/kirograph|kimigraph|codegraph/i);
  });
});

describe('bug fixes (B1-B4)', () => {
  // T1: greenfield uses local git config (not hardcoded)
  it('greenfield commit uses local git user, not hardcoded', () => {
    const tmp = mkdtempSync(join(tmpdir(), 'greenfield-author-'));
    const target = join(tmp, 'my-project');
    scaffoldGreenfield(target, 'my-project');
    const author = execSync('git log -1 --format=%an', { cwd: target, encoding: 'utf-8' }).trim();
    expect(author).not.toBe('multi-cli-install');
    rmSync(tmp, { recursive: true, force: true });
  });

  // T2: post-install .gitignore contains framework entries
  it('post-install .gitignore contains framework entries', () => {
    const tmp = mkdtempSync(join(tmpdir(), 'gitignore-merge-'));
    const target = join(tmp, 'test-project');
    scaffoldGreenfield(target, 'test-project');
    const tplDir = resolveTemplateDir();
    copyFrameworkFiles(tplDir, target, false);
    adaptPolicy(target, 'typescript', 'npm', false);
    const gi = readFileSync(join(target, '.gitignore'), 'utf-8');
    expect(gi).toContain('.kirograph/');
    expect(gi).toContain(MARKER);
    rmSync(tmp, { recursive: true, force: true });
  });

  // T3: resolveTemplateDir finds template with .ai/
  it('resolveTemplateDir finds template dir', () => {
    const dir = resolveTemplateDir();
    expect(existsSync(join(dir, '.ai'))).toBe(true);
    expect(existsSync(join(dir, '.claude'))).toBe(true);
  });

  // T4: greenfield refuses if target already exists
  it('greenfield refuses if target dir already exists', () => {
    const tmp = mkdtempSync(join(tmpdir(), 'greenfield-exists-'));
    const target = join(tmp, 'existing');
    mkdirSync(target);
    expect(() => scaffoldGreenfield(target, 'existing')).toThrow();
    rmSync(tmp, { recursive: true, force: true });
  });
});
