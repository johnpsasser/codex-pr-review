#!/usr/bin/env bash
# tests/test-threshold-penalty.sh — regression test for the threshold-vs-penalty
# "double-jeopardy" fix (commit a976765).
#
# Background:
#   Inconclusive findings (agreement = unconfirmed-by-codex / unconfirmed-by-
#   claude) get a ×0.7 DISPLAY penalty applied to `confidence_score` so the PR
#   comment communicates uncertainty. But the threshold filter that decides
#   whether a finding is surfaced at all must gate on the PRE-penalty value,
#   carried as `original_confidence_score`. Otherwise a genuinely high-
#   confidence-but-unconfirmed finding (orig 0.9, displayed 0.63) is unwinnable
#   against the default 0.8 threshold and silently disappears — the bug the fix
#   addresses.
#
# This test reproduces the exact gating jq filter used in review.sh and asserts
# the count is correct. The filter is COPIED VERBATIM from review.sh so this
# test fails if the script's filter regresses (e.g. someone reverts it to gate
# on .confidence_score). See:
#   scripts/review.sh:2409 (format_comment)
#   scripts/review.sh:2575 / 2960 / 2969 (summary JSON builder / single path)
# all four use the identical expression:
#   [.findings[] | select(((.original_confidence_score // .confidence_score) // 0) >= ($t | tonumber))] | length
#
# Usage:  bash tests/test-threshold-penalty.sh
# Exit:   0 if all assertions pass; 1 on the first failure.
# Needs:  jq only (fully hermetic — no codex/claude/gh required).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPTS_DIR="$REPO_ROOT/scripts"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0
fail_messages=()

assert() {
  local cond="$1"; shift
  local msg="$*"
  if eval "$cond"; then
    pass=$((pass + 1))
    printf '  ok  %s\n' "$msg"
  else
    fail=$((fail + 1))
    fail_messages+=("$msg")
    printf '  FAIL %s (cond: %s)\n' "$msg" "$cond"
  fi
}

# ─── Guard: the filter we copy below must still exist verbatim in review.sh ──
# This makes the test self-policing: if review.sh's filter drifts, the guard
# fails loudly rather than the copied filter silently going stale.
echo "Test 0: review.sh still contains the original_confidence_score gating filter"
GATING_FILTER='[.findings[] | select(((.original_confidence_score // .confidence_score) // 0) >= ($t | tonumber))] | length'
assert "grep -Fq '$GATING_FILTER' \"$SCRIPTS_DIR/review.sh\"" \
  "review.sh contains the exact gating filter (regression sentinel)"

# ─── Build the findings fixture ─────────────────────────────────────────────
# (a) unconfirmed, high pre-penalty confidence, penalized display confidence.
#     orig 0.9 >= 0.8 → KEEP (the bug would drop this because 0.63 < 0.8).
# (b) confirmed finding, no original_confidence_score; falls back to
#     confidence_score 0.85 >= 0.8 → KEEP.
# (c) low-confidence finding, orig 0.5 < 0.8 → DROP.
# Expected surviving count at THRESHOLD=0.8: 2.
findings="$WORK/findings.json"
cat > "$findings" <<'JSON'
{
  "findings": [
    {
      "title": "Unconfirmed high-confidence bug",
      "body": "Codex flagged this; Claude could not confirm it.",
      "code_location": {"path": "a.py", "start_line": 10, "end_line": 10},
      "category": "correctness",
      "priority": 2,
      "confidence_score": 0.63,
      "original_confidence_score": 0.9,
      "status": "new",
      "source": "codex",
      "verifier_verdict": "inconclusive",
      "agreement": "unconfirmed-by-claude"
    },
    {
      "title": "Confirmed bug (no original_confidence_score)",
      "body": "Both families agree.",
      "code_location": {"path": "b.py", "start_line": 20, "end_line": 20},
      "category": "correctness",
      "priority": 2,
      "confidence_score": 0.85,
      "status": "new",
      "source": "codex",
      "verifier_verdict": "confirmed",
      "agreement": "both"
    },
    {
      "title": "Genuinely low-confidence finding",
      "body": "Below threshold even pre-penalty.",
      "code_location": {"path": "c.py", "start_line": 30, "end_line": 30},
      "category": "maintainability",
      "priority": 1,
      "confidence_score": 0.35,
      "original_confidence_score": 0.5,
      "status": "new",
      "source": "claude",
      "verifier_verdict": "inconclusive",
      "agreement": "unconfirmed-by-codex"
    }
  ],
  "overall_correctness": "needs-changes",
  "overall_confidence_score": 0.85,
  "overall_explanation": "Mixed.",
  "review_iteration": 1,
  "resolved_prior_findings": []
}
JSON

THRESHOLD="0.8"

# ─── Test 1: the gating filter keeps (a) and (b), drops (c) ─────────────────
echo "Test 1: gating on original_confidence_score keeps 2 at THRESHOLD=0.8"
# COPIED VERBATIM from scripts/review.sh:2409 (and :2575/:2960/:2969). Do NOT
# "simplify" this — it must mirror the script byte-for-byte.
filtered_count=$(jq --arg t "$THRESHOLD" \
  '[.findings[] | select(((.original_confidence_score // .confidence_score) // 0) >= ($t | tonumber))] | length' \
  "$findings")
assert "[[ \"$filtered_count\" -eq 2 ]]" \
  "filter keeps 2 findings (the unconfirmed-but-high (a) + confirmed (b)) (got $filtered_count)"

# ─── Test 2: the surviving set is exactly (a) and (b), not (c) ──────────────
echo "Test 2: survivors are (a) and (b); (c) is dropped"
survivors="$WORK/survivors.json"
jq --arg t "$THRESHOLD" \
  '[.findings[] | select(((.original_confidence_score // .confidence_score) // 0) >= ($t | tonumber))]' \
  "$findings" > "$survivors"
assert "jq -e '[.[].title] | contains([\"Unconfirmed high-confidence bug\"])' \"$survivors\" >/dev/null" \
  "unconfirmed-but-high finding (a) survives"
assert "jq -e '[.[].title] | contains([\"Confirmed bug (no original_confidence_score)\"])' \"$survivors\" >/dev/null" \
  "confirmed finding (b) survives"
assert "jq -e '[.[].title] | contains([\"Genuinely low-confidence finding\"]) | not' \"$survivors\" >/dev/null" \
  "low-confidence finding (c) is dropped"

# ─── Test 3: double-jeopardy guard — the BUGGY filter would wrongly drop (a) ─
# Demonstrates the regression the fix prevents: gating on the post-penalty
# .confidence_score alone keeps only (b), so the fix's filter must NOT match
# this count.
echo "Test 3: the pre-fix (post-penalty) filter would keep only 1 — proving the fix matters"
buggy_count=$(jq --arg t "$THRESHOLD" \
  '[.findings[] | select(((.confidence_score) // 0) >= ($t | tonumber))] | length' \
  "$findings")
assert "[[ \"$buggy_count\" -eq 1 ]]" \
  "post-penalty-only gating keeps only the confirmed finding (got $buggy_count)"
assert "[[ \"$filtered_count\" -ne \"$buggy_count\" ]]" \
  "the correct filter and the buggy filter disagree (2 vs 1), confirming the fix is load-bearing"

# ─── Summary ─────────────────────────────────────────────────────────────────
echo
echo "Results: $pass passed, $fail failed"
if [[ "$fail" -gt 0 ]]; then
  echo "Failures:"
  for m in "${fail_messages[@]}"; do echo "  - $m"; done
  exit 1
fi
exit 0
