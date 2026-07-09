// framework-guard — OpenCode enforcement plugin (Crush-replacement lane, ADR-0002).
// Mechanical enforcement of the AGENTS.md contract:
//   1. File writes (any tool with args.filePath: edit/write/patch) allowed ONLY to
//      .ai/activity/log.md, .ai/reports/**, .ai/handoffs/** — mirrors
//      .claude/hooks/pretool-write-edit.sh normalization (absolute paths,
//      ..-traversal, backslashes).
//   2. Fleet whitelist (ADR-0004): writes to <root>/.fleet/handoffs/to-<project>/
//      allowed only if this project's talks_to list in <root>/.fleet/registry.json
//      includes the target. Fail-CLOSED on missing/unreadable registry.
//   3. Worktree confinement (ADR-0004): sessions running in .wt/<project>/<executor>/
//      may write only inside the worktree.
//   4. Bash screen: forbidden commands (CRUSH.md rule 4 list) + redirect/tee targets
//      run through the same path rules. Unresolvable redirect targets ($var,
//      command substitution) are blocked — fail-closed; bash is permission "ask"
//      anyway, this layer is defense in depth.
// Node builtins only. Decision logic is a pure exported function so
// test-guard.mjs can unit-test it without the plugin host.

import path from "node:path";
import fs from "node:fs";

const LANE = "OpenCode's writable lane is .ai/activity/log.md, .ai/reports/**, .ai/handoffs/** (see AGENTS.md)";

function norm(p) {
  return p.replace(/\\/g, "/");
}

function block(reason) {
  return { allow: false, reason };
}

function defaultReadRegistry(registryPath) {
  try {
    return JSON.parse(fs.readFileSync(registryPath, "utf8"));
  } catch {
    return null; // caller treats null as fail-closed
  }
}

function decidePath(filePath, root, readRegistry) {
  const abs = norm(path.resolve(root, filePath));
  const rootN = norm(path.resolve(root));
  const inWorktree = /\/\.wt\/[^/]+\/[^/]+(\/|$)/.test(rootN + "/");

  // Relative form if under project root (case-insensitive: Windows), else null.
  const absL = abs.toLowerCase();
  const rootL = rootN.toLowerCase();
  const rel =
    absL === rootL ? "" : absL.startsWith(rootL + "/") ? abs.slice(rootN.length + 1) : null;

  // Rule: worktree confinement (ADR-0004) — checked first, like the Kimi hook.
  if (inWorktree && rel === null) {
    return block(
      `Worktree confinement (ADR-0004): this session runs in executor worktree '${rootN}' and may write only inside it (+ the junctioned .ai/). Escaping to '${norm(filePath)}' is blocked — cross-tree changes go through .ai/handoffs/.`
    );
  }

  // Rule: fleet whitelist (ADR-0004) — <fleetRoot>/.fleet/handoffs/to-<target>/...
  const fleet = abs.match(/^(.*\/\.fleet)\/handoffs\/to-([^/]+)\//);
  if (fleet) {
    const [, fleetRoot, target] = fleet;
    const registryPath = fleetRoot + "/registry.json";
    const registry = readRegistry(registryPath);
    if (!registry) {
      return block(
        `Fleet whitelist (ADR-0004): no readable registry at '${registryPath}' — cannot verify talks_to for '${target}'. Fail-closed.`
      );
    }
    const projectName = path.basename(rootN);
    const talks =
      (registry.projects && registry.projects[projectName] && registry.projects[projectName].talks_to) || [];
    if (talks.includes(target)) return { allow: true };
    return block(
      `Fleet whitelist (ADR-0004): '${projectName}' is not whitelisted to talk to '${target}' (registry: ${registryPath}).`
    );
  }

  if (rel === null) {
    return block(`write to '${norm(filePath)}' is outside the project root. ${LANE}.`);
  }
  if (
    rel === ".ai/activity/log.md" ||
    rel.startsWith(".ai/reports/") ||
    rel.startsWith(".ai/handoffs/")
  ) {
    return { allow: true };
  }
  return block(`write to '${rel}' is outside the lane. ${LANE}.`);
}

// CRUSH.md rule 4 list. --force-with-lease is deliberately NOT matched
// (it is the sanctioned rollback form in this framework).
const FORBIDDEN_BASH = [
  { re: /\bgit\s+push\b[^|;&]*\s(--force\b(?!-with-lease)|-f\b)/, what: "git push --force" },
  { re: /\bgit\s+reset\b[^|;&]*--hard/, what: "git reset --hard" },
  { re: /\bdrop\s+database\b/i, what: "DROP DATABASE" },
  { re: /\btruncate\b/i, what: "TRUNCATE" },
];

const BROAD_RM_TARGET = /^["']?(\/\*?|~\/?|\.{1,2}\/?|\*|[A-Za-z]:[\/\\]?\*?|\$HOME\/?)["']?$/;

function decideBash(command, root, readRegistry) {
  for (const { re, what } of FORBIDDEN_BASH) {
    if (re.test(command)) {
      return block(`forbidden command (${what}) — never-run list in AGENTS.md.`);
    }
  }

  // rm -rf (any flag order/combination) on broad targets.
  for (const segment of command.split(/[;|&]+/)) {
    const tokens = segment.trim().split(/\s+/);
    if (tokens[0] !== "rm") continue;
    const flags = tokens.filter((t) => t.startsWith("-")).join(" ");
    const recursive = /(^|[^-])-[a-zA-Z]*r|--recursive/i.test(" " + flags);
    const force = /(^|[^-])-[a-zA-Z]*f|--force/.test(" " + flags);
    if (!(recursive && force)) continue;
    for (const target of tokens.slice(1).filter((t) => !t.startsWith("-"))) {
      if (BROAD_RM_TARGET.test(target)) {
        return block(`rm -rf on broad target '${target}' — never-run list in AGENTS.md.`);
      }
    }
  }

  // Redirect / tee targets go through the same path rules.
  const targets = [];
  for (const m of command.matchAll(/(?:^|[^>&\d])>{1,2}\s*([^\s;|&<>]+)/g)) targets.push(m[1]);
  for (const m of command.matchAll(/\btee\b\s+(?:-a\s+)?([^\s;|&]+)/g)) targets.push(m[1]);
  for (let target of targets) {
    target = target.replace(/^["']|["']$/g, "");
    if (target === "/dev/null" || target === "&2" || target === "&1") continue;
    if (/[$`]/.test(target)) {
      return block(`bash redirect to unresolvable target '${target}' — cannot verify lane, fail-closed.`);
    }
    const verdict = decidePath(target, root, readRegistry);
    if (!verdict.allow) return block(`bash write: ${verdict.reason}`);
  }

  return { allow: true };
}

/**
 * Pure decision function. input: { tool, args, root, readRegistry? }
 * Returns { allow: true } or { allow: false, reason }.
 */
export function decide({ tool, args, root, readRegistry = defaultReadRegistry }) {
  if (!args) return { allow: true };
  if (typeof args.filePath === "string") return decidePath(args.filePath, root, readRegistry);
  if (tool === "bash" && typeof args.command === "string") return decideBash(args.command, root, readRegistry);
  return { allow: true };
}

export const FrameworkGuard = async ({ directory, worktree }) => {
  const root = directory || worktree || process.cwd();
  return {
    "tool.execute.before": async (input, output) => {
      const verdict = decide({ tool: input.tool, args: output.args, root });
      if (!verdict.allow) {
        throw new Error(`BLOCKED by framework-guard: ${verdict.reason}`);
      }
    },
  };
};
