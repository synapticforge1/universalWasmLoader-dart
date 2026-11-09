# universalWasmLoader-dart

Universal WASM loader for Dart — the Dart port of the
[Universal WASM Loader](https://github.com/synapticforge1/universalWasmLoader-js), implementing the
cross-language `SPEC.md` **v4.0.0**.

Load a WebAssembly "DLL" the way the reference loader does: auto-detect the companion `.wit`, apply
the Canonical ABI (wasmtime profile), and get back a typed handle.

> **Web-only.** This package targets the **browser** (and Flutter web): it uses
> `dart:js_interop` over the browser's native `WebAssembly` and `fetch`. There is no Dart-VM /
> native runtime yet (see *Runtime* below).

## Install

Published on pub.dev: **[universal_wasm_loader](https://pub.dev/packages/universal_wasm_loader)**.

```bash
dart pub add universal_wasm_loader
```

## Usage

```dart
import 'package:universal_wasm_loader/universal_wasm_loader.dart';

Future<void> main() async {
  // Auto-detects ./math_50.wit, applies the Canonical ABI.
  final m = await wasmImport('math_50.wasm');
  print(m.call('add', [3, 4]));        // 7
  print(m.call('multiply', [2.5, 4])); // 10.0

  // Strings (Canonical ABI: cabi_realloc params, callee-allocated returns).
  final s = await wasmImport('strings_50.wasm');
  print(s.call('greet', ['World']));   // "Hello, World!"

  // Host import callbacks, keyed by camelCase WIT name: one for every WIT import.
  final i = await wasmImport('imports_50.wasm', hostCallbacks: {
    'envMul': (num a, num b) => a * b,
    'envAdd': (num a, num b) => a + b,
  });
  print(i.call('scale', [3.0, 4.0]));  // 12.0

  // Version pinning (SPEC §3): ./mod.wasm@2 checks the module's `version` global.
  // final v = await wasmImport('mod.wasm@2');

  // A 5 s limit per fetch instead of the default 30 s, and a cancel token.
  final token = LoadCancelToken();
  final f = await wasmImport('https://example.com/mod.wasm',
      options: LoadOptions(timeout: const Duration(seconds: 5), cancel: token));
}
```

### What fails, and how (SPEC 4.0.0)

The loader never guesses. Each of these is an error, not a default value:

| Situation | Error |
| --- | --- |
| The `.wit` answers anything but 2xx, 404 or 410, or the network fails | `StateError` naming the URL (before the `.wasm` is fetched) |
| The `.wit` does not parse, or uses a type outside `s32 s64 f32 f64 bool string` | `FormatException` naming the `.wit` and the fault |
| A WIT import has no host callback | `ArgumentError` naming every missing one, at load |
| A WIT import returns `string` | `UnsupportedError`, at load |
| A WIT export is missing from the module | `StateError` naming it, at load |
| The `.wasm` answers an HTTP error | `StateError` naming the status and URL (one request) |
| A fetch takes longer than `options.timeout` (default 30 s; `null` = no limit) | `TimeoutException` naming the URL and the limit |
| `options.cancel` is cancelled | the reason given to `cancel` (else a `StateError`) |
| A typed call has the wrong number of arguments, or one outside its type | `ArgumentError` naming the export and the parameter |
| A host callback returns a value outside its WIT result, or a `Future` | `ArgumentError` naming the callback, reaching the export's caller |

Only an absent `.wit` (HTTP 404 / 410, or a path that does not end in `.wasm`) gives raw exports.
Typed arguments are checked, never coerced: `s32` takes an `int` in the 32-bit range, `s64` an `int`
or a `BigInt` (and returns a `BigInt`), `f32` / `f64` a `num`, `bool` a `bool`, `string` a `String`.

### Instance lifecycle

```dart
// Singleton — loads once, caches (CLI / bounded-call scenarios).
final getMod = createSingleton('math_50.wasm');
final a = await getMod();
final b = await getMod(); // same instance

// Pool — N independent instances for concurrency.
final pool = InstancePool('math_50.wasm', size: 4);
final result = await pool.run((mod) => mod.call('square', [6])); // 36
```

`ModuleExports` exposes `call(name, [args])`, `function(name)`, `has(name)`, `names`, and the raw
`rawExports` escape hatch.

## Runtime

Implemented against the browser `WebAssembly` API via `dart:js_interop`. A native Dart-VM backend
(e.g. wasmtime via `dart:ffi`) is a possible follow-up but is not part of this package.

SPEC §10 (producer model) is implemented since 0.2.0. Every module gets a minimal WASI Preview 1 shim
(`wasi_snapshot_preview1`; `fd_write` goes to the browser console), so library modules that do I/O
load in the browser. A reactor module's exported `_initialize` is called once, automatically, right
after instantiation; don't call it yourself.

### ⚠️ Breaking Changes

| Version | What changed | How to migrate |
| --- | --- | --- |
| 0.3.0 | SPEC 4.0.0: loads and calls that 0.2.x accepted silently now fail (table above): a `.wit` that answers an HTTP error or does not parse, a missing host callback, a callback result of the wrong kind, a typed-call argument of the wrong count or kind, an `s64` value (now a `BigInt` result). `wasmImport`, `createSingleton` and `InstancePool` take a new `options` parameter (30 s default fetch limit). `parseWit` throws `FormatException`. | Pass a callback for every WIT import that returns its WIT result type; pass `int` / `num` / `bool` / `String` arguments that match the WIT exactly; fix or remove a malformed `.wit` (a server must answer 404 for an absent one). Use `LoadOptions(timeout: null)` for a fetch that may take over 30 s. |
| 0.2.0 | A module's exported `_initialize` is now called automatically after instantiation (behaviour, not API). | Remove any manual call to `_initialize`; calling it again initializes the module twice. |

From the release after 0.2.0 on, every release is checked against the previous one by
`scripts/compat.dart` (added 2026-10-22): a removed or changed API symbol requires a major version (pre-1.0: a minor plus a row
here), and the previous release's tests must still pass for a patch or minor.

## Testing

```bash
dart pub get
dart analyze
dart test -p chrome   # requires a Chrome/Chromium browser
dart run scripts/check_fixtures.dart
```

Tests run against the shared reference fixtures in `test/fixtures/` (`math_50`, `booleans_50`,
`strings_50`, `imports_50`, plus the §10 fixtures `wasi_io_50` and `init_check`), covering the
SPEC §8 suite with its 4.0.0 Refusals table, the lifecycle scenarios, and §10. The HTTP cases
(status codes, a server that never answers) use a local test server started by the suite
(`test/support/http_server.dart`). The fixtures are byte-identical copies of the
reference loader's set, built by `wasmtk modc`. `test/fixtures/fixtures.json` stamps the wasmtk
commit and each file's sha256, and `scripts/check_fixtures.dart` verifies them against it.

## Releasing

The package version lives in **`pubspec.yaml`** (`version:`) — the single source of truth.

```bash
# 0. See what the next release must be (compares with the last release tag).
dart run scripts/compat.dart

# 1. Raise the version (default: patch). Refused if below the compatibility floor.
dart run scripts/bump.dart            # 0.1.0 → 0.1.1
dart run scripts/bump.dart minor      # 0.1.0 → 0.2.0
dart run scripts/bump.dart major      # 0.1.0 → 1.0.0

# 2. (optional) Validate the package without uploading.
dart pub publish --dry-run

# 3. Tag vX.Y.Z from pubspec.yaml and push — this triggers CI to publish.
dart run scripts/release.dart
```

**The compatibility gate.** `bump.dart` (and CI, again, on the tag) diffs the public API against the
last release using the committed `api-surface.json`, which is generated by `dart run
scripts/surface.dart`. A removed or changed symbol needs a major, an added one at least a minor. The
previous release's tests must also pass against the new code for a patch or minor. Before 1.0, a
minor may stand in for a major, but it needs a row labelled `_next release_` in the Breaking
Changes table above. `bump.dart` replaces that label with the version, and does the same for the
CHANGELOG's Unreleased heading. An intended API change re-baselines `api-surface.json` in its own commit first.

Pushing a `v*` tag runs `.github/workflows/publish.yml` in three jobs, each holding only what it
needs:

- **`checks`** has a read-only token and no secrets. It installs the Dart SDK and dependencies and
  runs analysis, the browser tests, the release-script tests, the fixture check and the
  compatibility gate (the last three blocking).
- **`publish`** runs only after `checks` passes, on a fresh runner, with a read-only token. It runs
  only the Dart SDK (`dart pub publish`, plus `scripts/ci_release.dart`, which uses only Dart's
  core libraries). No dependency's code ever runs where the pub.dev credentials are on disk, and
  the credentials are deleted afterwards. If pub.dev already has the version, the upload is
  skipped, so a re-run can finish a release.
- **`release`** makes the GitHub Release page through GitHub's REST API. It is the only job that
  can write to the repository, and it has no credentials and no checkout: it fetches that one
  script at the tagged commit.

Every job refuses to go on if the tag has moved off the commit that triggered the run.

> **`run:`-only workflow.** The GitHub Actions policy permits only first-party (owner-owned) actions, so
> the publish workflow uses **no `uses:` steps** — checkout is `git clone`, the SDK is installed via
> the Dart apt repo, and publishing is the `dart pub` CLI. The official pub.dev OIDC automated-publishing
> reusable workflow (`dart-lang/setup-dart/.github/workflows/publish.yml`) is a third-party action and
> therefore **cannot be used here**; we publish with a credentials file instead.

### Owner setup (one-time)

1. **Own the package on pub.dev.** `universal_wasm_loader` must be created/owned by the publishing
   account (use a verified publisher if desired). The first publish of a new name creates it.
2. **Create the `PUB_DEV_CREDENTIALS` repo secret.** Run `dart pub login` locally and complete the
   Google OAuth flow; this writes `pub-credentials.json` to Dart's config dir
   (Linux `~/.config/dart/`, Windows `%APPDATA%\dart\`, macOS `~/Library/Application Support/dart/`).
   Copy the **entire JSON** into a GitHub Actions secret named `PUB_DEV_CREDENTIALS`
   (Settings → Secrets and variables → Actions). It holds a refresh token — keep it secret; rotate by
   re-running `dart pub login` and updating the secret.
