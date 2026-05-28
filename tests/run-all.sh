#!/usr/bin/env bash
# tests/run-all.sh — aggregate test runner for the codex-pr-review skill.
#
# Discovers and runs every tests/test-*.sh (except itself), each in a clean
# subshell so one test's environment cannot leak into the next. Prints a
# per-file PASS/FAIL line and a final "N passed, M failed" summary. Exits
# non-zero if any test failed.
#
# We intentionally use `set -uo pipefail` (NOT -e): a failing test must not
# abort the whole run — we capture each test's exit code and continue.
#
# Tests run sequentially (simplest correct behavior). The script is safe to
# invoke in parallel with other copies of itself because every test creates
# its own mktemp -d work dir; nothing here writes to shared state.
#
# Env knobs:
#   TESTS_FILTER   Substring filter — only run tests whose path contains it.
#   CI             When set (any value), CI mode: only hermetic tests run with
#                  their default (no-network) settings. The runner never sets
#                  RECORD=1, so the live-network branch in test-verifier.sh
#                  stays dormant. See the note below.
#
# Hermetic-by-default guarantee:
#   All six bundled tests are hermetic when run with no extra env. The only
#   network path in the suite is test-verifier.sh's Test 5, which is gated
#   behind RECORD=1. We explicitly unset RECORD here so an inherited RECORD=1
#   from a developer shell can never make CI hit the Anthropic API.
#
# Usage:  bash tests/run-all.sh
#         TESTS_FILTER=threshold bash tests/run-all.sh
# Exit:   0 if all selected tests pass; 1 if any failed (or none matched).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$(basename "${BASH_SOURCE[0]}")"

# Never let a developer's RECORD=1 leak into the suite and trigger live API
# calls. Tests that want a live mode must be invoked directly, not via run-all.
unset RECORD

filter="${TESTS_FILTER:-}"

# Collect candidate tests deterministically (sorted) so output order is stable.
tests=()
while IFS= read -r f; do
  tests+=("$f")
done < <(find "$SCRIPT_DIR" -maxdepth 1 -name 'test-*.sh' -type f | LC_ALL=C sort)

total=0
passed=0
failed=0
failed_names=()

for t in "${tests[@]}"; do
  name="$(basename "$t")"
  [[ "$name" == "$SELF" ]] && continue
  if [[ -n "$filter" && "$name" != *"$filter"* ]]; then
    continue
  fi

  total=$((total + 1))
  echo "════════════════════════════════════════════════════════════════"
  echo "▶ $name"
  echo "════════════════════════════════════════════════════════════════"

  # Run each test in a clean subshell. `bash "$t"` already gives a fresh
  # process (so exported env from one test can't survive into the next), and
  # the explicit ( ) groups any output handling without affecting our own
  # shell options. We capture the exit code without tripping `set -e` (we use
  # -uo pipefail, not -e) so a failure is recorded and the loop continues.
  rc=0
  ( bash "$t" ) || rc=$?

  if [[ "$rc" -eq 0 ]]; then
    passed=$((passed + 1))
    echo "── PASS: $name"
  else
    failed=$((failed + 1))
    failed_names+=("$name (exit $rc)")
    echo "── FAIL: $name (exit $rc)"
  fi
  echo
done

echo "════════════════════════════════════════════════════════════════"
echo "Summary: $passed passed, $failed failed (of $total run)"
if [[ "$failed" -gt 0 ]]; then
  echo "Failed tests:"
  for n in "${failed_names[@]}"; do
    echo "  - $n"
  done
fi
echo "════════════════════════════════════════════════════════════════"

# If a filter matched nothing, treat that as a failure so a typo in
# TESTS_FILTER doesn't silently "pass".
if [[ "$total" -eq 0 ]]; then
  echo "No tests matched (filter: '${filter}')." >&2
  exit 1
fi

[[ "$failed" -eq 0 ]] || exit 1
exit 0
