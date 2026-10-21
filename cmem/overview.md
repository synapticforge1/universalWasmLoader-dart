# Overview — universalWasmLoader-dart

The **Dart** port of the Universal WASM Loader (Stage 2 of the polyglot loader ecosystem; the JS/TS
`universalWasmLoader-js` is the reference, and `SPEC.md` is the cross-language contract). Intended to
publish to **pub.dev**.

## Repository home — `synapticforge1` organization (recorded 2026-10-20)

The GitHub repo was **transferred from the `jrmarcum` user account to the owner-controlled
`synapticforge1` organization**: canonical URL **https://github.com/synapticforge1/universalWasmLoader-dart**
(GitHub API confirms `full_name` = `synapticforge1/universalWasmLoader-dart`, owner type
`Organization`, default branch `main`). The old `jrmarcum/...` URL still works through GitHub's
redirect, but that redirect stops working if a repo with the old name is ever created under
`jrmarcum`. So every reference points at the new owner: `origin`, `pubspec.yaml` `repository:`,
and README. The reference loader moved with it: `synapticforge1/universalWasmLoader-js` (the old
`jrmarcum/universalWasmLoader` link resolves there).

- **pub.dev is unaffected by the transfer.** Package ownership is a pub.dev/Google-account fact, not
  a GitHub one. The `repository:` URL shown on pub.dev only changes with the next publish.
- **Not re-verified after the transfer (needs org-admin access):** (1) that the `PUB_DEV_CREDENTIALS`
  repo secret is still present, and (2) the `synapticforge1` org's Actions policy. The `run:`-only
  workflow below has no `uses:` steps, so it keeps working whatever that policy allows. Check both
  before the next release tag.

## Status — PUBLISHED to pub.dev, web-first (first publish 2026-06-24)

**`universal_wasm_loader` 0.1.0 is live on https://pub.dev/packages/universal_wasm_loader**
(first publish 2026-06-24 via the CI workflow — conclusion `success`; tag `v0.1.0`; GitHub Release
`v0.1.0` created). It was a brand-new name, so the `jrmarcum` account is the uploader/owner;
**not** under a pub.dev verified publisher (a future publish could carry one if set up first).
The `PUB_DEV_CREDENTIALS` repo secret is in place, so subsequent releases need only bump + tag.

Implemented against **SPEC 3.0.0** as a **web-only** package using `dart:js_interop` over the
browser's native `WebAssembly` + `fetch`. All of `wasmImport` / `createSingleton` / `InstancePool`,
WIT auto-detection, the `@N` version pin, and the full Canonical ABI (numerics pass-through; `bool`
1/0 ↔ true/false; string params via `cabi_realloc(0,0,1,len)`; string returns via the
callee-allocated `[ptr,len]` pair + `cabi_post_<name>` release) are in place.

### Runtime decision — dual-backend (web now, native later)

Dart is the **only** loader language that spans both worlds, so it is **dual-backend** (owner,
2026-06-15; see wasmtk `cmem/vision.md` → "Loader runtime + WASI strategy"):
- **Web backend (THIS, implemented):** browser `WebAssembly` via `dart:js_interop` + a hand-rolled
  WASI-P1 shim — the cheapest path, no native build step.
- **Native backend (TRACKED FUTURE):** `dart:ffi` → the **wasmtime C API** (Dart VM / Flutter
  desktop+mobile), getting wasmtime's built-in WASI. Selected vs. the web backend via conditional
  imports. Blocked only by the `libwasmtime` distribution cost (per-platform native binaries /
  native-assets) — its own mini-project, hence deferred.

Note: a Dart **web** app could instead `dart:js_interop`-call the published `-js` loader directly, but
that re-adds a JS dependency and works on web only; the native-Dart web impl here is preferred. The JS
loader CANNOT substitute on native (`dart:ffi` is unavailable on web; no JS engine on the Dart VM).

### File layout

