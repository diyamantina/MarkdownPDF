# The pre-push hook and a cold worktree

MEASURED (a push of this repository from a fresh worktree, 2026-11-24): the hook ran its format and lint steps, then `swift build` failed within seconds with `unable to read tree` for each package it had to check out (MathTypeset and the two documentation packages), and the push was refused.

Cause, MEASURED by the cure: git exports `GIT_DIR`, `GIT_WORK_TREE` and `GIT_INDEX_FILE` to a hook. SwiftPM runs git itself to check out its dependencies, and with those variables set its git calls read this repository's object store instead of the dependency's own. A worktree whose packages are already checked out never runs those calls, so earlier pushes from warm worktrees passed and hid the fault.

Cure: the hook unsets `GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR` before its first command (`.githooks/pre-push`). The gate finds the repository from its folder and needs none of them.

The same fault showed in three repositories on the same day; a hook that runs a package build must carry the line.

## The hook is 60 seconds, the heavy run is named

MEASURED (each test run alone, 2026-11-24): the whole suite took 706 seconds of test time; 14 of its 124 suites cost 590 of them and the other 110 cost 38 seconds. The pre-push hook therefore runs the 110 (`scripts/test-suites.sh smoke`, which skips the suites listed in `scripts/heavy-suites.txt`) and the heavy run is `scripts/check-heavy.sh`.

MEASURED: the smoke run took 23 seconds (929 tests, 13.6 seconds of test time) and the cheap gates together 12 seconds, so the hook stays under a minute. A fault planted inside a heavy suite leaves the smoke run green and turns the heavy suite red, which is the intended split: the hook is a floor, the heavy run is the proof.

DOCUMENTED (`scripts/check-heavy.sh`, `scripts/test-suites.sh`): a release, a tag or a "verified" claim names a passing heavy run at the exact commit. On a green run at a clean HEAD the script writes one record file, `MarkdownPDF-<commit>`, into `HEAVY_RECORD_DIR` (default: `heavy-pass` under the temporary folder), outside the repository so that a fresh worktree can be released from it.

A suite is added to the list when it grows past 5 seconds; `scripts/test-test-suites.sh` fails when a listed name is not a suite.
