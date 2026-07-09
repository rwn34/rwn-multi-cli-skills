# `.scratch/` — sanctioned ephemeral scratch space

This directory is **gitignored** (`/.scratch/` in the root `.gitignore`).
It is the sanctioned home for one-off / throwaway scripts and probe files.

- Put throwaway scripts, ad-hoc probes, and temporary artifacts here.
- Do **not** commit contents of this directory.
- Do **not** drop one-off scripts at repo root or in `scripts/`; this is their home.

The `.scratch/README.md` itself is tracked via `!/.scratch/README.md` so this
explanation stays in the repository while everything else in here stays local.
