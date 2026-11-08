# Testing — every gate, how to run it, what it can see

| Gate | Command | Sees | Blind to |
| --- | --- | --- | --- |
| Static | `dart analyze`; `dart format --output=none --set-exit-if-changed .` | types, lints, formatting | behaviour |
| Browser suite | `dart test -p chrome` (`@TestOn('browser')`; needs Chrome) | the SPEC §8 fixtures and its 4.0.0 Refusals table, lifecycle, both §10 tests, the http cases (local server), s64 | WIT/ABI shapes not in the fixtures or the test server; a callback whose arity is wrong |
| Fixtures | `dart run scripts/check_fixtures.dart` | `test/fixtures/` bytes vs the `-js` stamp | whether the stamp itself is current with `-js` |
| Compat gate | `dart run scripts/compat.dart` (+ `check_compat_gate.dart`) | API surface, SPEC version, previous tag's tests | behaviour the previous tests never exercised |

**Counts (2026-10-22, Dart 3.12.2 from scoop Flutter 3.44.2):** browser suite 9/9: math,
booleans, strings (canonical return), imports with host callbacks, `createSingleton` identity,
`InstancePool.run`, 2 concurrent pooled runs, §10.1 `_initialize` (no-WIT raw path, `init_check`),
§10.2 a WASI-using library (`wasi_io_50`, `logAndDouble(21)==42`, which loads only because the shim
supplies `fd_write`). The gate self-test passes 31/31; the fixture check covers 12 files.

**Counts (2026-11-07, Dart 3.13.7, `5e24ae3`):** browser suite **37/37** = the 9 above + 28 for SPEC
4.0.0: host-callback refusals (none, one missing, six wrong results, an `async` one), typed-call
arguments (count, kind, range, explicit `null`, through `call` and `function`), strict parsing (9
faults + the valid forms), and the http group. **Inverted:** the 14 non-http refusal tests run red
on v0.2.1's `lib/` (a scratch worktree; the http group cannot compile against the old API); a
mutant of the new code with the `.wit`-500 fallback and no timer turned exactly the 3 matching http
tests red. Gate: v0.2.1's own tests 9/9 on the new code.

## The http test server (`test/support/http_server.dart`, 2026-11-07)

Started by `spawnHybridUri` in the Dart VM beside the browser suite (loopback, port 0, CORS `*`).
URLs are `/<mode>/<tag>/<file>`: the mode picks the `.wit` and `.wasm` behaviour (a status, `hang`,
`partial` body, a custom `.wit` such as `u32wit`, or the hand-built `add64` s64 module); the tag keeps
each test's request counts apart; `GET /__counts` returns them, which is how "one request per file"
and "the `.wasm` is never fetched" are checked. `hybridMain` takes a `dynamic` channel, so
`stream_channel` need not become a direct dev-dependency. The hang tests use a 200–300 ms limit; a
test that loses its limit waits for `package:test`'s own 30 s timeout instead (the mutant run took
1 min for that reason).

## Reference fixtures (H7 / S4, done 2026-10-22, `c7b37f6`)

`test/fixtures/` is a **verbatim copy of `-js`'s `tests/` set** (copied from `-js` `1cfb863`,
2026-10-22), with `fixtures.json`, the stamp: the wasmtk commit and a sha256 per file (12 files).
Before that copy, only `strings_50.wasm`, `wasi_io_50.wasm` (other bytes) and `init_check.wat`
(missing) were off. The workspace note "dart's four match" was wrong about `strings_50`.

**Re-stamped 2026-10-26 (C11 / H7):** wasmtk rewrote its history twice (2026-10-23,
2026-10-26), so the stamped `f50c8e4` (`jrmarcum/wasmtk`) no longer exists; through wasmtk's two maps
it is `84b3e180eba` → **`4a5c3cf668d`** (`v2.0.3-64-g4a5c3cf6`, same commit time, on
`synapticforge1/wasmtk` `origin/main`). Measured, not assumed: a scratch clone at `4a5c3cf668d`
(clean before and after), `-js`'s `regen-fixtures.ts` steps run by hand (its script writes into
`-js`), → all five source blob ids equal the stamp's, and **all 10 rebuilt `.wasm` / `.wit` files are
sha256-identical** to the stamp and to `test/fixtures/` (Deno 2.9.8). Inverted: one byte appended to a
rebuilt file was refused. So only `generator.repository` / `commit` / `describe` changed. `-js`
re-stamped the same day (`36aa661`, on its `origin/main`, released in 1.1.2): every fixture blob of
its set equals ours (12 / 12), and its `fixtures.json` differed from the one our script wrote in ONE
line, `describe` — `g4a5c3cf` there, `g4a5c3cf6` here: `git describe` abbreviates to a length that
depends on the clone, so the field is not reproducible across clones. **`-js`'s `fixtures.json` was
then copied verbatim** (the rule above), so `test/fixtures/` is byte-identical to `-js` `36aa661`.

**To refresh when `-js` regenerates:** copy every file its `tests/fixtures.json` lists, plus that file,
into `test/fixtures/`; run `check_fixtures.dart` and the browser suite. Never edit a fixture by hand;
never copy without the stamp. The fixture check is blocking in `publish.yml`.

## SPEC §10 conformance per port (workspace S5)

Dart already has the two tests above. Whether they match the shared §10 test the workspace may
define is open ([open-work.md](open-work.md)).
