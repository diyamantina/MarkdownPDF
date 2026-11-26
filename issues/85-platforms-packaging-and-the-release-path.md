---
number: 85
title: "Platforms, packaging and the release path"
state: open
labels: ["before-1.0", "enhancement"]
assignees: []
created: 2026-11-24T11:42:47+01:00
updated: 2026-11-24T13:35:31+01:00
host: https://codeberg.org/MarkdownPDFHQ/MarkdownPDF/issues/85
synced: 2026-11-24T13:35:31+01:00 2aa4781e3982
neutralized: 2
---

## What

Builds and tests are green on macOS and Linux (the workflows in the repository), the CHANGELOG and the version history are consistent, the licence files agree (AGPL and the commercial terms), the README install line names the 1.0 version, the release is an annotated tag with notes, and SemVer is stated: after 1.0 a breaking change is a major version. The command line tool and the resume tool are released from their own repositories and name this version.

## Why

A release is repeatable by hand from documented commands.

## Oracle first

The reference is a clean checkout on each platform: build, test and the release steps, run from the documentation alone.

## Acceptance

Both platforms pass from a clean checkout, the documented release steps work on a dry run, and the README and CHANGELOG match the tag.

## Comments

### Mihaela, 2026-11-24T13:35:31+01:00

Correction after reading the code on 2026-11-24. The README has no install line to update (add one). The command line tool and the resume tool both live in one separate repository, MarkdownPDFCli. Besides the macOS and Linux workflows there are WebAssembly, style, documentation and rules-freshness workflows. The README claims Windows and WebAssembly builds while the manifest declares only macOS 13: decide what is claimed.
