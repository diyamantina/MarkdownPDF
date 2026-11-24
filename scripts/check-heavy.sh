#!/usr/bin/env bash
# The heavy run: every gate of the pre-push hook and every test suite, the heavy ones included. A release, a tag, a series of
# landings or a "verified" claim names a passing run of this script at the exact commit. On a green run at a clean HEAD it
# writes the heavy-pass record (see scripts/test-suites.sh). Takes about 12 minutes serially on a loaded machine.

set -euo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$ROOT"

# Git exports these to a hook; SwiftPM's own git calls must not see them.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR

bash scripts/check-style.sh
bash scripts/check-namespacing.sh
bash scripts/test-test-suites.sh
swiftformat . --config .swiftformat --lint
swiftlint --config .swiftlint.yml --strict
swift build
bash scripts/test-suites.sh heavy
