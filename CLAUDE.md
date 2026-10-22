> **⚠️ PORTABLE PROJECT MEMORY NOW LIVES IN `cmem/`** — start at [`cmem/INDEX.md`](cmem/INDEX.md).

> **At session start, read `../../cmem/handoffs.md` for letters addressed to this repo.** The workspace
> session (`../../cmem/INDEX.md`) reviews across the sibling repos and reports there; nothing is ever
> written into this repo from outside. (owner directive, 2026-09-20)

> When saving new project memory, write it into the matching `cmem/` topic file (and refresh its
> pointer in `cmem/INDEX.md`). The **"update the project memory"** and **"look for code issues"**
> triggers are defined in `cmem/INDEX.md` and are binding. This `CLAUDE.md` remains as the auto-loaded
> historical archive; `cmem/` is the source of truth.

# universalWasmLoader-dart

Universal WASM loader for Dart — the Dart port of the Universal WASM Loader (see the JS/TS reference
`universalWasmLoader-js` and the cross-language `SPEC.md`).

## Project Overview

Early-stage Dart package for loading WebAssembly modules the way the reference loader does — auto-detect
the companion `.wit`, apply the Canonical ABI, and return a typed handle. Intended to be published to
**pub.dev** as the Dart member of the polyglot loader ecosystem.

## Toolchain

- Platform: Dart SDK (and Flutter-compatible).
- Build / test / run: `dart pub get`, `dart test`, `dart run`; format with `dart format`, lint with
  `dart analyze`.
- Package manager / registry: **pub.dev**; package version lives in `pubspec.yaml` (`version:`).
- Scripts: **Dart only** (`dart run scripts/bump.dart`, `dart run scripts/release.dart`); no shell
  scripts. A TypeScript script, if ever needed, runs under `bun` (2026-10-22).
- OS: Windows 11 (development environment).

## WASM runtime — DECIDED (web now, native later)

Dual-backend, resolved 2026-06-15: the current backend is **web** — `dart:js_interop` over the
browser's native `WebAssembly` + `fetch` (best fit for Flutter web, no native build step). A **native**
(Dart VM) backend via `dart:ffi` → wasmtime C API is planned later, selected via conditional imports.
Because the web backend can't use a runtime built-in WASI, the SPEC §10.2 shim is **hand-rolled** in
`lib/src/wasi.dart` (mirrors `-js`); the future native backend will get wasmtime's built-in WASI.

## Repository Structure

Implemented and PUBLISHED to pub.dev. `lib/universal_wasm_loader.dart` (barrel) + `lib/src/`
(`loader.dart`, `abi.dart`, `wasi.dart`, `wasm_interop.dart`, `wit_parser.dart`),
`test/loader_test.dart` (`@TestOn('browser')`) + `test/fixtures/`, `pubspec.yaml`, `cmem/`. See
[`cmem/overview.md`](cmem/overview.md) for the authoritative file-by-file layout.

## Conformance

Implements the cross-language `SPEC.md` at **v3.0.0 (2026-06-15)** — string returns use the
**canonical callee-allocated** convention (export returns an i32 pointer to a `[ptr, len]` pair; host
reads it then calls `cabi_post_<name>(retPtr)`). **SPEC §10 (producer model) is implemented
(2026-07-05):** the loader always attaches a minimal WASI-P1 shim (`lib/src/wasi.dart`) and calls a
reactor module's `_initialize` after instantiation, so I/O-using `modc` libraries load on the web.
`dart test -p chrome` → 9/9 (incl. 2 §10 tests). Full detail in [`cmem/overview.md`](cmem/overview.md).

## Notes

- GitHub home: **https://github.com/synapticforge1/universalWasmLoader-dart**. It was transferred from
  `jrmarcum` to the `synapticforge1` org (recorded 2026-10-20; see `cmem/overview.md` → "Repository home").
- Git safe.directory may need adding for this path when running git outside Claude Code:
  `git config --global --add safe.directory D:/Programs/_ProgramExamples/Example_Programs/wasmExamples/universalWasmLoader/universalWasmLoader-dart`
