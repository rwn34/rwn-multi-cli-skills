// Standalone test harness for framework-guard's decision function.
// Run: node .opencode/plugin/test-guard.mjs
// WRITABLE_LANE now lives in ../lib/lane.js (a data module OUTSIDE the plugin glob)
// so framework-guard.js can export only functions — see the load-path tests at the
// bottom of this file and .ai/reports/opencode-2026-07-12-guard-dead-plugin-load-failure.md.
import { decide, FrameworkGuard } from "./framework-guard.js";
import { WRITABLE_LANE } from "../lib/lane.js";
import path from "node:path";
import fs from "node:fs";
import os from "node:os";
import { fileURLToPath } from "node:url";

// Sandbox roots derived via path.resolve so they are genuinely absolute on the
// running OS (POSIX on CI + Windows locally). Hardcoded `C:\...` literals are
// NOT absolute on Linux — path.resolve treats them as relative segments, which
// broke the in-lane absolute case (rel computed wrong -> guard blocked it).
const ROOT = path.resolve("proj");
const WT_ROOT = path.resolve("parent", ".wt", "projX", "kimi");
const FLEET_ROOT = path.resolve("fleet", "projA");

// Absolute test inputs built from the roots above so they resolve to real
// absolutes under the OS root on every platform. norm() in the guard converts
// backslashes, so on Windows these normalize identically.
const ABS_INLANE = path.join(ROOT, ".ai", "reports", "r.md"); // absolute, inside ROOT lane
const ABS_OUTSIDE = path.resolve("elsewhere", "evil.txt"); // absolute, sibling of ROOT
const ABS_OUTSIDE_READ = path.resolve("elsewhere", "notes.md"); // absolute, outside project root
const WT_ABS_ESCAPE = path.resolve("parent", "other.md"); // absolute, outside WT_ROOT
const FLEET_HANDOFFS = path.resolve("fleet", ".fleet", "handoffs");
const fleetWrite = (target, name = "202607091200-x.md") =>
  path.join(FLEET_HANDOFFS, `to-${target}`, name); // .fleet/handoffs/to-<target>/<name>

const registryOk = () => ({ projects: { projA: { talks_to: ["projB"] } } });
const registryMissing = () => null;

let pass = 0;
let fail = 0;
const failures = [];

function check(name, verdict, expectAllow) {
  const ok = verdict.allow === expectAllow;
  if (ok) pass++;
  else {
    fail++;
    failures.push(`${name} — expected allow=${expectAllow}, got ${JSON.stringify(verdict)}`);
  }
}

const write = (filePath, root = ROOT, readRegistry) =>
  decide({ tool: "write", args: { filePath }, root, ...(readRegistry ? { readRegistry } : {}) });
const read = (filePath, root = ROOT) => decide({ tool: "read", args: { filePath }, root });
const bash = (command, root = ROOT) => decide({ tool: "bash", args: { command }, root });

// --- whitelist ---
check("allow .ai/reports write", write(".ai/reports/opencode-test.md"), true);
check("allow .ai/activity/log.md", write(".ai/activity/log.md"), true);
check("allow .ai/handoffs write", write(".ai/handoffs/to-claude/open/202607091200-x.md"), true);
check("allow absolute in-lane write", write(ABS_INLANE), true);
check("block .ai/activity sibling", write(".ai/activity/other.md"), false);
check("block src/ write", write("src/evil.txt"), false);
check("block CRUSH.md write", write("CRUSH.md"), false);
check("block absolute outside root", write(ABS_OUTSIDE), false);

// --- traversal / backslash normalization ---
check("block ../ traversal", write("../outside.md"), false);
check("block in-lane prefix escaping via ..", write(".ai/reports/../../src/evil.txt"), false);
check("block backslash variant", write("src\\evil.txt"), false);
check("block backslash traversal", write("..\\..\\outside.md"), false);
check("allow backslash in-lane", write(".ai\\reports\\ok.md"), true);