- `pubspec.yaml` — package `universal_wasm_loader`, version `0.1.0`, SDK `^3.4.0`; deps `web`,
  dev-deps `test` + `lints`.
- `.pubignore` — excludes `cmem/`, `scripts/`, `CLAUDE.md` from the published pub.dev archive.
- `analysis_options.yaml` — `package:lints/recommended` + `strict-casts`.
- `lib/universal_wasm_loader.dart` — public barrel (exports `wasmImport`, `createSingleton`,
  `InstancePool`, `ModuleExports`, the WIT parser surface).
- `lib/src/wit_parser.dart` — `parseWit` + `WitFunc`/`WitParam`/`ParsedWit` + kebab helpers.
- `lib/src/wasm_interop.dart` — `@JS` bindings for `WebAssembly.instantiate`, `fetch`,
  `Reflect.get/set`, memory views (`memoryBytes`, `readI32`).
- `lib/src/abi.dart` — `buildComponentImportEnv` / `buildComponentExportProxy` + the `ModuleExports`
  handle (`call`/`function`/`has`/`names`/`rawExports`).
- `lib/src/wasi.dart` — **SPEC §10.2** minimal WASI Preview 1 shim (`buildWasiShim` + `WasiMemRef`):
  a hand-rolled `wasi_snapshot_preview1` import object built from Dart closures via `.toJS`
  (`fd_write`→`console.log`/`console.error`, `proc_exit`, `random_get`, `clock_time_get`,
  environ/args, `fd_close`/`fd_fdstat_get`/`fd_seek`). Web-safe i64 writes split into two i32 words
  (`ByteData.setInt64` is unsupported on the web). Like `-js` (and unlike the native ports), the web
  backend can't use a runtime built-in, so the shim is hand-rolled.
- `lib/src/loader.dart` — `wasmImport`, `createSingleton`, `InstancePool`, version-suffix parsing,
  version-global assertion. **SPEC §10:** always attaches the WASI shim to the imports (both the
  no-WIT and WIT branches) and calls a reactor module's `_initialize` (`_callInitialize`) once after
  instantiation.
- `test/loader_test.dart` (`@TestOn('browser')`) + `test/fixtures/*.{wasm,wit}` (the four
  `*_50` reference fixtures + the §10 fixtures `init_check.wasm` and `wasi_io_50.{wasm,wit}`).

### Verification level — `dart analyze` clean + browser tests PASS

Dart SDK 3.12.2 (bundled in the scoop Flutter 3.44.2 install). `dart analyze` → **No issues found**;
`dart format .` clean. **`dart test -p chrome` ran in real Chrome and all 9 tests passed** (math,
booleans, strings incl. the Canonical string return, imports with host callbacks, `createSingleton`
identity, `InstancePool.run`, 2 concurrent pooled runs, plus the two **SPEC §10** tests: §10.1
`_initialize` on the no-WIT raw path via `init_check.wasm`, and §10.2 a WASI-using library
`wasi_io_50.wasm` — `logAndDouble(21)==42` — instantiating only because the shim supplies
`fd_write`). Added 2026-07-05.

### Key js_interop note (gotcha)

WASM calls each `env` import with the **flattened ABI arity** (a `string` param is two i32s). The
Dart closure handed to `.toJS` must tolerate that exact count — a fixed-arity closure throws
`NoSuchMethodError` when invoked with fewer args. The import wrappers use **optional positional
params** (8 slots) so any arity 0..8 is accepted. Export calls use `Function.prototype.apply`
(bound via `@JS('Function.prototype.apply.call')`) to pass an arbitrary arg count, since
`callAsFunction` is fixed at 4.

## API surface (implemented, published in 0.1.0)

