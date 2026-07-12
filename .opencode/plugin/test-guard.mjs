// Standalone test harness for framework-guard's decision function.
// Run: node .opencode/plugin/test-guard.mjs
import { decide, WRITABLE_LANE } from "./framework-guard.js";
import path from "node:path";
import fs from "node:fs";
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

console.log(`PASS ${pass} / FAIL ${fail} (total ${pass + fail})`);
if (fail > 0) {
  for (const f of failures) console.log("  FAIL:", f);
  process.exit(1);
}
