import { execSync } from 'node:child_process';
import { chmodSync, existsSync } from 'node:fs';
import { join } from 'node:path';

/**
 * Wire the universal git pre-commit backstop (ADR-0005).
 *
 * `core.hooksPath` is per-clone and never inherited, so every install must set
 * it explicitly. This points git at the versioned `scripts/git-hooks/` dir
 * (copied in by copyFrameworkFiles) — the one mechanical layer that fires for
 * every CLI regardless of its runtime hook behavior (headless/trust-all/hookless).
 *
 * Returns the list of actions taken (for the install log).
 */
export function wireGitHooks(targetDir: string, dryRun: boolean): string[] {
  const actions: string[] = [];
  const hookDir = join(targetDir, 'scripts', 'git-hooks');
  const preCommit = join(hookDir, 'pre-commit');

  if (!existsSync(preCommit)) {
    return actions; // nothing to wire (hook not present)
  }

  if (dryRun) {
    actions.push('would set core.hooksPath = scripts/git-hooks');
    return actions;
  }

  // Ensure the hook is executable (git requires it on POSIX; harmless on Windows).
  for (const f of ['pre-commit', 'test-pre-commit.sh']) {
    const p = join(hookDir, f);
    if (existsSync(p)) {
      try { chmodSync(p, 0o755); } catch { /* non-POSIX fs — ignore */ }
    }
  }

  if (!existsSync(join(targetDir, '.git'))) {
    actions.push('skipped core.hooksPath (target is not a git repo yet)');
    return actions;
  }

  try {
    execSync('git config core.hooksPath scripts/git-hooks', { cwd: targetDir, stdio: 'pipe' });
    actions.push('core.hooksPath = scripts/git-hooks (ADR-0005 commit backstop)');
  } catch (err) {
    actions.push(`failed to set core.hooksPath: ${(err as Error).message}`);
  }

  return actions;
}