// --- fleet whitelist (ADR-0004) ---
check(
  "allow fleet whitelisted",
  write(fleetWrite("projB"), FLEET_ROOT, registryOk),
  true
);
check(
  "block fleet non-whitelisted",
  write(fleetWrite("projC"), FLEET_ROOT, registryOk),
  false
);
check(
  "block fleet missing registry (fail-closed)",
  write(fleetWrite("projB", "x.md"), FLEET_ROOT, registryMissing),
  false
);

// --- worktree confinement (ADR-0004) ---
check("block worktree absolute escape", write(WT_ABS_ESCAPE, WT_ROOT), false);
check("block worktree ../ escape", write("..\\..\\..\\other.md", WT_ROOT), false);
check("allow worktree in-lane write", write(".ai/reports/wt-report.md", WT_ROOT), true);
check("block worktree out-of-lane write", write("src/evil.txt", WT_ROOT), false);

// --- bash forbidden commands ---
check("block git push --force", bash("git push --force origin master"), false);
check("block git push -f", bash("git push -f origin master"), false);
check("allow git push --force-with-lease", bash("git push --force-with-lease=master:abc origin"), true);
check("block git reset --hard", bash("git reset --hard HEAD~1"), false);
check("block rm -rf /", bash("rm -rf /"), false);
check("block rm -fr .", bash("rm -fr ."), false);
check("block rm -r -f *", bash("rm -r -f *"), false);
check("allow rm -rf on scoped dir", bash("rm -rf .ai/reports/tmp-dir"), true);
check("block DROP DATABASE", bash('psql -c "DROP DATABASE prod"'), false);
check("block TRUNCATE", bash('psql -c "TRUNCATE TABLE users"'), false);

// --- bash ordinary / redirects ---
check("allow git status", bash("git status"), true);
check("allow ls", bash("ls -la src/"), true);
check("allow redirect in-lane", bash("echo hi > .ai/reports/note.md"), true);
check("block redirect out-of-lane", bash("echo hi > src/evil.txt"), false);
check("block append out-of-lane", bash("echo hi >> config/app.toml"), false);
check("block tee out-of-lane", bash("echo hi | tee src/evil.txt"), false);
check("allow tee in-lane", bash("echo hi | tee .ai/reports/note.md"), true);
check("block unresolvable redirect target", bash('echo hi > "$SOMEWHERE/file"'), false);
check("allow stderr redirect to /dev/null", bash("git fetch 2> /dev/null"), true);

// --- reads allowed everywhere (read-fix 2026-07-09) ---
check("allow read outside lane (src/)", read("src/main.rs"), true);
check("allow read of .opencode/contract.md (regression)", read(".opencode/contract.md"), true);
check("allow read outside project root", read(ABS_OUTSIDE_READ), true);
check("allow read escaping worktree", read(WT_ABS_ESCAPE, WT_ROOT), true);
check("allow edit-tool alias 'patch' still lane-restricted", decide({ tool: "patch", args: { filePath: "src/evil.txt" }, root: ROOT }), false);

// --- non-write tools pass through ---
check("allow read-ish tool (no filePath)", decide({ tool: "grep", args: { pattern: "x" }, root: ROOT }), true);

// ===========================================================================
// GitHub / repo-ops lane (2026-07-12) — .github/** is writable.
// The bug this closes: docs assigned OpenCode "CI config/workflow fixes"
// (operating-prompt §14, ADR-0011) while the guard denied .github/ — handoff
// 202607120021 was mechanically impossible. See .ai/reports/opencode-2026-07-12-gates-blocked.md.
// ===========================================================================

// --- ALLOW: .github/** in every path shape ---
check("allow .github/workflows/gates.yml (the blocked handoff)", write(".github/workflows/gates.yml"), true);
check("allow .github top-level file", write(".github/CODEOWNERS"), true);
check("allow .github nested action", write(".github/actions/setup/action.yml"), true);
check("allow .github issue template", write(".github/ISSUE_TEMPLATE/bug.md"), true);
check("allow .github backslash form", write(".github\\workflows\\gates.yml"), true);
check("allow .github absolute form", write(path.join(ROOT, ".github", "workflows", "gates.yml")), true);
check(
  "allow .github absolute backslash form",
  write(path.join(ROOT, ".github", "workflows", "gates.yml").replace(/[/\\]/g, "\\")),
  true
);
check("allow .github via ./ prefix", write("./.github/workflows/gates.yml"), true);
check("allow .github via in-lane traversal", write(".ai/reports/../../.github/workflows/gates.yml"), true);
check("allow .github write inside worktree", write(".github/workflows/gates.yml", WT_ROOT), true);
check("allow bash redirect into .github", bash("echo x > .github/workflows/gates.yml"), true);
check("allow bash tee into .github", bash("cat t.yml | tee .github/workflows/gates.yml"), true);

