import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';

const GRAPH_SERVERS: Record<string, { command: string; args: string[] }> = {
  codegraph: { command: 'codegraph', args: ['serve', '--mcp'] },
  kirograph: { command: 'kirograph', args: ['serve', '--mcp'] },
  kimigraph: { command: 'kimigraph', args: ['serve', '--mcp'] },
};

function wireJsonConfig(
  configPath: string,
  serversKey: string,
  dryRun: boolean,
): boolean {
  let parsed: Record<string, unknown>;
  let created = false;

  if (!existsSync(configPath)) {
    parsed = { [serversKey]: {} };
    created = true;
  } else {
    parsed = JSON.parse(readFileSync(configPath, 'utf-8')) as Record<string, unknown>;
  }

  const servers = (parsed[serversKey] ?? {}) as Record<string, unknown>;
  let changed = false;

  for (const [name, config] of Object.entries(GRAPH_SERVERS)) {
    if (!servers[name]) {
      servers[name] = config;
      changed = true;
    }
  }

  if (!changed && !created) return false;

  parsed[serversKey] = servers;
  if (!dryRun) {
    writeFileSync(configPath, JSON.stringify(parsed, null, 2) + '\n');
  }
  return true;
}

export function wireMcp(targetDir: string, dryRun: boolean): string[] {
  const touched: string[] = [];

  // Claude Code — .mcp.json (mcpServers key)
  const mcpPath = join(targetDir, '.mcp.json');
  if (wireJsonConfig(mcpPath, 'mcpServers', dryRun)) {
    touched.push('.mcp.json');
  }

  // Crush — .crush.json (mcp key, type: stdio)
  const crushPath = join(targetDir, '.crush.json');
  if (!existsSync(crushPath)) {
    const crushServers: Record<string, unknown> = {};
    for (const [name, config] of Object.entries(GRAPH_SERVERS)) {
      crushServers[name] = { type: 'stdio', ...config };
    }
    if (!dryRun) {
      writeFileSync(crushPath, JSON.stringify({ mcp: crushServers }, null, 2) + '\n');
    }
    touched.push('.crush.json');
  } else {
    const parsed = JSON.parse(readFileSync(crushPath, 'utf-8')) as Record<string, unknown>;
    const servers = (parsed.mcp ?? {}) as Record<string, unknown>;
    let changed = false;
    for (const [name, config] of Object.entries(GRAPH_SERVERS)) {
      if (!servers[name]) {
        servers[name] = { type: 'stdio', ...config };
        changed = true;
      }
    }
    if (changed) {
      parsed.mcp = servers;
      if (!dryRun) {
        writeFileSync(crushPath, JSON.stringify(parsed, null, 2) + '\n');
      }
      touched.push('.crush.json');
    }
  }

  return touched;
}