Mirrors the reference loader in idiomatic Dart:
- `wasmImport(path, {hostCallbacks})` → a `Future` resolving to a `ModuleExports` handle; auto-detects
  the companion `.wit`, applies the Canonical ABI, falls back to raw exports if there is no `.wit`.
  Supports the `@N` version-pin suffix (checked against the module's exported `version` global).
- `createSingleton(path, {hostCallbacks})` — caches the load; same instance every call.
- `InstancePool(path, {hostCallbacks, size})` — `acquire` / `release` / `run` over N instances.

The runtime choice (formerly an open decision) is settled: see "Runtime decision — dual-backend" above.
Native-backend note kept from that analysis: `package:wasm` (Wasmer-based) is effectively deprecated,
so avoid it. The wasmtime C API path would share marshalling with `universalWasmLoader-c`.

## Conformance — SPEC 3.0.0

`SPEC.md` (cross-language) is at **v3.0.0 (2026-06-15)**. String/aggregate RETURNS use the **canonical
callee-allocated** convention: the export returns an i32 pointer to a callee-allocated `[ptr, len]`
pair; the host reads the little-endian pair, decodes UTF-8, then calls the paired
**`cabi_post_<name>(retPtr)`** export to release it. String PARAMS flatten to `(ptr, len)` written via
`cabi_realloc(0,0,1,len)`. Numerics pass through; `bool` is `1/0` ↔ `true/false`. Implement the NEW
convention from the start — there is **no legacy out-parameter code to migrate** here.

## Tests

`dart test -p chrome` (browser-only, `@TestOn('browser')`), against the reference-suite fixtures
(`math_50` / `booleans_50` / `strings_50` / `imports_50`) plus the lifecycle scenarios
(`createSingleton`, `InstancePool`) and the two §10 fixtures. `strings_50.wasm` exercises the
canonical return path.

**Fixture drift (workspace finding S4, received via handoff H7, 2026-09-20):** 3 of dart's 4
`*_50.wasm` files are **not** byte-identical to the set shared by c/dotnet/go/js/rs/jvm. The fix
agreed across the workspace is to regenerate every loader's fixtures from ONE `wasmtk modc` run,
stamp the source commit, and commit identical bytes. That is still open (see "Open work").

## Open work (as of 2026-10-20)

- **Unpushed commit:** local `main` is 1 ahead of `origin/main`. `985039f` (SPEC §10 WASI shim +
  `_initialize`) is not on GitHub yet. Pushing is the owner's call.
- **Handoff H7 / S4:** replace the 3 drifted fixtures with the single-`wasmtk modc`-run set, then
  re-run `dart test -p chrome`.
- **Handoff H6 (every repo):** SemVer 2.0.0 with a compatibility gate on the bump script
  (`scripts/bump.dart` / `bump.sh`), the workspace ★ rules block in a `best-practices.md`, memory
  layout per `../../cmem/memory-conventions.md`. Not started.
- **S5:** the workspace asks for a SPEC §10 conformance test per loader port. Dart already has two
  (§10.1 `_initialize`, §10.2 WASI-using library). Whether they match the eventual shared test is TBD.
- **Post-transfer checks:** `PUB_DEV_CREDENTIALS` secret and `synapticforge1` Actions policy (see
  "Repository home").
- **Native backend:** tracked future (see "Runtime decision").

## Release flow (implemented 2026-06-15)

**Version source:** `pubspec.yaml` (`version:`) is the single source of truth.

**Bump → tag → push:**

1. `dart run scripts/bump.dart [patch|minor|major]` (default `patch`) — or the pure-POSIX
   `scripts/bump.sh` — raises the `version:` line with a targeted edit (rest of the file untouched).
   Mirrors `-js`'s `scripts/bump.ts` UX.
2. `scripts/release.sh` — commits a pending pubspec bump, tags `vX.Y.Z` from the current
   `pubspec.yaml` version, and pushes the tag. It NEVER runs `dart pub publish` locally (mirrors
   `-js`'s `scripts/publish.ts`, which only tags + pushes so CI publishes).
3. The pushed `v*` tag triggers `.github/workflows/publish.yml`, which publishes to pub.dev.

**`.github/workflows/publish.yml` — `run:`-only (Actions policy).** The policy under which this was
built (pre-transfer, owner `jrmarcum`) permitted only `jrmarcum`-owned actions. The `synapticforge1`
org's policy has not been re-checked (see "Repository home"). Under that policy ANY third-party `uses:` step (incl. `actions/checkout`, `dart-lang/setup-dart`,
and the official `dart-lang/setup-dart/.github/workflows/publish.yml` reusable OIDC workflow) causes a
`startup_failure` — nothing runs. So every step is a plain `run:` step:
- checkout via `git clone --depth=1 --branch <tag> https://x-access-token:<token>@github.com/<repo> .`
- install the Dart SDK from the official Dart apt repo (`/usr/lib/dart/bin` → `$GITHUB_PATH`)
- `dart pub get`, `dart analyze`, best-effort `dart test -p chrome` (web-only package; skipped with a
  logged `::warning::` if no Chrome on the runner — does not block publish)
- write the `PUB_DEV_CREDENTIALS` secret to `pub-credentials.json` (in `$HOME/.config/dart/`,
  `$XDG_CONFIG_HOME/dart/` if set, and `$HOME/.pub-cache/credentials.json` for older SDKs), then
  `dart pub publish --force`
- `gh release create` for the tag

**Why credentials-file, not OIDC:** the official pub.dev automated-publishing path is the
`dart-lang/setup-dart/.github/workflows/publish.yml` reusable workflow — a third-party `uses:`,
forbidden by org policy. So we use a credentials-file publish in `run:` steps instead.

### Required owner setup (one-time)

1. **Own the package on pub.dev.** The package name `universal_wasm_loader` must be created/owned by
   the publishing account (a verified publisher is recommended if used). First publish of a brand-new
   name will create it under your account.
2. **Generate the `PUB_DEV_CREDENTIALS` secret.** Locally run `dart pub login` and complete the
   Google OAuth flow. This writes `pub-credentials.json` to Dart's config dir:
   - Linux: `$XDG_CONFIG_HOME/dart/pub-credentials.json` (or `~/.config/dart/pub-credentials.json`)
   - Windows: `%APPDATA%\dart\pub-credentials.json`
   - macOS: `~/Library/Application Support/dart/pub-credentials.json`
   Copy the FULL JSON contents of that file into a GitHub repo secret named **`PUB_DEV_CREDENTIALS`**
   (Settings → Secrets and variables → Actions → New repository secret). It contains a refresh token,
   so treat it as sensitive; rotate by re-running `dart pub login` and updating the secret.

### Published archive contents — `.pubignore` (added 2026-06-24)

A root `.pubignore` (gitignore syntax; consulted only by `dart pub publish`) keeps internal files in
git but **out of the published tarball**: `cmem/`, `scripts/`, and `CLAUDE.md`. This shrank the
archive from **19 KB → 12 KB**; `dart pub publish --dry-run` stays at **0 warnings**. The published
tree is `lib/`, `test/` (incl. `*.wasm`/`*.wit` fixtures), `README.md`, `CHANGELOG.md`, `LICENSE`,
`pubspec.yaml`, `analysis_options.yaml`.

### First publish (2026-06-24) — DONE via CI

`dart pub publish --dry-run` (Dart 3.12.2) had previously validated 0-warnings/exit-0. The real
publish was performed by the CI flow: `scripts/release.sh` committed the `.pubignore` change, tagged
`v0.1.0` from `pubspec.yaml`, and pushed `main` + the tag; `.github/workflows/publish.yml` ran to
**success** and uploaded to pub.dev (verified: `GET pub.dev/api/packages/universal_wasm_loader` →
200, `"version":"0.1.0"`). Both bump scripts remain verified for patch/minor/major + bad-kind
rejection.