// --- DENY: the widening must not leak. Source + other CLIs + SSOT + ADRs. ---
// Relative form.
check("block source .js", write("src/index.js"), false);
check("block source at root", write("main.rs"), false);
check("block tests/", write("tests/e2e/spec.ts"), false);
check("block .claude/", write(".claude/hooks/pretool-write-edit.sh"), false);
check("block .kimi/", write(".kimi/config.toml"), false);
check("block .kiro/", write(".kiro/steering/operating-prompt.md"), false);
check("block .ai/instructions/ (SSOT)", write(".ai/instructions/operating-prompt/principles.md"), false);
check("block docs/architecture/ (ADRs)", write("docs/architecture/0011-git-ops.md"), false);
check("block .opencode/ (own contract — Claude is custodian)", write(".opencode/contract.md"), false);
check("block package.json", write("package.json"), false);
check("block near-miss '.githubfoo/'", write(".githubfoo/x.yml"), false);
check("block '.github' as a bare file", write(".github"), false);
check("block .github traversal escape to source", write(".github/../src/evil.js"), false);
check("block .github traversal escape to .claude", write(".github/workflows/../../.claude/agents/x.md"), false);

// Absolute form — the Claude write-guard was found (2026-07-11) to compare a
// `$(pwd)` prefix that never matched Windows absolutes, so an absolute path
// bypassed its territorial rules while its suite stayed green on relative paths
// only. These assert the same hole does not exist here.
check("block absolute source", write(path.join(ROOT, "src", "index.js")), false);
check("block absolute .claude/", write(path.join(ROOT, ".claude", "agents", "x.md")), false);
check("block absolute .kimi/", write(path.join(ROOT, ".kimi", "config.toml")), false);
check("block absolute .kiro/", write(path.join(ROOT, ".kiro", "steering", "x.md")), false);
check("block absolute .ai/instructions/", write(path.join(ROOT, ".ai", "instructions", "x.md")), false);
check("block absolute docs/architecture/", write(path.join(ROOT, "docs", "architecture", "x.md")), false);

// Backslash form (absolute + relative).
check(
  "block absolute backslash .claude/",
  write(path.join(ROOT, ".claude", "agents", "x.md").replace(/[/\\]/g, "\\")),
  false
);
check("block backslash .kimi/", write(".kimi\\config.toml"), false);
check("block backslash .ai/instructions/", write(".ai\\instructions\\x.md"), false);

// Mixed case — lane matching is case-SENSITIVE, so a case variant fails CLOSED
// (blocked) rather than sneaking into an allow rule. Asserted in both directions.
check("block mixed-case .GitHub/ (fail-closed)", write(".GitHub/workflows/gates.yml"), false);
check("block mixed-case .AI/reports/ (fail-closed)", write(".AI/Reports/r.md"), false);
check("block mixed-case .Claude/", write(".Claude/agents/x.md"), false);
check("block mixed-case SRC/", write("SRC/index.js"), false);
check("block bash redirect to mixed-case .GITHUB/", bash("echo x > .GITHUB/workflows/y.yml"), false);

// --- DENY: secrets (contract rule 5) — outranks every allow rule, including
// the newly widened .github/** subtree. ---
check("block .env at root", write(".env"), false);
check("block .env.production", write(".env.production"), false);
check("block secret inside .github/ (lane must not license it)", write(".github/deploy.key"), false);
check("block .pem inside .github/", write(".github/workflows/ci.pem"), false);
check("block id_rsa inside .ai/reports/", write(".ai/reports/id_rsa"), false);
check("block credentials.json inside .ai/handoffs/", write(".ai/handoffs/to-claude/open/credentials.json"), false);
check("block absolute .env", write(path.join(ROOT, ".env")), false);
check("block bash redirect to .env", bash("echo K=v > .env"), false);
check("allow ordinary .yml in .github (not a secret)", write(".github/workflows/keys.yml"), true);

