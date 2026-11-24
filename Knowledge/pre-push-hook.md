# The pre-push hook and a cold worktree

MEASURED (a push of this repository from a fresh worktree, 2026-11-24): the hook ran its format and lint steps, then `swift build` failed within seconds with `unable to read tree` for each package it had to check out (MathTypeset and the two documentation packages), and the push was refused.

Cause, MEASURED by the cure: git exports `GIT_DIR`, `GIT_WORK_TREE` and `GIT_INDEX_FILE` to a hook. SwiftPM runs git itself to check out its dependencies, and with those variables set its git calls read this repository's object store instead of the dependency's own. A worktree whose packages are already checked out never runs those calls, so earlier pushes from warm worktrees passed and hid the fault.

Cure: the hook unsets `GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR` before its first command (`.githooks/pre-push`). The gate finds the repository from its folder and needs none of them.

The same fault showed in three repositories on the same day; a hook that runs a package build must carry the line.
