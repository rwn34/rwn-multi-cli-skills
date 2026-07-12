// framework-guard — OpenCode enforcement plugin (Crush-replacement lane, ADR-0002).
// Mechanical enforcement of the .opencode/contract.md contract:
//   1. File writes (write-class tools only: write/edit/patch) allowed ONLY to the
//      paths in WRITABLE_LANE below — mirrors .claude/hooks/pretool-write-edit.sh
//      normalization (absolute paths, ..-traversal, backslashes). Default-DENY:
//      anything not matched by the lane is blocked, so project source, .claude/,
//      .kimi/, .kiro/, .ai/instructions/ and docs/architecture/ stay unwritable
//      without needing an explicit denylist.
//   2. Fleet whitelist (ADR-0004): writes to <root>/.fleet/handoffs/to-<project>/
//      allowed only if this project's talks_to list in <root>/.fleet/registry.json
//      includes the target. Fail-CLOSED on missing/unreadable registry.
//   3. Worktree confinement (ADR-0004): sessions running in .wt/<project>/<executor>/
//      may write only inside the worktree.
//   Reads are ALLOWED everywhere (read-fix 2026-07-09): only write-class ops are
//   lane-restricted. Read-class tools (read/grep/glob/list/...) pass through.
//   4. Bash screen: forbidden commands (contract rule 4 list) + redirect/tee targets
//      run through the same path rules. Unresolvable redirect targets ($var,
//      command substitution) are blocked — fail-closed; bash is permission "ask"
//      anyway, this layer is defense in depth.
//   5. Secrets: sensitive filenames (contract rule 5) are denied ANYWHERE, ahead of
//      every allow rule — the lane never licenses writing a secret file.
// Node builtins only. Decision logic is a pure exported function so
// test-guard.mjs can unit-test it without the plugin host.
//
// LOAD-BEARING EXPORT RULE: OpenCode's plugin host globs `{plugin,plugins}/*.{ts,js}`
// and requires EVERY top-level export of a matched module to be a plugin function —
// it throws `TypeError("Plugin export is not a function")` on the first non-function
// export, killing the WHOLE plugin. So this file must export ONLY functions
// (`decide`, `FrameworkGuard`). The writable-lane DATA lives in ../lib/lane.js
// (outside the plugin glob) precisely so exporting it does not break plugin loading.
// See ../lib/lane.js and .ai/reports/opencode-2026-07-12-guard-dead-plugin-load-failure.md.

import path from "node:path";
import fs from "node:fs";
import { WRITABLE_LANE } from "../lib/lane.js";

const LANE = `OpenCode's writable lane is ${WRITABLE_LANE.join(", ")} (see .opencode/contract.md)`;

// Contract rule 5: never write secrets files. Matched on the BASENAME of the
// resolved path, so it holds inside every allowed subtree too (e.g. a key
// smuggled into .github/ or .ai/reports/).
const SENSITIVE_BASENAME = /^(\.env.*|.*\.(key|pem)|id_rsa.*|secrets\..*|credentials.*)$/i;

// Windows paths are case-insensitive, so the project-root prefix must be compared
// case-insensitively there (a tool may hand back `c:\` for `C:\`). On case-SENSITIVE
// filesystems an insensitive compare would treat a sibling `/PROJ/` as inside `/proj/`
// — so we do not do that. Legitimate paths always match case exactly.
const CASE_INSENSITIVE_FS = process.platform === "win32";

function norm(p) {
  return p.replace(/\\/g, "/");
}

function inLane(rel) {
  return WRITABLE_LANE.some((entry) =>
    entry.endsWith("/**") ? rel.startsWith(entry.slice(0, -2)) : rel === entry
  );
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

function decidePath(filePath, root, readRegistry, op = "write") {
  // Normalize separators BEFORE resolving, not after. On POSIX a backslash is a
  // legal filename character, so path.resolve() treats a Windows-style absolute
  // path ('C:\p\.github\x' / '\p\.github\x') as a RELATIVE name and silently
  // rebases it under root — the path then fails to match its own lane. That is
  // fail-closed (a wrongly-blocked allow, never a bypass), but it is still wrong:
  // the guard must judge the same path identically whichever platform it runs on.
  const abs = norm(path.resolve(norm(root), norm(filePath)));
  const rootN = norm(path.resolve(norm(root)));
  const inWorktree = /\/\.wt\/[^/]+\/[^/]+(\/|$)/.test(rootN + "/");

  // Rule 5 (secrets) outranks every allow rule below, including the fleet lane.
  if (SENSITIVE_BASENAME.test(path.basename(abs))) {
    return block(
      `${op} of '${norm(filePath)}' targets a sensitive file — never write secrets (.opencode/contract.md rule 5).`
    );
  }

  // Relative form if under project root, else null.
  const fold = (s) => (CASE_INSENSITIVE_FS ? s.toLowerCase() : s);
  const absL = fold(abs);
  const rootL = fold(rootN);
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
    return block(`${op} of '${norm(filePath)}' is outside the project root. ${LANE}.`);
  }
  if (inLane(rel)) return { allow: true };
  return block(`${op} of '${rel || norm(filePath)}' is outside the lane. ${LANE}.`);
}

// .opencode/contract.md rule 4 list. --force-with-lease is deliberately NOT matched
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
      return block(`forbidden command (${what}) — never-run list in .opencode/contract.md.`);
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
        return block(`rm -rf on broad target '${target}' — never-run list in .opencode/contract.md.`);
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

// Only these tools mutate files via args.filePath. Everything else with a
// filePath (read, grep, glob, list, ...) is read-class and passes through —
// bash write-targets are screened separately in decideBash.
const WRITE_TOOLS = new Set(["write", "edit", "patch"]);

/**
 * Pure decision function. input: { tool, args, root, readRegistry? }
 * Returns { allow: true } or { allow: false, reason }.
 */
export function decide({ tool, args, root, readRegistry = defaultReadRegistry }) {
  if (!args) return { allow: true };
  if (WRITE_TOOLS.has(tool) && typeof args.filePath === "string")
    return decidePath(args.filePath, root, readRegistry, tool);
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
