# Overview — universalWasmLoader-dart

The **Dart** port of the Universal WASM Loader: package `universal_wasm_loader` on pub.dev. The
JS/TS `universalWasmLoader-js` is the reference implementation, and its `SPEC.md` is the
cross-language contract. What is released, and what is open, lives in [open-work.md](open-work.md),
not here.

## Repository home — `synapticforge1` organization (recorded 2026-10-20)

**https://github.com/synapticforge1/universalWasmLoader-dart**: transferred from the `jrmarcum` user
account to the owner-controlled `synapticforge1` organization (`4a9b9b7`). The old `jrmarcum/...` URL
only works through GitHub's redirect, which dies if a repo of that name is ever created under
`jrmarcum`. So `origin`, `pubspec.yaml` `repository:` and README all name the new owner. The
reference loader moved too: `synapticforge1/universalWasmLoader-js`. pub.dev ownership is a
Google-account fact and was unaffected. The 0.2.0 release proved the release path after the
transfer (see [releasing.md](releasing.md)).

## Runtime decision — dual-backend (web now, native later) 🔒

Dart is the **only** loader language that spans both worlds, so it is **dual-backend** (owner,
2026-06-15; see wasmtk `cmem/vision.md` → "Loader runtime + WASI strategy"):
- **Web backend (THIS, implemented):** browser `WebAssembly` via `dart:js_interop` + a hand-rolled
  WASI-P1 shim — the cheapest path, no native build step.
- **Native backend (TRACKED FUTURE):** `dart:ffi` → the **wasmtime C API** (Dart VM / Flutter
  desktop+mobile), getting wasmtime's built-in WASI. Selected vs. the web backend via conditional
  imports. Blocked only by the `libwasmtime` distribution cost (per-platform native binaries /
  native-assets) — its own mini-project, hence deferred. It would share marshalling with
  `universalWasmLoader-c`. Avoid `package:wasm` (Wasmer-based, effectively deprecated).

A Dart **web** app could instead `dart:js_interop`-call the published `-js` loader directly, but that
re-adds a JS dependency and works on web only; the native-Dart web impl here is preferred. The JS
loader CANNOT substitute on native (`dart:ffi` is unavailable on web; no JS engine on the Dart VM).

## API surface

Mirrors the reference loader in idiomatic Dart; the authoritative list is the generated
`api-surface.json` (34 keys on 2026-10-22, unchanged since 0.1.0; see [compat-gate.md](compat-gate.md)):
- `wasmImport(path, {hostCallbacks})` → a `Future<ModuleExports>`; auto-detects the companion `.wit`,
  applies the Canonical ABI, falls back to raw exports if there is no `.wit`. Supports the `@N`
  version-pin suffix (checked against the module's exported `version` global).
- `createSingleton(path, {hostCallbacks})` — caches the load; same instance every call.
- `InstancePool(path, {hostCallbacks, size})` — `acquire` / `release` / `run` over N instances.
- `ModuleExports` — `call` / `function` / `has` / `names` / `rawExports`.
- The WIT parser: `parseWit`, `ParsedWit`, `WitFunc`, `WitParam`, `kebabToCamel`, `kebabToWasmImportKey`.

## Conformance — SPEC 3.0.0

`SPEC.md` (in `-js`) is at **v3.0.0 (2026-06-15)**; README declares it as `SPEC.md` **v3.0.0**, which
`surface.dart` reads, so a SPEC move shows in the gate's floor. String/aggregate RETURNS use the
**canonical callee-allocated** convention: the export returns an i32 pointer to a `[ptr, len]` pair;
the host reads the little-endian pair, decodes UTF-8, then calls **`cabi_post_<name>(retPtr)`** to
release it. String PARAMS flatten to `(ptr, len)` written via `cabi_realloc(0,0,1,len)`. Numerics
pass through; `bool` is `1/0` ↔ `true/false`. There was never a legacy out-parameter path here.
**SPEC §10** (producer model) since 0.2.0 (`985039f`): the WASI-P1 shim is always attached, and a
reactor module's `_initialize` is called once after instantiation.

## File layout

- `lib/universal_wasm_loader.dart` — the public barrel; its export list IS the API surface.
- `lib/src/loader.dart` — `wasmImport`, `createSingleton`, `InstancePool`, version-suffix parsing,
  version-global assertion; attaches the WASI shim on both the no-WIT and WIT paths and calls
  `_initialize` (`_callInitialize`).
- `lib/src/abi.dart` — `buildComponentImportEnv` / `buildComponentExportProxy` + `ModuleExports`.
- `lib/src/wasi.dart` — **SPEC §10.2** hand-rolled `wasi_snapshot_preview1` (`buildWasiShim` +
  `WasiMemRef`): `fd_write`→`console.log`/`console.error`, `proc_exit`, `random_get`,
  `clock_time_get`, environ/args, `fd_close`/`fd_fdstat_get`/`fd_seek`. i64 writes are split into two
  i32 words (`ByteData.setInt64` is unsupported on the web).
- `lib/src/wasm_interop.dart` — `@JS` bindings: `WebAssembly.instantiate`, `fetch`, `Reflect.get/set`,
  memory views (`memoryBytes`, `readI32`).
- `lib/src/wit_parser.dart` — `parseWit` + `WitFunc`/`WitParam`/`ParsedWit` + kebab helpers.
- `test/` — see [testing.md](testing.md). `scripts/` — see [releasing.md](releasing.md) and
  [compat-gate.md](compat-gate.md). `api-surface.json` — the committed surface snapshot.
- `pubspec.yaml` — SDK `^3.4.0`; dep `web`; dev-deps `test`, `lints`, `crypto` (fixture check),
  `analyzer` (surface generator).
- `.pubignore` — keeps `cmem/`, `scripts/`, `CLAUDE.md`, `.claude/`, `api-surface.json` out of the
  pub.dev archive. ⚠️ A `.pubignore` REPLACES `.gitignore` for `dart pub publish`, so anything
  git-ignored that must also stay out of the archive is listed here too.
- `.gitignore` — also `.claude/settings.local.json` (per-machine). `.gitattributes` — LF everywhere
  (see [working-rules.md](working-rules.md)). `analysis_options.yaml` — `lints/recommended` +
  `strict-casts`.

## js_interop gotcha ⚠️

WASM calls each `env` import with the **flattened ABI arity** (a `string` param is two i32s). The
Dart closure handed to `.toJS` must tolerate that exact count — a fixed-arity closure throws
`NoSuchMethodError` when invoked with fewer args. The import wrappers use **optional positional
params** (8 slots) so any arity 0..8 is accepted. Export calls use `Function.prototype.apply`
(bound via `@JS('Function.prototype.apply.call')`) to pass an arbitrary arg count, since
`callAsFunction` is fixed at 4.
