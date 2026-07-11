# Kimi step-cap test (cap lowered to 5) — semantic word-chain, unscriptable
Status: DONE

<!-- TEST COMPLETE (claude-code, 2026-07-11): purpose achieved. Under a temporarily
     lowered cap (max_steps_per_turn=5, since restored to 100) real Kimi hit the cap
     mid-chain and the pane-runner auto-continued 8x (Continues=8, Invocations=9),
     resuming the shiritori chain from disk each turn (apple->elephant->tree->engine
     ->egg->garden->nest->train). It MAXED at word-08 only because MaxContinues=8 was
     less than the 12-word chain length — the cap->reinvoke->resume MECHANISM is
     proven, and the MAXED->ALERT safety valve fired (Telegram alert sent). Marked
     DONE in place to stop re-pickup; the done-reconciler relocates it to done/. -->

Sender: claude-code
Recipient: kimi-cli
Created: 2026-07-11 14:40
Auto: yes
Risk: A

<!-- Protocol v3. DELIBERATE step-cap test, take 3. The runner is running you with
     max_steps_per_turn TEMPORARILY lowered to 5 (restored to 100 right after this
     test). Earlier takes failed because arithmetic/count tasks are collapsible into
     one shell loop or one parallel batch, so the step counter never climbed. This
     task is a SEMANTIC word-chain: each word requires model judgment (a shell loop
     cannot pick a valid English word), and a mandatory read-back between writes
     blocks parallel batching. So you WILL exceed 5 steps in a turn, the turn will
     end on its own mid-chain, the runner re-invokes you, and you resume from the
     files on disk. Hitting the cap mid-task is EXPECTED and correct — do not try to
     avoid it. Everything is in .scratch/ (gitignored); nothing is committed. -->

## Goal
Force Kimi past the (temporarily lowered) 5-step per-turn cap so the pane-runner's
auto-continue path fires, then resume the word-chain from disk and finish it. This
validates cap -> re-invoke -> resume with real Kimi.

## Current state
- Scratch dir may not exist: `.scratch/kimi-cap5-test/` (repo root, gitignored via `/.scratch/*`).
- No `word-NN.txt` files yet (fresh run) OR some exist from an interrupted turn (resume).

## Target state
- `.scratch/kimi-cap5-test/` contains exactly 12 files: `word-01.txt` … `word-12.txt`.
- Each contains ONE lowercase common English noun. `word-01.txt` = `apple`. For every
  N>1, the FIRST letter of the word in `word-NN.txt` equals the LAST letter of the
  word in `word-(NN-1).txt` (a shiritori/word-chain), and no word repeats in the chain.

## Steps
1. Ensure `.scratch/kimi-cap5-test/` exists.
2. Determine the RESUME point: find the highest-numbered `word-NN.txt` that exists.
   - None exist: write `word-01.txt` containing `apple`. Now the last link is N=1.
   - Some exist: read the highest one; that word's LAST letter drives the next word.
3. Extend the chain ONE WORD AT A TIME, for N from (last+1) up to 12:
   - **Read** `word-(N-1).txt` and note its last letter L.
   - **Choose** a common English noun (lowercase, singular) that starts with L and has
     NOT been used earlier in this chain — this is a judgment only you can make.
   - **Write** it to `word-NN.txt` (2-digit zero-padded filename).
   - **Read `word-NN.txt` back** to confirm it was written before moving on.
   - Do NOT use bash/PowerShell/scripts/loops, and do NOT write multiple words in one
     batch. One word per step, reading the predecessor each time. Running out of steps
     mid-chain is the point — the runner will continue you.
4. When `word-12.txt` exists and the chain is valid (verify below), set Status to
   `DONE` and move this file to `.ai/handoffs/to-kimi/done/`.

## Verification
- (a) EXECUTE a count: `.scratch/kimi-cap5-test/` has exactly 12 `word-*.txt` files. Paste it.
- (b) EXECUTE a chain check: list all 12 words in order and confirm each word's first
      letter equals the previous word's last letter, with no repeats. Paste the list.

## Next step / future note
If this STILL shows Continues=0, the model precomputed the whole chain and batch-wrote
despite the read-back rule — escalate to a treasure-hunt design where each next
filename is only revealed by solving the current step. First thing that breaks: the
cap is only lowered to 5 for THIS test; it is restored to 100 immediately after, so
re-running this handoff later (at cap 100) will complete in one turn (Continues=0).

## Activity log template
    ## 2026-07-11 HH:MM — kimi-cli
    - Action: per handoff 202607111440-kimi-cap5-wordchain — built 12-word shiritori chain (cap-5 test), resumed across N continue(s)
    - Files: .scratch/kimi-cap5-test/word-*.txt (gitignored)
    - Decisions: <did you hit the 5-step cap? at roughly which word did a turn end?>

## Report back with
- (a) file count in `.scratch/kimi-cap5-test/` (pasted output).
- (b) the ordered 12-word chain (pasted).
- (c) whether you hit the 5-step cap and roughly which word each turn ended on.

## When complete (protocol v3)
Set Status to `DONE` and move this file to `.ai/handoffs/to-kimi/done/` yourself once
all 12 words exist and the chain is valid. If blocked, leave it in `open/`, set Status
`BLOCKED`, and append a `## Blocker` section with verbatim errors.
