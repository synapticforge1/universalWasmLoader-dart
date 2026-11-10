# Changelog

## Unreleased

- No library changes.
- Releases now run checks first, then CI creates the tag, then the GitHub Release page, then the
  pub.dev upload, with a read-back. A release is started by pushing `main`. README's Releasing
  section is updated.

## 0.3.2

- No library changes.
- README: the Releasing section describes the three-job release workflow.
- Release tooling (not part of the package): the GitHub Release page is made by its own job, which
  is the only one that can write to the repository; the release script has tests.

## 0.3.1

- No library changes.
- README: the Releasing section describes the release workflow as it now runs (checks and publishing
  in separate jobs; the publishing job runs only the Dart SDK).
- Release tooling (not part of the package): the GitHub Release is created through GitHub's REST
  API, and a re-run skips the pub.dev upload when the version is already there.

## 0.3.0

**Breaking (SPEC 4.0.0): failures are loud.** See the README's "What fails, and how" table and the
Breaking Changes row.

- Only an absent `.wit` (HTTP 404 / 410, or a path not ending in `.wasm`) loads raw exports. Any
  other `.wit` failure fails the load before the `.wasm` is fetched. The `.wit` URL now drops the
  `.wasm` URL's query and fragment.
- `parseWit` is strict: a malformed statement or parameter, an unsupported type (`u32` was read as
  `s32`), a duplicate name or text outside the one `world` throws a `FormatException`.
- Every WIT import needs a host callback, checked at load. A callback's return value must match the
  import's WIT result, and a `Future` is refused. An import returning `string` is refused at load.
- A WIT export the module does not export fails the load.
- Typed calls check the argument count and each argument's kind; nothing is coerced. `s64` now
  passes a real 64-bit integer (`int` or `BigInt`) and returns a `BigInt`; it used to fail inside
  the engine.
- New `options: LoadOptions(timeout:, cancel:)` on `wasmImport`, `createSingleton` and
  `InstancePool`: a 30 s default limit on each fetch (`TimeoutException`), and a `LoadCancelToken`.

## 0.2.1

- Test fixtures are now byte-identical copies of the shared reference set (stamped in
  `test/fixtures/fixtures.json`); `strings_50.wasm` and `wasi_io_50.wasm` updated, `init_check.wat`
  added.
- README: corrected the Runtime section, which said SPEC §10 was not implemented; added a
  `### ⚠️ Breaking Changes` table (recording the 0.2.0 `_initialize` behaviour change).
- Releases are now checked by a compatibility gate (repository tooling, not part of the package):
  the public API is compared with the previous release, and its tests must still pass.
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
