#!/usr/bin/env bash
# Runs the Swift tests of this package in one of two sizes, and is the only place that knows which suites are heavy.
#
#   scripts/test-suites.sh smoke         every suite except those in scripts/heavy-suites.txt (the pre-push hook runs this)
#   scripts/test-suites.sh heavy         every suite; on a green run at a clean HEAD it writes the heavy-pass record
#   scripts/test-suites.sh print-smoke   prints the command of `smoke`, runs nothing (the self-test reads it)
#   scripts/test-suites.sh print-heavy   prints the command of `heavy`, runs nothing
#
# The heavy-pass record is one file, `<repository>-<commit>`, in HEAVY_RECORD_DIR (default: heavy-pass under TMPDIR),
# holding the date, the machine and the load. It lives outside the repository so that a fresh worktree can be released from
# it. A release or a "verified" claim needs the record of the exact commit.
#
# SWIFT_TEST_ARGS adds arguments to `swift test` (for example cache paths); HEAVY_SUITES_FILE names another list.

set -euo pipefail

MODE="${1:?usage: scripts/test-suites.sh smoke|heavy|print-smoke|print-heavy}"
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$ROOT"

REPOSITORY="MarkdownPDF"
MODULE="MarkdownPDFTests"
LIST="${HEAVY_SUITES_FILE:-scripts/heavy-suites.txt}"

# shellcheck disable=SC2206
EXTRA=(${SWIFT_TEST_ARGS:-})

skips=()
while IFS= read -r line || [ -n "$line" ]; do
  line=${line%%#*}
  line=${line//[[:space:]]/}
  [ -n "$line" ] || continue
  # The id of a test is Module.Type/test: anchored on both sides, so FixtureTests does not also skip ShowcaseFixtureTests.
  skips+=(--skip "${MODULE}\\.${line}/")
done < "$LIST"

case "$MODE" in
  smoke)
    exec swift test "${skips[@]}" ${EXTRA[@]+"${EXTRA[@]}"}
    ;;
  print-smoke)
    echo "swift test ${skips[*]}"
    ;;
  print-heavy)
    echo "swift test"
    ;;
  heavy)
    if [ -n "$(git status --porcelain)" ]; then
      echo "test-suites: the tree is not clean: a heavy run is recorded for a commit, so commit or stash first." >&2
      exit 1
    fi
    DIR="${HEAVY_RECORD_DIR:-}"
    if [ -z "$DIR" ]; then
      DIR="${TMPDIR:?set TMPDIR (an external folder) or HEAVY_RECORD_DIR before a heavy run}/heavy-pass"
    fi
    HASH=$(git rev-parse HEAD)
    swift test ${EXTRA[@]+"${EXTRA[@]}"}
    mkdir -p "$DIR"
    {
      echo "repository: $REPOSITORY"
      echo "commit: $HASH"
      echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
      echo "machine: $(hostname -s)"
      echo "load at the end: $(sysctl -n vm.loadavg 2>/dev/null || echo unknown)"
    } > "$DIR/$REPOSITORY-$HASH"
    echo "test-suites: heavy run passed at $HASH, recorded in $DIR/$REPOSITORY-$HASH"
    ;;
  *)
    echo "test-suites: unknown mode $MODE" >&2
    exit 2
    ;;
esac