// ===========================================================================
// Activity-log entry spool (ADR-0010 blocker, 2026-07-12) — .ai/activity/entries/**
// is writable. Without this the FIRST spool entry OpenCode ever writes is blocked
// by its own guard, silently, on day one. Additive: log.md must keep working, the
// migration has not happened yet.
// ===========================================================================

// --- ALLOW: the spool, in every path shape a tool might hand us ---
const ENTRY = "20260712T101500Z-opencode-blockers-a1b2.md";
check("allow spool entry (relative)", write(`.ai/activity/entries/${ENTRY}`), true);
check("allow spool entry (backslash)", write(`.ai\\activity\\entries\\${ENTRY}`), true);
check("allow spool entry (absolute)", write(path.join(ROOT, ".ai", "activity", "entries", ENTRY)), true);
check(
  "allow spool entry (absolute backslash)",
  write(path.join(ROOT, ".ai", "activity", "entries", ENTRY).replace(/[/\\]/g, "\\")),
  true
);
check("allow spool entry (./ prefix)", write(`./.ai/activity/entries/${ENTRY}`), true);
check("allow spool entry (via in-lane traversal)", write(`.ai/reports/../activity/entries/${ENTRY}`), true);
check("allow spool entry inside worktree", write(`.ai/activity/entries/${ENTRY}`, WT_ROOT), true);
check("allow spool entry nested subdir", write(".ai/activity/entries/2026-07/x.md"), true);
check("allow bash redirect into spool", bash(`echo x > .ai/activity/entries/${ENTRY}`), true);
check("allow bash tee into spool", bash(`cat e.md | tee .ai/activity/entries/${ENTRY}`), true);

// --- NO REGRESSION: the old path still works (it is still the live log) ---
check("allow .ai/activity/log.md (unchanged)", write(".ai/activity/log.md"), true);
check("allow .ai/activity/log.md backslash (unchanged)", write(".ai\\activity\\log.md"), true);
check("allow .ai/activity/log.md absolute (unchanged)", write(path.join(ROOT, ".ai", "activity", "log.md")), true);
check("allow bash redirect to log.md (unchanged)", bash("echo x >> .ai/activity/log.md"), true);

// --- DENY: the spool widening must not leak. It is ONE subtree, not `.ai/activity`. ---
check("block .ai/activity sibling file (not entries/)", write(".ai/activity/other.md"), false);
check("block .ai/activity/archive/ (deliberately NOT in lane)", write(".ai/activity/archive/2026-04.md"), false);
check("block near-miss '.ai/activity/entriesfoo/'", write(".ai/activity/entriesfoo/x.md"), false);
check("block '.ai/activity/entries' as a bare file", write(".ai/activity/entries"), false);
check("block .ai/ root file via spool sibling", write(".ai/known-limitations.md"), false);
check("block spool traversal escape to source", write(".ai/activity/entries/../../../src/evil.js"), false);
check(
  "block spool traversal escape to .claude",
  write(".ai/activity/entries/x/../../../../.claude/agents/x.md"),
  false
);
check("block spool traversal escape to SSOT", write(".ai/activity/entries/../../instructions/x.md"), false);
check("block mixed-case .ai/Activity/Entries/ (fail-closed)", write(".ai/Activity/Entries/x.md"), false);
check("block bash redirect to .ai/activity/archive/", bash("echo x > .ai/activity/archive/x.md"), false);
check("block secret inside the spool (rule 5 outranks the lane)", write(".ai/activity/entries/id_rsa"), false);
check("block .env inside the spool", write(".ai/activity/entries/.env.prod"), false);

