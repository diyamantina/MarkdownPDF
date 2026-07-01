#!/usr/bin/env python3
"""Roadmap diagram gate.

Enforces github-discipline Rule 1.8 against this repo's README:

  1. Structural: every mermaid block is vertical (flowchart TD), every node
     referenced by an edge is defined, every node is assigned exactly one
     class, every assigned class is declared in that block's classDef, and
     every classDef is within the shared legend palette.
  2. Legend: the first mermaid block is the shared legend (declares the palette)
     and therefore precedes every status diagram.
  3. Coverage: every OPEN epic appears in at least one README mermaid diagram.
     In-progress epics keep a detailed roadmap diagram and a node in the shared
     Epics overview. A closed epic is removed from the roadmap once its issue
     closes; the work it delivered is recorded in the CHANGELOG and the
     Completed epics section, so the diagrams stay focused on remaining work.

Structural and legend checks run offline and always. The epic-coverage check
needs GitHub access, so it runs only when `gh` is available and authenticated;
otherwise it is skipped with a notice so the gate stays portable for offline
and local runs. In CI the workflow grants `issues: read` and a token so
coverage is enforced.
"""
import json
import os
import re
import shutil
import subprocess
import sys

LEGEND = {"done", "active", "review", "next", "todo"}
README = os.path.join(os.path.dirname(__file__), os.pardir, "README.md")


def parse_blocks(text):
    return re.findall(r"```mermaid\n(.*?)```", text, re.S)


def lint_block(block):
    errs = []
    direction = next(
        (l.strip() for l in block.splitlines() if l.strip().startswith("flowchart")),
        "",
    )
    if direction != "flowchart TD":
        errs.append(f"not vertical (got '{direction or 'no flowchart line'}')")

    defined = set(re.findall(r"^\s*([A-Za-z0-9_]+)\s*[\[\({]", block, re.M))

    used = set()
    for line in block.splitlines():
        s = line.strip()
        if "-->" in s or "-.->" in s:
            for tok in re.split(r"-\.?->", s):
                m = re.match(r"\s*([A-Za-z0-9_]+)", tok)
                if m:
                    used.add(m.group(1))

    classdef = set(re.findall(r"classDef\s+(\w+)", block))

    assigned = {}
    for m in re.finditer(r"^\s*class\s+([A-Za-z0-9_,]+)\s+(\w+)\s*;", block, re.M):
        for nid in m.group(1).split(","):
            assigned[nid] = m.group(2)
    for m in re.finditer(r"([A-Za-z0-9_]+)[^\n]*?:::(\w+)", block):
        assigned[m.group(1)] = m.group(2)

    orphan = sorted(used - defined)
    unclassed = sorted(defined - set(assigned))
    bad_class = {n: c for n, c in assigned.items() if c not in classdef}
    not_legend = sorted(classdef - LEGEND)

    if orphan:
        errs.append(f"edge nodes not defined: {orphan}")
    if unclassed:
        errs.append(f"nodes with no class: {unclassed}")
    if bad_class:
        errs.append(f"class not in classDef: {bad_class}")
    if not_legend:
        errs.append(f"classDef outside legend palette: {not_legend}")
    return errs


def all_epics():
    if not shutil.which("gh"):
        return None, "gh not installed"
    # Only open epics must appear in a diagram. A closed epic is removed from the
    # roadmap once its issue closes; the work it delivered lives in the CHANGELOG
    # and the Completed epics section, so the diagrams stay focused on remaining
    # work.
    cmd = ["gh", "issue", "list", "--label", "epic", "--state", "open",
           "--json", "number", "--limit", "200"]
    repo = os.environ.get("GITHUB_REPOSITORY")
    if repo:
        cmd += ["-R", repo]
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    except Exception as exc:  # network, auth, or missing binary
        return None, f"gh call failed: {exc}"
    if out.returncode != 0:
        return None, (out.stderr.strip().splitlines()[-1] if out.stderr.strip() else "gh returned nonzero")
    return [str(x["number"]) for x in json.loads(out.stdout)], None


def mermaid_sections(text):
    parts = re.split(r"(?m)^(##\s.*)$", text)
    secs = []
    for i in range(1, len(parts), 2):
        body = parts[i + 1] if i + 1 < len(parts) else ""
        secs.append(parts[i] + "\n" + body)
    return [s for s in secs if "```mermaid" in s]


def epic_has_diagram(number, sections):
    pat = re.compile(rf"(?:#|issues/){number}(?!\d)")
    return any(pat.search(s) for s in sections)


def main():
    text = open(README, encoding="utf-8").read()
    blocks = parse_blocks(text)
    fail = False

    if not blocks:
        print("roadmap: no mermaid diagrams found in README", file=sys.stderr)
        sys.exit(1)

    for i, block in enumerate(blocks):
        for err in lint_block(block):
            print(f"roadmap: [diagram {i}] {err}", file=sys.stderr)
            fail = True

    if not re.search(r"classDef\s+done", blocks[0]):
        print("roadmap: first mermaid block is not the shared legend (no classDef palette)", file=sys.stderr)
        fail = True

    epics, why = all_epics()
    if epics is None:
        print(f"roadmap: SKIP epic coverage ({why})")
    else:
        sections = mermaid_sections(text)
        missing = sorted((n for n in epics if not epic_has_diagram(n, sections)), key=int)
        if missing:
            print(f"roadmap: epics with NO diagram: {['#' + n for n in missing]}", file=sys.stderr)
            fail = True
        else:
            print(f"roadmap: all {len(epics)} open epics appear in a diagram")

    if fail:
        print("roadmap: gate failed. Rule: github-discipline Rule 1.8 "
              "(every epic appears in a valid, legend-keyed status diagram; "
              "in-progress epics keep a detailed roadmap).",
              file=sys.stderr)
        sys.exit(1)
    print("roadmap: OK")


if __name__ == "__main__":
    main()
