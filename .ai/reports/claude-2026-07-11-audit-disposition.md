# Latent-Issue Audit — Disposition (2026-07-11)

Companion to `claude-2026-07-11-latent-issue-audit.md`. Records what was fixed,
deferred, and accepted, so a future audit doesn't re-flag settled items.

## Fixed + shipped
| Audit # | Sev | Finding | Fix | Landed |
|---|---|---|---|---|
| #1, #2 | CRITICAL | Handoff filename → `Invoke-Expression`/`eval` command injection (pane-runner + dispatcher) | Native argv invocation (`& $exe @rest` / `"${HEADLESS_ARGV[@]}"`); filename is inert data. Proven with a `$(touch pwned)` filename fixture in both languages — nothing executes. | PR #31, v0.0.12 |
| #10 | MED | Non-atomic bash claim write vs PS empty-claim read (race) | `acquire_claim` writes temp then atomic publish (`ln`/`mv -f`). | PR #31, v0.0.12 |
| #4 | MED | Pre-commit guards fail-OPEN on case-insensitive FS (`.ENV`, `ID_RSA`, `.Kimi/`) | `_lc` lowercase-normalize before matching in sensitive/tombstone/territory checks. 50 guard tests pass. | PR #32, v0.0.13 |
| #6 | MED | Update-mode `rm -rf` wipes `.ai/research/` + `.claude/settings.local.json` | Added both to the preserve/restore set. | PR #32, v0.0.13 |
| #5 | MED | Version-bump allowlist missed now-shipped `fleet-init.sh` + `sync-4ai-panes-install.ps1` | Added to `is_versioned`. | PR #32, v0.0.13 |

## Accepted risk (by design — owner-confirmed 2026-07-11)
- **#3 (HIGH) — handoffs auto-run off a self-declared `Risk:` field with no signature/provenance.**
  The owner confirmed this repo is written ONLY by the owner and the owner's own
  CLIs — a single-trust-domain repo. Handoff files in `to-*/open/` are therefore
  TRUSTED repo content, the same trust model as any script in the tree. No
  provenance/signing is warranted. **Revisit only if the threat model changes**
  (untrusted/third-party handoff authors, shared automation writing to `open/`):
  at that point spec a signature/provenance ADR. The command-injection fix (#1/#2)
  already removes the "crafted filename → RCE" teeth regardless of trust domain.

## Deferred (real but low-severity; logged, not blocking)
- **find_python** can't detect the Windows `WindowsApps` python stub → a silent MCP
  no-op reported as success. Fix: probe the stub / require a real interpreter.
- **reconcile_block** can truncate a global config to EOF on a hand-mangled sentinel
  order. Fix: validate sentinel pairing before rewriting; refuse on mismatch.
- **Version-bump gate** is PR-scoped; direct master pushes skip it. Low risk given
  the merge-via-PR norm; note for whoever changes the push policy.
- **Release asset-count guard** is a bare `== 4` equality — can't catch a wrong-but-
  still-4 asset set, and needs manual update if a 5th asset is added. Evolve into a
  name+tag manifest assertion before the asset set next changes.
- **notify throttle** state is a single shared JSON (last-writer-wins) + resets per
  supervised respawn is now file-backed but still one blob; go per-key if pane
  concurrency grows. (Fail-open toward SENDING, never silencing — safe direction.)

## Confirmed solid (do NOT "fix")
`AI_HANDOFF_DISPATCH` recursion guard (consistent across CLIs); pre-commit
fail-CLOSED identity discipline (the "spoofing" is by-design committer selection,
not a hole); release.yml idempotency skip + concurrency; post-* hooks never block;
supervisor backoff math.
