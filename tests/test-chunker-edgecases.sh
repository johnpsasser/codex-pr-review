#!/usr/bin/env bash
# tests/test-chunker-edgecases.sh — chunk-diff.awk count-invariant edge cases.
#
# Regression test for the awk off-by-one fix (see scripts/chunk-diff.awk header
# comment: "the count written to chunk_count.txt MUST equal the number of
# chunk_NNN.diff files that actually received content"). We exercise two shapes
# that historically tripped the off-by-one:
#   1. A deletes-only diff (a hunk whose body is entirely `-` lines).
#   2. A binary-file diff ("Binary files ... differ" — a file header with NO
#      @@ hunk at all, exercising the END-block ensure_file_header path).
# For each, we assert chunk_count.txt == the number of chunk_*.diff files that
# were actually written to disk.
#
# We drive the AWK chunker directly (scripts/chunk-diff.awk) like Test 6 of
# tests/test-chunker.sh does. This keeps the test hermetic: no node, no
# tree-sitter, no git fixtures required.
#
# Usage:  bash tests/test-chunker-edgecases.sh
# Exit:   0 if all assertions pass; 1 on the first failure.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AWK="$REPO_ROOT/scripts/chunk-diff.awk"

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

assert "[[ -f \"$AWK\" ]]" "chunk-diff.awk exists"

# Count chunk_*.diff files that actually got bytes on disk.
count_chunk_files() {
  local dir="$1"
  local n=0 f
  for f in "$dir"/chunk_*.diff; do
    [[ -e "$f" && -s "$f" ]] && n=$((n + 1))
  done
  echo "$n"
}

run_awk() {
  local diff_file="$1" out_dir="$2" csize="$3"
  mkdir -p "$out_dir"
  LC_ALL=C awk -v chunk_size="$csize" -v output_dir="$out_dir" \
    -f "$AWK" < "$diff_file"
}

# ─── Case 1: deletes-only diff ──────────────────────────────────────────────
echo "Test 1: deletes-only diff — chunk_count.txt == files written"
del_diff="$WORK/deletes-only.diff"
cat > "$del_diff" <<'EOF'
diff --git a/old.py b/old.py
index 1111111..0000000 100644
--- a/old.py
+++ b/old.py
@@ -1,5 +0,0 @@
-def gone():
-    return 1
-
-x = gone()
-print(x)
EOF
del_out="$WORK/deletes-only-out"
run_awk "$del_diff" "$del_out" 1000
assert "[[ -f \"$del_out/chunk_count.txt\" ]]" "deletes-only: chunk_count.txt written"
del_reported=$(cat "$del_out/chunk_count.txt" 2>/dev/null || echo "MISSING")
del_actual=$(count_chunk_files "$del_out")
assert "[[ \"$del_reported\" == \"$del_actual\" ]]" \
  "deletes-only: reported count ($del_reported) == files written ($del_actual)"
assert "[[ \"$del_actual\" -ge 1 ]]" \
  "deletes-only: at least one chunk file produced (got $del_actual)"

# ─── Case 2: binary-file diff (header, no @@ hunk) ──────────────────────────
echo "Test 2: binary-file diff — chunk_count.txt == files written"
bin_diff="$WORK/binary.diff"
cat > "$bin_diff" <<'EOF'
diff --git a/logo.png b/logo.png
index 1234567..89abcde 100644
Binary files a/logo.png and b/logo.png differ
EOF
bin_out="$WORK/binary-out"
run_awk "$bin_diff" "$bin_out" 1000
assert "[[ -f \"$bin_out/chunk_count.txt\" ]]" "binary: chunk_count.txt written"
bin_reported=$(cat "$bin_out/chunk_count.txt" 2>/dev/null || echo "MISSING")
bin_actual=$(count_chunk_files "$bin_out")
assert "[[ \"$bin_reported\" == \"$bin_actual\" ]]" \
  "binary: reported count ($bin_reported) == files written ($bin_actual)"

# ─── Case 3: mixed — binary file + a real text hunk in the same diff ────────
# Ensures the count invariant holds when a no-hunk header is followed by a
# normal file with a hunk (the binary header must not consume a phantom slot).
echo "Test 3: binary header + text hunk — chunk_count.txt == files written"
mix_diff="$WORK/mixed.diff"
cat > "$mix_diff" <<'EOF'
diff --git a/logo.png b/logo.png
index 1234567..89abcde 100644
Binary files a/logo.png and b/logo.png differ
diff --git a/app.py b/app.py
index aaaaaaa..bbbbbbb 100644
--- a/app.py
+++ b/app.py
@@ -1,3 +1,4 @@
 import os
+import sys
 def main():
     pass
EOF
mix_out="$WORK/mixed-out"
run_awk "$mix_diff" "$mix_out" 1000
mix_reported=$(cat "$mix_out/chunk_count.txt" 2>/dev/null || echo "MISSING")
mix_actual=$(count_chunk_files "$mix_out")
assert "[[ \"$mix_reported\" == \"$mix_actual\" ]]" \
  "mixed: reported count ($mix_reported) == files written ($mix_actual)"
assert "[[ \"$mix_actual\" -ge 1 ]]" \
  "mixed: at least one chunk file produced (got $mix_actual)"

# ─── Summary ─────────────────────────────────────────────────────────────────
echo
echo "Results: $pass passed, $fail failed"
if [[ "$fail" -gt 0 ]]; then
  echo "Failures:"
  for m in "${fail_messages[@]}"; do echo "  - $m"; done
  exit 1
fi
exit 0
