# Testing — every gate, how to run it, what it can see

| Gate | Command | Sees | Blind to |
| --- | --- | --- | --- |
| Static | `dart analyze`; `dart format --output=none --set-exit-if-changed .` | types, lints, formatting | behaviour |
| Browser suite | `dart test -p chrome` (`@TestOn('browser')`; needs Chrome) | the SPEC §8 fixtures, lifecycle, both §10 tests | WIT/ABI shapes not in the fixtures |
| Fixtures | `dart run scripts/check_fixtures.dart` | `test/fixtures/` bytes vs the `-js` stamp | whether the stamp itself is current with `-js` |
| Compat gate | `dart run scripts/compat.dart` (+ `check_compat_gate.dart`) | API surface, SPEC version, previous tag's tests | behaviour the previous tests never exercised |

**Counts (2026-10-22, Dart 3.12.2 from scoop Flutter 3.44.2):** browser suite 9/9: math,
booleans, strings (canonical return), imports with host callbacks, `createSingleton` identity,
`InstancePool.run`, 2 concurrent pooled runs, §10.1 `_initialize` (no-WIT raw path, `init_check`),
§10.2 a WASI-using library (`wasi_io_50`, `logAndDouble(21)==42`, which loads only because the shim
supplies `fd_write`). The gate self-test passes 31/31; the fixture check covers 12 files.

## Reference fixtures (H7 / S4, done 2026-10-22, `bc53669`)

`test/fixtures/` is a **verbatim copy of `-js`'s `tests/` set**, including `fixtures.json`, the stamp:
wasmtk `f50c8e4` (`v2.0.3-64-gf50c8e419a0`) and a sha256 per file (12 files). It was copied from
`-js` `1cfb863`. Before the copy, only `strings_50.wasm`, `wasi_io_50.wasm` (other bytes) and
`init_check.wat` (missing) were off. The workspace note "dart's four match" was wrong about
`strings_50`.

**To refresh when `-js` regenerates:** copy every file its `tests/fixtures.json` lists, plus that file,
into `test/fixtures/`; run `check_fixtures.dart` and the browser suite. Never edit a fixture by hand;
never copy without the stamp. The fixture check is blocking in `publish.yml`.

## SPEC §10 conformance per port (workspace S5)

Dart already has the two tests above. Whether they match the shared §10 test the workspace may
define is open ([open-work.md](open-work.md)).
