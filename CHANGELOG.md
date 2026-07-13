# Changelog

## [Unreleased]

Post-2.0.0 correctness fixes to the verifier, confidence threading, and the
installer/docs.

### Changed

- **Default models bumped to the current generation.** The Codex reviewer now
  defaults to `gpt-5.6-sol` (was `gpt-5.3-codex`), and the Claude reviewer,
  verifier, and escalation verifier now default to `claude-opus-4-8` (was
  `claude-opus-4-7`). All remain overridable via `--model-codex`,
  `--model-claude`, and `--model-verifier`.

### Fixes

- **Verifier reads files at the PR head SHA, not local HEAD.** The cross-family
  grounded verifier now fetches the file contents at the PR's head commit rather
  than whatever happens to be checked out locally, so verification is grounded
  in the code under review.
- **Read `.structured_output` from the claude CLI envelope.** The Claude-side
  verifier/reviewer output is wrapped in a CLI envelope; the parser now reads
  `.structured_output` from it instead of mis-parsing the envelope itself.
- **Capture `verifier_evidence` on findings.** Each finding now carries the
  verifier's evidence string as a diagnostic so it's possible to see *why* a
  finding was confirmed, refuted, or left inconclusive.
- **Confidence threadthrough finished.** Rendering and the stdout summary now use
  `original_confidence_score` (the pre-penalty value) consistently, matching the
  threshold filter so unconfirmed-but-high-confidence findings still surface.
- **Threshold-vs-penalty double-jeopardy fixed; Opus is the default verifier.**
  The `0.7×` penalty for `[unconfirmed-by-X]` findings is now applied only for
  display, and the threshold filter checks the pre-penalty score (no double
  penalty). The default `--model-verifier` is now `claude-opus-4-7`
  (`claude-haiku-4-5` remains a cheaper override).

### Audit fixes (installer + docs)

- **Installer hardening.** `install.sh` now runs under `set -euo pipefail`,
  installs transactionally (stages into a temp dir and atomically swaps into
  place so a partial failure never destroys the existing install), guards the
  node major-version parse against empty/non-numeric output, and tees
  `npm install` output to `scripts/npm-install.log` for debuggability.
- **Removed the fictional v1 rollback.** `install.sh --version 1` previously
  claimed to roll back to a v1 pipeline but only copied the current (v2)
  `review.sh` after deleting its own backup; there is no v1 source in the repo.
  The `--version` flag and all rollback claims have been removed from the
  installer and docs.
- **Doc corrections.** README's `--model-verifier` default corrected to
  `claude-opus-4-7`; the "vendored grammars" claim corrected to "tree-sitter
  bindings installed via npm into `scripts/node_modules/`"; and "silently
  no-ops" corrected to "no-ops (with a note on stderr)" to match
  `det-floor.sh`.

## v2.0.0 — 2026-05-05

The v2 release ships the dual-family pipeline (Codex + Claude Opus), the cross-family grounded verifier, AST-aware chunking, the deterministic floor, three iteration modes (initial / followup-after-fixes / delta-since-prior), and the post-synthesis location validator.

### Breaking changes

- **`overall_correctness` enum changed.** The output schema's `overall_correctness` field now uses the v2 enum:
  - `correct`
  - `needs-changes`
  - `blocking`
  - `insufficient information`
  - The v1 values (`patch is correct` / `patch is incorrect`) are no longer accepted by the schema. Downstream callers that string-match the verdict must update their checks.
  - **Compatibility shim:** `format_comment()` maps any v1 verdict it sees to the v2 enum at render time, so a v1-shaped Codex output flowing through v2 (e.g., a `--no-verify` debug run) still produces correctly-rendered output.
- **`suggested_fix` is now required on every finding.** The synthesis step generates this field from the verifier metadata. Downstream callers that read findings and don't tolerate a new required field need to update.

### New features

- **Dual-family review.** Codex (`gpt-5.3-codex`) and Claude Opus (`claude-opus-4-7`) review every chunk in parallel. `--max-parallel` defaults to 4 (was 6 in v1) so the doubled per-chunk concurrency stays inside Codex CLI's process limits.
- **Cross-family grounded verifier.** Every LLM finding is verified by the *other* family's grounded verifier (Claude Haiku 4.5 verifies Codex findings; Codex CLI verifies Claude findings). Refuted findings are dropped; inconclusive findings escalate to Opus, then post as `[unconfirmed-by-X]` if escalation also can't confirm. `--no-verify` bypasses verification (debug only).
- **AST-aware chunker** for Python / TypeScript / Go via tree-sitter bindings installed via npm into `scripts/node_modules/` during install. Snaps chunk boundaries to function/class boundaries instead of mid-hunk. Hunk-aware AWK chunker remains the fallback.
- **Per-chunk neighbors manifest** — every symbol referenced in a chunk but defined elsewhere in the PR is listed for the reviewer, eliminating cross-chunk "undefined symbol" false positives.
- **Deterministic floor.** Lint / typecheck / test runs on changed lines, configurable via `.codex-pr-review.toml`. Findings tagged `[deterministic]`; skip the cross-family verifier (tools don't hallucinate).
- **Iteration modes.** `--mode auto|initial|followup|delta`. Default `auto` classifies each run via `git log $prior_sha..HEAD` commit messages. Delta mode reviews only commits since the prior review SHA.
- **Location validator.** Deterministic post-synthesis filter (`scripts/location-validator.sh`) drops findings whose `(file, line)` does not resolve in the diff, with a maintainability exception for findings that cite unchanged-but-related lines in touched files. Below-threshold and empty-body findings are also dropped.
- **Agreement labels** in the PR comment: `[both]` / `[codex-only]` / `[claude-only]` / `[deterministic]` / `[unconfirmed-by-codex]` / `[unconfirmed-by-claude]`.
- **v2 sentinel** `<!-- codex-pr-review:meta v=2 sha=... iteration=... findings=... verdict=... mode=... prior_sha=... -->` is the primary iteration-tracking signal. The legacy `CODEX_REVIEW_DATA_START/END` JSON block is preserved for back-compat with prior PR comments.
- **Synthesis prompt rewrite (P5).** Synthesis is now a pure merge/dedupe/label step — explicitly forbidden from re-reading the diff to discover new findings (the v1 hallucination root cause). The prompt's CRITICAL CONSTRAINT block enforces this.
- **stdout summary JSON** adds `verdict` (v2 enum), `verdict_raw` (pre-shim), `mode`, `agreement_summary` (per-label counts), and `delta` (for follow-up runs).

### Fixes

- `chunk-diff.awk` mid-hunk split bug: chunks produced by mid-hunk splits now correctly start with the `@@ -a,b +c,d @@` header so reviewers see line-number context.

### Migration path

- **Default install is v2.** `./install.sh` installs the v2 dual-family pipeline. There is no v1 rollback path — the repo no longer ships a v1 pipeline source.
- **PR comments remain bilingual.** v2 comments contain both the v2 sentinel and the legacy `CODEX_REVIEW_DATA_START` block, so older tooling that reads the legacy block still finds it.
- **Schema impact.** Downstream callers that string-match the v1 verdict (`patch is correct` / `patch is incorrect`) must add the v2 mapping (`correct` / `needs-changes` / `blocking` / `insufficient information`). The `tests/test-schema-backcompat.sh` test suite gates this.

## v1.x

See git log up to commit `c37d9d2` for the v1 history. v1 ships a single-Codex pipeline with hunk-aware chunking, a single synthesis call, and a self-verification pass.
