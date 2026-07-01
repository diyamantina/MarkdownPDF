#!/usr/bin/env bash
# Repo-wide style gate: no em dashes, no tool-attribution phrases, no signature
# emojis in any tracked file. Mirrors the .githooks checks, run over the whole
# tree in CI so a bypassed local hook is still caught at merge time.
#
# Portable: BSD-compatible grep, bash 3.2 (macOS) and bash 4+ (CI).

set -u

FAIL=0

# Em dash U+2014, built via printf so this script contains no em-dash byte.
EMDASH=$(printf '\xe2\x80\x94')

# Enforcement files legitimately contain the forbidden phrases in order to
# detect them, so exclude them from the phrase scan.
is_enforcement_file() {
  case "$1" in
    .githooks/*|scripts/check-style.sh|researchcode/*) return 0 ;;
    *) return 1 ;;
  esac
}

# Tool-attribution phrases. Tool-agnostic: any AI assistant or its vendor, not
# just one. The Claude token is assembled from fragments so this script does not
# contain the full literal phrase (which would self-flag in other scanners).
# Bare tool names are NOT flagged (that would false-positive on legitimate text
# like "fix cursor blink"); only attribution-context mentions are.
TOOL="Cla""ude"
AI_TOOLS="$TOOL|Anthropic|Codex|OpenAI|ChatGPT|GPT-[0-9]|Cursor|Copilot|Gemini|Google AI"
ATTRIB_REGEX="(Co-Authored-By|Co-authored-with|Generated (with|by)|Created (with|by)|Powered by|with help from|written by|authored by)[: ].*($AI_TOOLS)"
# Generic self-reference tells, independent of any vendor name.
GENERIC_PHRASES=(
  "as an AI"
)

while IFS= read -r f; do
  [ -f "$f" ] || continue
  case "$f" in
    researchcode/*) continue ;;
  esac
  if ! LC_ALL=C grep -Iq . "$f" 2>/dev/null; then
    continue
  fi
  if LC_ALL=C grep -qF -- "$EMDASH" "$f" 2>/dev/null; then
    echo "style: em dash (U+2014) in $f" >&2
    FAIL=1
  fi
  if ! is_enforcement_file "$f"; then
    if LC_ALL=C grep -qiE -- "$ATTRIB_REGEX" "$f" 2>/dev/null; then
      echo "style: forbidden attribution phrase in $f" >&2
      FAIL=1
    fi
    for p in "${GENERIC_PHRASES[@]}"; do
      if LC_ALL=C grep -qF -- "$p" "$f" 2>/dev/null; then
        echo "style: forbidden attribution phrase in $f" >&2
        FAIL=1
      fi
    done
  fi
done < <(git ls-files)

# Roadmap diagram gate (github-discipline Rule 1.8): valid, vertical,
# legend-keyed mermaid diagrams, and every epic visible in a diagram.
if command -v python3 >/dev/null 2>&1; then
  if ! python3 "$(dirname "$0")/check-roadmap.py"; then
    FAIL=1
  fi
else
  echo "style: python3 not found, skipping roadmap gate" >&2
fi

if [ "$FAIL" -ne 0 ]; then
  echo "style: gate failed. Rules: docs/rules/git-discipline.md" >&2
fi
exit "$FAIL"
