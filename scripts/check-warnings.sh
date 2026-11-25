#!/usr/bin/env bash
# A compiler warning in this repository's own sources or tests is a finding, not noise (issue 89).
#
#   scripts/check-warnings.sh LOGFILE     reads the log of a build that compiled every file and fails on a warning in Sources/ or Tests/
#   scripts/check-warnings.sh --build     builds the package and its tests from scratch (so that every file is compiled and every warning
#                                         is printed: a cached build prints none) and checks the log
#   scripts/check-warnings.sh --self-test proves the check can fail: a planted warning is found, a clean log and a warning of a
#                                         dependency are not
#
# The ESC byte of a coloured log is allowed between the position and the word `warning:`.

set -euo pipefail

ESC=$'\033'
# A warning has a position: `File.swift:LINE:COL: warning:`, or, inside the expansion of a macro (the `#expect` of a test), the
# position `macro expansion #expect:LINE:COL: warning:` with no path (the path is on the note line after it). The `warning:` that
# SwiftPM itself prints at the start of a line (for example about a cache) has no position and is not a finding.
PATTERN="(\\.swift:[0-9]+:[0-9]+|macro expansion #[A-Za-z_]+:[0-9]+:[0-9]+): (${ESC}\\[[0-9;]*m)*warning:"

findings() {
    # A warning inside a dependency checkout is not ours: its path has /.build/checkouts/ or /checkouts/.
    # A macro expansion names no file on its own line: the next line says where the expanded code comes from, so it is kept.
    { grep -a -E "\\.swift:[0-9]+:[0-9]+: (${ESC}\\[[0-9;]*m)*warning:" "$1" || true
      grep -a -E -A1 "macro expansion #[A-Za-z_]+:[0-9]+:[0-9]+: (${ESC}\\[[0-9;]*m)*warning:" "$1" | grep -a -v -E '^--$' || true
    } | grep -a -v -E '/(\.build/)?checkouts/' || true
}

check_log() {
    local found
    found=$(findings "$1")
    if [ -n "$found" ]; then
        echo "check-warnings: warnings in this repository's own sources or tests:" >&2
        echo "$found" >&2
        return 1
    fi
    echo "check-warnings: no warning in Sources/ or Tests/"
}

self_test() {
    local dir
    dir=$(mktemp -d "${TMPDIR:-/tmp}/check-warnings.XXXXXX")
    trap 'rm -rf "$dir"' RETURN
    printf '%s\n' "Compiling MarkdownPDF Foo.swift" "Build complete!" > "$dir/clean.log"
    printf '%s\n' "/work/repo/Tests/MarkdownPDFTests/FooTests.swift:11:20: ${ESC}[1;33mwarning: ${ESC}[1;39mno calls to throwing functions" > "$dir/ours-colour.log"
    printf '%s\n' "/work/repo/Sources/MarkdownPDF/Foo.swift:3:5: warning: variable 'x' was never used" > "$dir/ours-plain.log"
    printf '%s\n' "/work/repo/.build/checkouts/Dep/Sources/Dep/Dep.swift:9:1: warning: something in a dependency" > "$dir/dependency.log"
    printf '%s\n' "macro expansion #expect:1:22: ${ESC}[1;33mwarning: ${ESC}[1;39mno calls to throwing functions" > "$dir/ours-macro.log"
    printf '%s\n' "warning: 'markdownpdf': skipping cache due to an error: the file doesn't exist" "[3 / 9] Compiling Foo" > "$dir/swiftpm.log"
    check_log "$dir/clean.log" > /dev/null || { echo "self-test: a clean log failed" >&2; return 1; }
    check_log "$dir/swiftpm.log" > /dev/null || { echo "self-test: a SwiftPM warning without a position failed the check" >&2; return 1; }
    if check_log "$dir/ours-macro.log" > /dev/null 2>&1; then
        echo "self-test: a warning inside a macro expansion passed" >&2
        return 1
    fi
    check_log "$dir/dependency.log" > /dev/null || { echo "self-test: a warning of a dependency failed the check" >&2; return 1; }
    if check_log "$dir/ours-colour.log" > /dev/null 2>&1; then
        echo "self-test: a coloured warning of ours passed" >&2
        return 1
    fi
    if check_log "$dir/ours-plain.log" > /dev/null 2>&1; then
        echo "self-test: a plain warning of ours passed" >&2
        return 1
    fi
    echo "check-warnings self-test: ok (clean passes, a dependency's warning passes, ours fail, coloured and plain)"
}

case "${1:-}" in
    --self-test)
        self_test
        ;;
    --build)
        ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
        cd "$ROOT"
        unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR
        WORK=$(mktemp -d "${TMPDIR:-/tmp}/check-warnings-build.XXXXXX")
        trap 'rm -rf "$WORK"' EXIT
        swift build --build-tests --scratch-path "$WORK/build" > "$WORK/build.log" 2>&1 || { tail -40 "$WORK/build.log" >&2; exit 1; }
        check_log "$WORK/build.log"
        ;;
    "")
        echo "usage: check-warnings.sh LOGFILE | --build | --self-test" >&2
        exit 2
        ;;
    *)
        check_log "$1"
        ;;
esac
