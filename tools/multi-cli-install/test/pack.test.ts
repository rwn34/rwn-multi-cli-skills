import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { execSync } from 'node:child_process';
import { existsSync, mkdtempSync, rmSync, readdirSync, mkdirSync, renameSync } from 'node:fs';
import { join, dirname, resolve } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath, pathToFileURL } from 'node:url';

// Verifies the published-tarball layout: when the package is installed under
// node_modules/, resolveTemplateDir() must locate the bundled assets/ at
// package-root/assets/ (NOT dist/assets/), and the no-dot gitignore copy
// must be present so adapt-policy can merge it.

const __dirname = dirname(fileURLToPath(import.meta.url));
const pkgDir = resolve(__dirname, '..');

let tempRoot: string;
let extractedPkgDir: string;

beforeAll(() => {
  // Build first so dist/ is fresh
  execSync('npm run build', { cwd: pkgDir, stdio: 'pipe' });

  tempRoot = mkdtempSync(join(tmpdir(), 'multi-cli-pack-'));

  // npm pack writes the tarball to cwd. Pack into tempRoot.
  const tgzName = execSync('npm pack --silent', { cwd: pkgDir, env: { ...process.env, npm_config_pack_destination: tempRoot } })
    .toString().trim().split('\n').pop()!.trim();

  // Some npm versions ignore pack_destination — locate the .tgz wherever it landed.
  const tgzPath = existsSync(join(tempRoot, tgzName))
    ? join(tempRoot, tgzName)
    : existsSync(join(pkgDir, tgzName))
      ? join(pkgDir, tgzName)
      : (() => { throw new Error(`Could not locate packed tarball ${tgzName}`); })();

  // Set up fake node_modules layout: <tempRoot>/node_modules/@rwn34/multi-cli-install/
  const nm = join(tempRoot, 'node_modules', '@rwn34', 'multi-cli-install');
  mkdirSync(nm, { recursive: true });

  // Extract tarball: tar strips top-level "package/" prefix with --strip-components=1.
  // GNU tar on Git-bash (Windows) chokes on backslashes and "C:" host parsing; use
  // forward-slash paths and run from the extraction dir so we don't need -C.
  // --force-local prevents "host:path" interpretation.
  const tgzPosix = tgzPath.replace(/\\/g, '/');
  execSync(`tar --force-local -xzf "${tgzPosix}" --strip-components=1`, { cwd: nm, stdio: 'pipe' });

  // Clean up the original tarball if it stayed in pkgDir
  if (existsSync(join(pkgDir, tgzName))) {
    rmSync(join(pkgDir, tgzName));
  }

  extractedPkgDir = nm;
}, 60_000);

afterAll(() => {
  if (tempRoot && existsSync(tempRoot)) {
    rmSync(tempRoot, { recursive: true, force: true });
  }
});

describe('npm pack tarball regression', () => {
  it('extracts dist/ and assets/ at package root', () => {
    expect(existsSync(join(extractedPkgDir, 'dist'))).toBe(true);
    expect(existsSync(join(extractedPkgDir, 'assets'))).toBe(true);
    expect(existsSync(join(extractedPkgDir, 'dist', 'src', 'installer', 'copy-framework.js'))).toBe(true);
  });

  it('bundles assets/.ai/, assets/CLAUDE.md, assets/AGENTS.md', () => {
    expect(existsSync(join(extractedPkgDir, 'assets', '.ai'))).toBe(true);
    expect(existsSync(join(extractedPkgDir, 'assets', 'CLAUDE.md'))).toBe(true);
    expect(existsSync(join(extractedPkgDir, 'assets', 'AGENTS.md'))).toBe(true);
  });

  it('bundles assets/gitignore (no-dot copy survives npm pack stripping)', () => {
    // Bug 2: npm strips top-level .gitignore from tarballs. Our sync-assets.ts
    // workaround writes both names; the no-dot copy must reach the consumer.
    expect(existsSync(join(extractedPkgDir, 'assets', 'gitignore'))).toBe(true);
  });

  it('resolveTemplateDir() returns the bundled assets/ path under node_modules', async () => {
    // Bug 1: dynamically import the EXTRACTED copy-framework.js so import.meta.url
    // reflects the published path, then call resolveTemplateDir().
    const cfPath = join(extractedPkgDir, 'dist', 'src', 'installer', 'copy-framework.js');
    const mod = await import(pathToFileURL(cfPath).href);
    const resolved: string = mod.resolveTemplateDir();

    // Must equal <extractedPkgDir>/assets — three .. up from dist/src/installer/.
    const expected = join(extractedPkgDir, 'assets');
    expect(resolve(resolved)).toBe(resolve(expected));
  });

  it('--version and --help work via the bin entry', () => {
    const binJs = join(extractedPkgDir, 'dist', 'bin', 'multi-cli-install.js');
    expect(existsSync(binJs)).toBe(true);

    const versionOut = execSync(`node "${binJs}" --version`, { encoding: 'utf-8' }).trim();
    expect(versionOut).toMatch(/^\d+\.\d+\.\d+/);

    const helpOut = execSync(`node "${binJs}" --help`, { encoding: 'utf-8' });
    expect(helpOut).toContain('Usage:');
    expect(helpOut).toContain('--new');
  });
});
