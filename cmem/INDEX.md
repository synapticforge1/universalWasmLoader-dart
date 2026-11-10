# cmem — Portable Project Memory for universalWasmLoader-dart

> **At session start, read `../../cmem/workspace-correspondence.md` (rows addressed to this repo),
> then `../../cmem/handoffs.md` for the letters it points to.** The
> workspace session reviews across the sibling repos and reports there; nothing is ever written into
> this repo from outside (owner, 2026-09-20).

This folder is the **authoritative, portable project memory** for `universalWasmLoader-dart`. It
travels with the repo and is committed. Layout per the workspace `../../cmem/memory-conventions.md`
(conformed 2026-10-22, letter H6). One topic per file; this INDEX holds policy, triggers and one line
per file, and no status. The status lives only in [open-work.md](open-work.md).

## Policy

- **`cmem/` is the single home for ALL project memory.** `README.md` and `CHANGELOG.md` are the
  public docs: keep internal decision logs and post-mortems out of them. `SPEC.md` lives in `-js`.
- **Working memory, not an archive; git is the archive.** Completed work is summarized with its
  commit pointer. Superseded text is replaced, not struck through. Absolute dates; every number
  carries its date.

### The "update the project memory" trigger (binding on every agent)

When the owner says **"update the project memory"** (or "update memory", "record this"), do BOTH:
(1) revise the matching `cmem/` files and refresh their lines below. This means AUDITING for stale
live claims: grep the old values, classify each hit as live or dated, and re-read every "by design"
and "out of scope" line, not just the files you touched. (2) Sync README / CHANGELOG only where
the change is user-relevant.

### The "look for code issues" trigger (binding on every agent)

When the owner says **"look for code issues"** (or "code audit" / "audit the code"), audit tested
AND untested paths for: (1) workarounds / temporary hacks; (2) dead code; (3) bugs (wrong ABI
marshalling, off-by-one pointer/length math, endianness, missing `cabi_post` calls); (4) silent
fall-throughs (returning a default instead of erroring). Report `file:line` + severity, fix the safe
ones, and keep every gate in [testing.md](testing.md) green (`dart test -p chrome` included).

## Files

| File | What it holds |
| --- | --- |
| [open-work.md](open-work.md) | THE status line and the one list of open items; done items as summaries with commit pointers |
| [overview.md](overview.md) | What the port is, repo home (`synapticforge1`), the 🔒 dual-backend runtime decision, API surface, SPEC 4.0.0 conformance and the Dart error types, file layout, the js_interop gotchas |
| [release.md](release.md) | 🔒 How a release runs (the owner's order: checks → CI tag → page → pub.dev, slots U1–U12, what is not filled and why) and § "Release History", newest first, a summary per version |
| [releasing.md](releasing.md) | The design: bump → release (pushes `main` only) → the `run:`-only four-job workflow and why; `compat --release` on the untagged candidate; `ci_release.dart`'s five commands and tests; the D1 rehearsal; Dart-only scripting 🔒 |
| [testing.md](testing.md) | Every gate, its command and blind spots, dated counts; the http test server; the stamped reference fixtures (H7) and how to refresh them |
| [compat-gate.md](compat-gate.md) | The H6 compatibility gate: surface, floor, previous-tag tests, pre-1.0 rule, the inversion table, traps |
| [working-rules.md](working-rules.md) | The checklist: git/release (no package code beside the credentials 🔒, no GitHub CLI 🔒, Release pages from CI 🔒, Bun notations), tooling hard rules, LF 🔒, privacy and the path test 🔒, memory rules |
| [best-practices.md](best-practices.md) | This repo's own rules (§ L) + the workspace ★ rules, a stamped verbatim copy (re-copied 2026-10-26) |
| [history-map-2026-10-26.md](history-map-2026-10-26.md) | The H19 path purge: what leaked, how it was rewritten and verified, the old → new commit map |
| `local/` (gitignored) | Private machine notes (`environment.md`); never committed |
