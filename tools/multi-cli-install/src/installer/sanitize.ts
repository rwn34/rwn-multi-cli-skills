import { writeFileSync, readdirSync, rmSync, existsSync, appendFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';

function clearDir(dir: string, dryRun: boolean): string[] {
  const modified: string[] = [];
  if (!existsSync(dir)) return modified;
  for (const entry of readdirSync(dir)) {
    modified.push(join(dir, entry));
    if (!dryRun) rmSync(join(dir, entry), { recursive: true, force: true });
  }
  return modified;
}

export function sanitizeState(targetDir: string, version: string, dryRun: boolean): string[] {
  const modified: string[] = [];

  // 1. Clean activity log — ADR-0010 (2026-07-13): the activity log is an
  // entry-per-file spool, not a single log.md. Remove any log.md that rode
  // along with the template copy (adopters must not inherit the template's own
  // history) and create an empty spool. log.md becomes a generated, gitignored
  // view rendered by .ai/tools/render-activity-log.sh.
  const logPath = join(targetDir, '.ai', 'activity', 'log.md');
  if (existsSync(logPath)) {
    modified.push('.ai/activity/log.md');
    if (!dryRun) rmSync(logPath, { force: true });
  }
  const entriesDir = join(targetDir, '.ai', 'activity', 'entries');
  // Clear any entries copied from the template tree (adopters must not inherit
  // the template's own spool), then leave an empty spool behind.
  modified.push(...clearDir(entriesDir, dryRun).map(p => p.replace(targetDir + '/', '').replace(targetDir + '\\', '')));
  modified.push('.ai/activity/entries/.gitkeep');
  if (!dryRun) {
    mkdirSync(entriesDir, { recursive: true });
    writeFileSync(join(entriesDir, '.gitkeep'), '');
  }

  // 2. Clear handoff open/done dirs (keep README.md and template.md at handoffs/ root)
  for (const cli of ['to-kiro', 'to-kimi', 'to-claude']) {
    for (const sub of ['open', 'done']) {
      const dir = join(targetDir, '.ai', 'handoffs', cli, sub);
      modified.push(...clearDir(dir, dryRun).map(p => p.replace(targetDir + '/', '').replace(targetDir + '\\', '')));
    }
  }

  // 3. Clear .ai/reports/ contents (keep README.md)
  const reportsDir = join(targetDir, '.ai', 'reports');
  if (existsSync(reportsDir)) {
    for (const entry of readdirSync(reportsDir)) {
      if (entry === 'README.md') continue;
      modified.push(`.ai/reports/${entry}`);
      if (!dryRun) rmSync(join(reportsDir, entry), { recursive: true, force: true });
    }
  }

  // 4. Clear .archive/ai/ contents
  for (const sub of ['handoffs', 'reports', 'activity']) {
    const dir = join(targetDir, '.archive', 'ai', sub);
    modified.push(...clearDir(dir, dryRun).map(p => p.replace(targetDir + '/', '').replace(targetDir + '\\', '')));
  }

  // 5. Append attribution marker to known-limitations.md
  const klPath = join(targetDir, '.ai', 'known-limitations.md');
  if (existsSync(klPath)) {
    modified.push('.ai/known-limitations.md');
    if (!dryRun) {
      appendFileSync(klPath, `\n---\n\n# ADDED BY @rwn34/multi-cli-install v${version}\n`);
    }
  }

  return modified;
}
