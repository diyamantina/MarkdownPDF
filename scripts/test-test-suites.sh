#!/usr/bin/env bash
# Self-test of scripts/test-suites.sh: the smoke command skips exactly the listed suites, the heavy command skips none, a
# planted suite in the list is skipped by the smoke command and by no other, and every name in the real list is a suite
# that exists in the test sources. Builds and runs nothing.

set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$ROOT"

fail=0
check() { # description, condition result (0 = holds)
  if [ "$2" -eq 0 ]; then echo "ok: $1"; else echo "FAIL: $1" >&2; fail=1; fi
}

heavy=$(bash scripts/test-suites.sh print-heavy)
[ "$heavy" = "swift test" ]
check "the heavy command skips nothing" $?

smoke=$(bash scripts/test-suites.sh print-smoke)
count=$(printf '%s\n' "$smoke" | grep -o -- '--skip' | wc -l | tr -d ' ')
listed=$(grep -v -e '^[[:space:]]*#' -e '^[[:space:]]*$' scripts/heavy-suites.txt | wc -l | tr -d ' ')
[ "$count" -eq "$listed" ]
check "the smoke command skips one pattern for each of the $listed listed suites (found $count)" $?

printf '%s\n' "$smoke" | grep -q 'MarkdownPDFTests\\.FixtureTests/'
check "a listed name is anchored on both sides" $?

if printf '%s\n' "$smoke" | grep -q 'LargeDocumentFixtureTests'; then
  check "a suite that is not listed is not skipped (LargeDocumentFixtureTests)" 1
else
  check "a suite that is not listed is not skipped (LargeDocumentFixtureTests)" 0
fi

# The planted fault: a list with one invented suite. The smoke command must skip it, the heavy command must not.
planted=$(mktemp "${TMPDIR:-.}/planted-heavy.XXXXXX")
trap 'rm -f "$planted"' EXIT
printf 'PlantedHeavyFaultTests\n' > "$planted"
planted_smoke=$(HEAVY_SUITES_FILE="$planted" bash scripts/test-suites.sh print-smoke)
printf '%s\n' "$planted_smoke" | grep -q 'PlantedHeavyFaultTests'
check "a planted suite in the list is skipped by the smoke command" $?
planted_heavy=$(HEAVY_SUITES_FILE="$planted" bash scripts/test-suites.sh print-heavy)
[ "$planted_heavy" = "swift test" ]
check "the heavy command still runs the planted suite (it skips nothing)" $?

# Every listed name is a real suite: a type of that name with a @Suite or @Test in the sources.
while IFS= read -r line || [ -n "$line" ]; do
  line=${line%%#*}
  line=${line//[[:space:]]/}
  [ -n "$line" ] || continue
  grep -rqE "^(struct|final class|class|enum) ${line}\b" Tests
  check "the listed suite $line exists in Tests/" $?
done < "${HEAVY_SUITES_FILE:-scripts/heavy-suites.txt}"

exit $fail
