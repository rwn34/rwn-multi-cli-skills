import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';

// ADR-0003 (code-graph rationalization): each CLI gets AT MOST its own graph.
// - Claude Code: codegraph only, and only when the target actually has a
//   CodeGraph config (.codegraph/config.json).
// - Kimi / Kiro: optional-off — no graph wiring by default.
// - OpenCode: no graph wiring, ever (opencode.json is never touched here) —
//   lane successor to Crush per ADR-0002 amendment 2026-07-09.
const CODEGRAPH_SERVER = { command: 'codegraph', args: ['serve', '--mcp'] };

export function wireMcp(targetDir: string, dryRun: boolean): string[] {
  if (!existsSync(join(targetDir, '.codegraph', 'config.json'))) return [];

  const mcpPath = join(targetDir, '.mcp.json');
  const parsed: Record<string, unknown> = existsSync(mcpPath)
    ? (JSON.parse(readFileSync(mcpPath, 'utf-8')) as Record<string, unknown>)
    : {};

  const servers = (parsed.mcpServers ?? {}) as Record<string, unknown>;
  if (servers.codegraph) return [];

  servers.codegraph = CODEGRAPH_SERVER;
  parsed.mcpServers = servers;
  if (!dryRun) {
    writeFileSync(mcpPath, JSON.stringify(parsed, null, 2) + '\n');
  }
  return ['.mcp.json'];
}
