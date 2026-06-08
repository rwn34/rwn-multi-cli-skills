import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';

const CODEGRAPH_SERVER = { command: 'codegraph', args: ['serve', '--mcp'] };

// Create or merge a `.mcp.json` in the target carrying the codegraph server.
// - No file: write one with just codegraph.
// - File present: add `codegraph` under mcpServers only if absent; never
//   overwrite an existing codegraph entry or clobber other servers.
// Returns the relative paths touched (empty if nothing changed).
export function wireMcp(targetDir: string, dryRun: boolean): string[] {
  const mcpPath = join(targetDir, '.mcp.json');

  if (!existsSync(mcpPath)) {
    if (!dryRun) {
      writeFileSync(mcpPath, JSON.stringify({ mcpServers: { codegraph: CODEGRAPH_SERVER } }, null, 2) + '\n');
    }
    return ['.mcp.json'];
  }

  const parsed = JSON.parse(readFileSync(mcpPath, 'utf-8')) as Record<string, unknown>;
  const servers = (parsed.mcpServers ?? {}) as Record<string, unknown>;
  if (servers.codegraph) return [];

  servers.codegraph = CODEGRAPH_SERVER;
  parsed.mcpServers = servers;
  if (!dryRun) {
    writeFileSync(mcpPath, JSON.stringify(parsed, null, 2) + '\n');
  }
  return ['.mcp.json'];
}