// MSYS /c/... form: FAIL-CLOSED (blocked), not a bypass. path.resolve cannot map
// an MSYS drive path onto a Windows root, so it lands outside the project root and
// is denied. This is pre-existing behaviour shared by EVERY lane entry (`.ai/reports/**`
// behaves identically) — asserted here so a future "fix" that maps /c/ must prove it
// does not open a bypass. OpenCode emits repo-relative paths, so this is never hit
// in practice. See the report accompanying this change.
check("MSYS /c/ spool form is blocked (fail-closed, not a bypass)", write(`/c/proj/.ai/activity/entries/${ENTRY}`), false);
check("MSYS /c/ reports form blocked identically (pre-existing)", write("/c/proj/.ai/reports/r.md"), false);

// --- DENY: everything the widening must still keep out (re-asserted post-widening) ---
check("post-widening: still block src/", write("src/index.js"), false);
check("post-widening: still block .claude/", write(".claude/hooks/pretool-write-edit.sh"), false);
check("post-widening: still block .kimi/", write(".kimi/steering/00-ai-contract.md"), false);
check("post-widening: still block .kiro/", write(".kiro/agents/coder.json"), false);
check("post-widening: still block .ai/instructions/ (SSOT)", write(".ai/instructions/operating-prompt/principles.md"), false);
check("post-widening: still block docs/architecture/ (ADRs)", write("docs/architecture/0010-activity-log-entry-spool.md"), false);
check("post-widening: still block .opencode/", write(".opencode/plugin/framework-guard.js"), false);
check("post-widening: still block scripts/", write("scripts/git-hooks/pre-commit"), false);
check("post-widening: still block .env", write(".env"), false);

// --- ANTI-DRIFT: the lane in the docs must equal the lane in the guard. ---
// The doc/enforcement divergence IS the bug being fixed (contract promised the
// repo-ops lane, guard denied it). If they ever diverge again, this fails loudly.
const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");

