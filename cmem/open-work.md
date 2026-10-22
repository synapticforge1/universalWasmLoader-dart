# Open work — the ONE list (status lives here and nowhere else)

**State (2026-10-22):** 0.2.0 is the latest on pub.dev (SPEC 3.0.0 + §10). `main` is ahead of
`v0.2.0` with H7 (`bc53669`) and H6 (the compatibility gate, ★ block, memory layout). No library
code has changed since 0.2.0, and the gate's floor against `v0.2.0` is patch.

## Open

- **Release 0.2.1** 🔒 owner decided 2026-10-22 ("bump and push"). It carries the README §10
  correction (pub.dev's 0.2.0 README says §10 is "Not implemented"), the stamped fixtures, and the
  first CI run of the blocking gate. In progress: bump with the gate, then tag.
- **S5:** check the two §10 tests against the shared §10 conformance test, once the workspace
  defines one ([testing.md](testing.md)).
- **Native backend** (`dart:ffi` → wasmtime C API): tracked future ([overview.md](overview.md)).

## Done (summaries with pointers)

- **H6 (2026-10-22):** SemVer gate ([compat-gate.md](compat-gate.md)); ★ block copied
  ([best-practices.md](best-practices.md)); memory split per `memory-conventions.md`; tooling rules
  ([working-rules.md](working-rules.md)). `bump.dart` was already plain SemVer.
- **H7 / S4 (2026-10-22, `bc53669`):** fixtures = the stamped `-js` set ([testing.md](testing.md)).
- **Org transfer (2026-10-20, `4a9b9b7`)**, Dart-only scripts (`a75b167`), LF (`b9f4e9c`), 0.2.0 release
  (`f550a37`).
