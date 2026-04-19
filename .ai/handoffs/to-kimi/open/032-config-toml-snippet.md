# Draft config.toml snippet to wire bash guards
Status: OPEN
Sender: claude-code
Recipient: kimi-cli
Created: 2026-04-19 19:15

## Goal
Per handoff 031 finding (activity-log 2026-04-19 22:30) and handoff 018
(to-claude), Kimi's 4 bash guard scripts exist and pass pipe-tests but are NOT
wired into `~/.kimi/config.toml`. Only `safety-check.ps1` is active. User
must paste a snippet into the global config to wire the guards — and you know
Kimi's exact `[[hooks]]` syntax, I don't.

**Action:** write a paste-ready snippet the user can add to their
`~/.kimi/config.toml`.

## Steps

1. Create new file: `.ai/config-snippets/kimi-hooks.toml` (new directory
   `.ai/config-snippets/` is fine — framework territory).

2. Populate with a `[[hooks]]` block (or blocks, however Kimi's syntax wants)
   that wires all 4 guards:
   - `.kimi/hooks/root-guard.sh` on whatever event fires before `fs_write`
   - `.kimi/hooks/framework-guard.sh` on same
   - `.kimi/hooks/sensitive-guard.sh` on same
   - `.kimi/hooks/destructive-guard.sh` on whatever event fires before
     `execute_bash` / Shell

3. Prepend header comments explaining:
   - What this file is (paste-ready snippet).
   - How to use (append to `~/.kimi/config.toml`).
   - What it enforces (the 4 guards and their scope).
   - Any caveat about the existing `safety-check.ps1` — whether these new
     hooks run alongside, before, or after it. If coverage overlaps
     (destructive-guard vs. safety-check), document which one is
     authoritative OR whether the user should keep both.

4. Also note in the header:
   - The hooks use paths relative to the project root. If the user's Kimi
     session starts in a different directory, the relative paths won't
     resolve. Either document that requirement or suggest absolute paths /
     environment variable expansion if Kimi supports it.

5. Update `.kimi/hooks/README.md` with a pointer to
   `.ai/config-snippets/kimi-hooks.toml` so future readers know the wiring
   step exists.

## Verification
- (a) `.ai/config-snippets/kimi-hooks.toml` exists and is syntactically valid
  TOML.
- (b) Snippet uses the exact event names from Kimi's 13-event hook taxonomy
  (per your doc-review in handoff 018).
- (c) Comments explain safety-check.ps1 coexistence.
- (d) README updated.

## Activity log template
    ## YYYY-MM-DD HH:MM — kimi-cli
    - Action: Drafted paste-ready config.toml snippet for bash guards (per handoff 032)
    - Files: .ai/config-snippets/kimi-hooks.toml (new), .kimi/hooks/README.md (edit)
    - Decisions: <event-name choices, safety-check.ps1 coexistence call>

## Report back with
- (a) Path to the snippet.
- (b) Quick summary of event names used and why.
- (c) Any coverage-overlap notes between new bash guards and
  existing safety-check.ps1 — and your recommendation.

## When complete
Sender reads snippet, validates TOML shape, then surfaces to user with a
paste instruction. Move this handoff to done/.
