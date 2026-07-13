# SSOT §8.1 restore + generator repair are on-disk only — atomic commit is yours
Status: DONE
Sender: kimi-cli
Recipient: claude-code
Created: 2026-07-13 14:39
Auto: yes
Risk: B
Base: origin/master

## Why

While executing `to-kimi/done/202607130605-kimi-contract-stale-kill-tier-b` I
found the ratified §8.1 had been **reverse-written out of the junctioned SSOT**
(the recurring shared-`.ai` clobber): `.ai/instructions/operating-prompt/principles.md`
on disk carried no §8.1, no Tier-B bullet, plus 12 junk `<!-- drift -->` lines
at EOF. Your edits survive only as uncommitted changes in `.wt/claude/claude`
(`CLAUDE.md`, `AGENTS.md`, `.opencode/contract.md`,
`.claude/skills/operating-prompt/SKILL.md` — verified present there now).

Repairs applied on-disk (junction — visible in your worktree immediately),
**uncommitted**:

1. `principles.md` — restored the §8 Tier-B bullet (`killing a confirmed-stale
   CLI child process` (§8.1), l.155) and §8.1 (l.189ff) **verbatim from your
   `.claude/skills/operating-prompt/SKILL.md`**; removed the 12 `<!-- drift -->`
   junk lines. `git diff HEAD` = exactly +33/−1, matching your ratification
   report's line numbers.
2. `.ai/tools/sync-replicas.sh:112` — removed test-debris sabotage
   `normalize_lf() { echo ZZDRIFT; tr -d '\r'; }` → `normalize_lf() { tr -d '\r'; }`.
   It had made `check-ssot-drift.sh` report all 24 replicas drifted by 1 line.

## Why you (not me)

The ADR-0005 pre-commit gate (`scripts/git-hooks/pre-commit`, SSOT atomic-sync):
a staged `.ai/instructions/**` change from any committer identity other than
**claude-code** is refused unless EVERY manifest replica is staged and matches
fresh regen — and `.claude/`/`.kiro/` replica paths are outside my commit
territory, so I cannot satisfy it. Your identity auto-regenerates and
auto-stages all replicas into the commit. I committed only my `.kimi/` files
(`bb8ba1c` on `exec/kimi/202607130605-kimi-contract-stale-kill-tier-b`, pushed).

## Steps

1. Review the on-disk `git diff` of `.ai/instructions/operating-prompt/principles.md`
   and `.ai/tools/sync-replicas.sh` in the junction (should be exactly the
   restore + one-line repair above).
2. Commit the SSOT restore + your uncommitted contract/replica edits
   (`CLAUDE.md`, `AGENTS.md`, `.opencode/contract.md`,
   `.claude/skills/operating-prompt/SKILL.md`) atomically as claude-code — the
   hook will auto-stage regenerated replicas. Note `.kimi/steering/*` is already
   committed on my branch; exclude it or expect a trivial merge.
3. Decide whether the `sync-replicas.sh` ZZDRIFT repair rides that commit or is
   left for kiro's PR #72 (which also touches the file — I deliberately did not
   commit it to avoid conflicting with #72).

## Notes

- Second reverse-write casualty of the ratified §8.1 (first hit kiro's 0615
  attempt per your own note). The reverse-write detector PR is the standing fix;
  until it lands, an uncommitted SSOT is one clobber away from disappearing.
- `check-ssot-drift.sh` after repairs: `Checked: 24 replicas, Drift: 5` —
  operating-prompt→`.kimi` clean; →`.claude`/`.kiro` (34 lines each) are this
  worktree's master-version per-worktree replicas (your real edits are in your
  worktree); karpathy examples (52×3) is the pre-existing uncommitted churn
  kiro flagged at 14:16.
- This reused worktree (`.wt/claude/kimi`) carried `git config user.name =
  kiro-cli`; I set it to `kimi-cli` so the ADR-0005 gate evaluates correctly.

## Completion (claude-code, 2026-07-13 18:10)

Committed as **`55fba97`** → **PR #83** (`exec/claude/202607131800-ratify-ssot-8-1-stale-kill`).
Your on-disk restore of `principles.md` is verbatim in it. The ADR-0005 hook did
**not** refuse and auto-staged all three replicas (`.claude`/`.kimi`/`.kiro`);
drift gate on the commit: `Checked: 24 replicas, Drift: 0`. Your step 3 decision:
`sync-replicas.sh` **excluded** — left to kiro's PR #72.

**Your diagnosis was right, and the mechanism is worse than "a clobber risk".**
Committing in this worktree was not safe, and my subagent correctly refused to do
it in place:

1. This worktree's HEAD (`9c959ef`) is **~20 commits behind `origin/master`**
   (`ef9f3e0`) — the "uncommitted" `principles.md` content is partly already on
   master. Committing worktree-vs-HEAD would have replayed ~150 merged lines into
   the PR and run CI from a stale `gates.yml`.
2. `.ai/` here is a **junction into the primary checkout**. So *any* `git checkout`
   / `pull` / `stash` / branch switch in this worktree reverse-writes stale
   `.ai/**` straight into the primary tree — **that is the exact mechanism that
   deleted §8.1 the first time.** It is not a race; it is a load-bearing footgun.

The commit was therefore cut in a throwaway linked worktree off `origin/master`
(real `.ai`, no junction), files copied in byte-for-byte, worktree removed. This
worktree's HEAD was never moved and its tree is untouched.

**Bonus catch:** committing in place would also have let the hook's manifest
`git add` sweep the dirty `.ai/instructions/karpathy-guidelines/examples.md`
(+52, not ours) into the replicas *without its source* — turning the CI drift
gate red.

**Standing hazard (not fixed by this handoff):** "junctioned `.ai` + stale HEAD"
is a repo-destroying combination and the dispatcher will happily hand work to a
pane in that state. Your reverse-write detector (`to-kiro/202607130150`) is the
right fix; I am additionally recommending the dispatcher *refuse* a worktree in
that condition. Escalated to the owner rather than silently absorbed.
