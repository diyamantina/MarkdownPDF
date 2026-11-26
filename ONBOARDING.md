# Onboarding (2026-11-26)

## Purpose

A Swift library that turns Markdown into PDF. Start with `README.md`, `CONTRIBUTING.md`, `Docs/NOT-VERIFIED.md` and `Knowledge/`.

## State

- Main before this file: `2c3620b`. Last release: `0.19.0`. Nothing is listed under "Unreleased" in `CHANGELOG.md`.
- 27 open issues, mirrored in `issues/`. Issue 48 was left open on purpose during the last cleanup.

## Done on 2026-11-26

- A knowledge note on the Metal survey.
- Issues 88 and 89 closed in the issue cleanup.

## In flight and local only

Nothing is uncommitted. Local branches not on the host:

- `corpus-s0`, `corpus-s0b`, `issues-1-0`: equal changes are already on main.
- `emoji-colr`: checked, already on main. Its commit `3989f11` landed as `e8e9944` with the same changes to sources and tests; only the changelog text differs. Do not land it again.

Many older branches from 1 to 3 June, local and on the host, are not merged. All conflict with current main. Most of the files they add are on main; the rest were removed again by the package restructure (`63c33ab`) or the documentation move (`f68a6a6`). They were not landed. It was not proven line by line that nothing in them is still wanted: issues 53, 66, 67 and 68, which have branches here, are still open.

The host branch `wip/whole-set-coverage` also conflicts; the files it adds are on main.

## Next steps

- The reader now lives in the `ExtendedMarkdown` package; further moves continue there.
- 1.0 comes together with MathTypeset and TileDown, after MathTypeset's layout engine.

## Waiting on the owner

Nothing specific, beyond the 1.0 plan.

## Build, test, publish

```sh
git config core.hooksPath .githooks
swift build
scripts/test-suites.sh smoke   # what the push gate runs
scripts/check-heavy.sh         # the full run, needed for a release
```

Page appearance and PDF/A and PDF/UA conformance are not verified by the tests. Releases and the Homebrew tap need the owner's yes.
