#!/bin/bash
# check-ssot-drift.sh — COMPATIBILITY SHIM (2026-07-13).
#
# The SSOT drift check now lives in the ONE generator, .ai/tools/sync-replicas.sh
# (--check mode): same registry, same transform, same regenerate-and-diff — one
# drift authority instead of two scripts that could disagree (ADR-0005 second
# amendment). This shim keeps every existing caller (CI muscle memory, docs,
# SSOT references) working with the IDENTICAL output contract and exit codes:
#   DRIFT: <src> -> <dst> (N lines differ)   per drifted replica
#   MISSING: <path>                          per absent file
#   Checked: <N> replicas, Drift: <M>        final summary
# Exit 0 iff Drift == 0.
#
# New call sites should use the authoritative entry point directly:
#   bash .ai/tools/sync-replicas.sh --check

exec bash "$(dirname "$0")/sync-replicas.sh" --check "$@"
