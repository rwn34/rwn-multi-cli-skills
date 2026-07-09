// Standalone test harness for framework-guard's decision function.
// Run: node .opencode/plugin/test-guard.mjs
import { decide } from "./framework-guard.js";

const ROOT = "C:\\proj";
const WT_ROOT = "C:\\parent\\.wt\\projX\\kimi";
const FLEET_ROOT = "C:\\fleet\\projA";

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
check("allow absolute in-lane write", write("C:\\proj\\.ai\\reports\\r.md"), true);
check("block .ai/activity sibling", write(".ai/activity/other.md"), false);
check("block src/ write", write("src/evil.txt"), false);
check("block CRUSH.md write", write("CRUSH.md"), false);
check("block absolute outside root", write("C:\\elsewhere\\evil.txt"), false);

// --- traversal / backslash normalization ---
check("block ../ traversal", write("../outside.md"), false);
check("block in-lane prefix escaping via ..", write(".ai/reports/../../src/evil.txt"), false);
check("block backslash variant", write("src\\evil.txt"), false);
check("block backslash traversal", write("..\\..\\outside.md"), false);
check("allow backslash in-lane", write(".ai\\reports\\ok.md"), true);

// --- fleet whitelist (ADR-0004) ---
check(
  "allow fleet whitelisted",
  write("C:\\fleet\\.fleet\\handoffs\\to-projB\\202607091200-x.md", FLEET_ROOT, registryOk),
  true
);
check(
  "block fleet non-whitelisted",
  write("C:\\fleet\\.fleet\\handoffs\\to-projC\\202607091200-x.md", FLEET_ROOT, registryOk),
  false
);
check(
  "block fleet missing registry (fail-closed)",
  write("C:\\fleet\\.fleet\\handoffs\\to-projB\\x.md", FLEET_ROOT, registryMissing),
  false
);

// --- worktree confinement (ADR-0004) ---
check("block worktree absolute escape", write("C:\\parent\\other.md", WT_ROOT), false);
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
check("allow read outside project root", read("C:\\elsewhere\\notes.md"), true);
check("allow read escaping worktree", read("C:\\parent\\other.md", WT_ROOT), true);
check("allow edit-tool alias 'patch' still lane-restricted", decide({ tool: "patch", args: { filePath: "src/evil.txt" }, root: ROOT }), false);

// --- non-write tools pass through ---
check("allow read-ish tool (no filePath)", decide({ tool: "grep", args: { pattern: "x" }, root: ROOT }), true);

console.log(`PASS ${pass} / FAIL ${fail} (total ${pass + fail})`);
if (fail > 0) {
  for (const f of failures) console.log("  FAIL:", f);
  process.exit(1);
}