function documentedLane(file) {
  const src = fs.readFileSync(path.join(REPO, file), "utf8");
  const block = src.match(/<!--\s*LANE:BEGIN[\s\S]*?-->\n([\s\S]*?)<!--\s*LANE:END\s*-->/);
  if (!block) return null;
  return block[1]
    .split("\n")
    .map((l) => l.match(/^\s*-\s*`([^`]+)`\s*$/))
    .filter(Boolean)
    .map((m) => m[1]);
}

for (const file of [".opencode/contract.md", "AGENTS.md"]) {
  let documented = null;
  try {
    documented = documentedLane(file);
  } catch (e) {
    documented = null;
  }
  const enforced = WRITABLE_LANE.join(", ");
  const found = documented ? documented.join(", ") : "<no LANE:BEGIN/LANE:END block found>";
  check(
    `lane in ${file} matches WRITABLE_LANE in framework-guard.js`,
    { allow: found === enforced, reason: `documented [${found}] != enforced [${enforced}]` },
    true
  );
}

// ===========================================================================
// LOAD-PATH TESTS (2026-07-12) — the invariant the plugin HOST requires.
//
// The 133 assertions above unit-test decide()/the lane; NONE of them load the
// module the way OpenCode does, so a total plugin-load failure shipped green:
// PR #45 added `export const WRITABLE_LANE = []` (an array) to framework-guard.js,
// and OpenCode's host — which globs `{plugin,plugins}/*.{ts,js}` and calls
// `if(!isFunction(export)) throw TypeError("Plugin export is not a function")`
// over EVERY top-level export — rejected the whole module, so nothing was
// lane-restricted at runtime. These tests reproduce the host's contract:
//   (1) every top-level export of every host-loaded plugin module is a function;
//   (2) the plugin actually INITIALIZES and its tool.execute.before hook blocks
//       out-of-lane writes and allows in-lane ones (the real end-to-end path);
//   (3) the WRITABLE_LANE data module is NOT in the plugin-load glob (so exporting
//       a non-function array from it can never break loading again).
// See .ai/reports/opencode-2026-07-12-guard-dead-plugin-load-failure.md.
// ===========================================================================

const PLUGIN_DIR = path.dirname(fileURLToPath(import.meta.url));
const OPENCODE_DIR = path.resolve(PLUGIN_DIR, "..");

// Mirror OpenCode's discovery glob `{plugin,plugins}/*.{ts,js}` (non-recursive,
// only .ts/.js — NOT .mjs, which is why test-guard.mjs itself is never loaded as
// a plugin). Returns absolute paths of every file the host would import as a plugin.
function hostLoadedPluginFiles() {
  const files = [];
  for (const dirName of ["plugin", "plugins"]) {
    const dir = path.join(OPENCODE_DIR, dirName);
    if (!fs.existsSync(dir)) continue;
    for (const name of fs.readdirSync(dir)) {
      if (/\.(ts|js)$/.test(name) && fs.statSync(path.join(dir, name)).isFile()) {
        files.push(path.join(dir, name));
      }
    }
  }
  return files;
}

async function checkAllExportsAreFunctions(absFile, label) {
  const mod = await import(pathToFileHref(absFile));
  const nonFns = Object.entries(mod).filter(([, v]) => typeof v !== "function");
  check(
    `${label}: every top-level export is a function (host invariant)`,
    { allow: nonFns.length === 0, reason: `non-function exports: ${nonFns.map(([k, v]) => `${k}=${typeof v}`).join(", ")}` },
    true
  );
}

function pathToFileHref(absPath) {
  // Cross-platform file:// URL so dynamic import() works on Windows too.
  let p = absPath.replace(/\\/g, "/");
  if (!p.startsWith("/")) p = "/" + p; // drive-letter form -> /C:/...
  return "file://" + encodeURI(p);
}

// (1) HOST INVARIANT — every plugin module the host globs exports only functions.
const hostFiles = hostLoadedPluginFiles();
check("host discovers exactly framework-guard.js as a plugin", { allow: hostFiles.length === 1 && /framework-guard\.js$/.test(hostFiles[0]) }, true);
for (const f of hostFiles) {
  await checkAllExportsAreFunctions(f, path.basename(f));
}

// (3) The WRITABLE_LANE data module must NOT be in the host's plugin-load path.
// It exports a non-function array on purpose; the load-bearing guarantee is that
// the host never imports it as a plugin. It lives at ../lib/lane.js, outside the
// `{plugin,plugins}/` glob.
const laneModule = path.resolve(OPENCODE_DIR, "lib", "lane.js");
check("lane.js data module exists at ../lib/lane.js", { allow: fs.existsSync(laneModule) }, true);
check("lane.js is NOT in the plugin-load glob", { allow: !hostFiles.some((f) => path.resolve(f) === laneModule), reason: `lane.js was globbed as a plugin: ${hostFiles.join(", ")}` }, true);
check("lane.js is outside any {plugin,plugins}/ dir", { allow: !/[\\/](plugins?)[\\/][^\\/]+$/.test(laneModule) }, true);

// (2) END-TO-END — initialize the plugin exactly like the host and drive its hook.
const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), "guard-loadtest-"));
const plugin = await FrameworkGuard({ directory: tmpRoot });
check("FrameworkGuard() returns an object", { allow: !!plugin && typeof plugin === "object" }, true);
const hook = plugin && plugin["tool.execute.before"];
check("plugin exposes a tool.execute.before hook function", { allow: typeof hook === "function" }, true);

async function hookAllows(filePath) {
  // Returns true if the hook lets the write through, false if it throws (BLOCKED).
  try {
    await hook({ tool: "write" }, { args: { filePath } });
    return true;
  } catch {
    return false;
  }
}

if (typeof hook === "function") {
  check("hook BLOCKS write src/x.js (must-block)", { allow: !(await hookAllows("src/x.js")) }, true);
  check("hook ALLOWS write .ai/reports/x.md (in-lane)", { allow: await hookAllows(".ai/reports/x.md") }, true);
  check("hook ALLOWS write .github/x.yml (repo-ops lane)", { allow: await hookAllows(".github/x.yml") }, true);
  check("hook BLOCKS write .env (secret, must-block)", { allow: !(await hookAllows(".env")) }, true);
  check("hook BLOCKS write .claude/x.md (other CLI territory)", { allow: !(await hookAllows(".claude/x.md")) }, true);
}

fs.rmSync(tmpRoot, { recursive: true, force: true });

console.log(`PASS ${pass} / FAIL ${fail} (total ${pass + fail})`);
if (fail > 0) {
  for (const f of failures) console.log("  FAIL:", f);
  process.exit(1);
}
