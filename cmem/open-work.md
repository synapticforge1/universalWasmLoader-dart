# Open work — the ONE list (status lives here and nowhere else)

**State (2026-10-22):** 0.2.1 is the latest on pub.dev (SPEC 3.0.0 + §10), and `main` = `v0.2.1`
(`1fc0757`) plus memory commits only. Every release from here on passes the blocking
compatibility gate in CI.

## Open

- **S5:** check the two §10 tests against the shared §10 conformance test, once the workspace
  defines one ([testing.md](testing.md)).
- **Native backend** (`dart:ffi` → wasmtime C API): tracked future ([overview.md](overview.md)).

## Done (summaries with pointers)

- **0.2.1 released (2026-10-22, owner: "bump and push"), tag → `1fc0757`:** README §10 correction,
  stamped fixtures, and the first release through the gate ([releasing.md](releasing.md)).
- **H6 (2026-10-22, `36378fd`):** SemVer gate ([compat-gate.md](compat-gate.md)); ★ block copied
  ([best-practices.md](best-practices.md)); memory split per `memory-conventions.md`; tooling rules
  ([working-rules.md](working-rules.md)). `bump.dart` was already plain SemVer.
- **H7 / S4 (2026-10-22, `bc53669`):** fixtures = the stamped `-js` set ([testing.md](testing.md)).
- **Org transfer (2026-10-20, `4a9b9b7`)**, Dart-only scripts (`a75b167`), LF (`b9f4e9c`), 0.2.0 release
  (`f550a37`).
