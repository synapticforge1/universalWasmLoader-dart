# Changelog

## Unreleased

- Test fixtures are now byte-identical copies of the shared reference set (stamped in
  `test/fixtures/fixtures.json`); `strings_50.wasm` and `wasi_io_50.wasm` updated, `init_check.wat`
  added.
- README: corrected the Runtime section, which said SPEC §10 was not implemented.
- No library code changes.

## 0.2.0

- SPEC §10 (producer model) loader capabilities:
  - A minimal WASI Preview 1 shim (`wasi_snapshot_preview1`) is always attached
    to the imports, so library modules that do I/O load in the browser.
    `fd_write` goes to `console.log` / `console.error`; `proc_exit`,
    `random_get`, `clock_time_get`, environ/args and basic `fd_*` are provided.
  - A reactor module's exported `_initialize` is now called once, automatically,
    right after instantiation (with or without a `.wit`). Do not call it again
    yourself.
- No public API changes.

## 0.1.0

- Initial release. Web-first Dart port of the Universal WASM Loader, implementing
  cross-language `SPEC.md` v3.0.0 over the browser `WebAssembly` API via
  `dart:js_interop`.
- `wasmImport`, `createSingleton`, `InstancePool`; WIT auto-detection; the `@N`
  version pin; full Canonical ABI (numerics pass-through, `bool` 1/0 ↔ true/false,
  string params via `cabi_realloc`, callee-allocated string returns +
  `cabi_post_<name>` release).
