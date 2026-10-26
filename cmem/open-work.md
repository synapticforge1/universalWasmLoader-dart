# Open work — the ONE list (status lives here and nowhere else)

**State (2026-10-26):** 0.2.1 is the latest on pub.dev (SPEC 3.0.0 + §10), and `main` = `v0.2.1`
(`ae231db`, post-purge id) plus memory / fixture-stamp commits only. Every release from here on
passes the blocking compatibility gate in CI. The history was purged of a drive path and
force-pushed on 2026-10-26 (H19, [history-map-2026-10-26.md](history-map-2026-10-26.md)).

## Open

- **🗓️ OWNER (optional):** GitHub serves the pre-purge commits by hash until its GC; removing them
  is a GitHub Support request. The private pre-purge bundle may be deleted once you are satisfied
  ([local/environment.md](local/environment.md)).
- **S5:** check the two §10 tests against the shared §10 conformance test, once the workspace
  defines one ([testing.md](testing.md)).
- **Native backend** (`dart:ffi` → wasmtime C API): tracked future ([overview.md](overview.md)).

## Done (summaries with pointers)

- **H19 force-pushed 2026-10-26** (owner: "try the force push"): `main` → `0bcd2e9` and the three
  tags, each with a lease on its old value; GitHub accepted all four (no immutable release);
  `ls-remote` = local; all 22 pushed commits re-scanned with `-a`, 0 hits. The tag moves re-ran
  `publish.yml` three times (runs 40383568732 for v0.1.0, 40383568400 for v0.2.1, and one for v0.2.0): every step green up to
  **"Publish to pub.dev" — failed (version exists)**, "Create GitHub Release" skipped; pub.dev
  read back unchanged (latest 0.2.1, original publish dates). Expected and harmless, as predicted.
- **Workspace letters, 2026-10-26** (owner: "perform H19 and C11/H7 and C8"; one commit after the
  purge): **H19** history purged of the drive path, verified pair by pair
  ([history-map-2026-10-26.md](history-map-2026-10-26.md)); **H18 / H25 §3(c)** `CLAUDE.md` clean at
  HEAD; **H16** `maintenance.strategy gc` (1 pack); **H22 / H25 §3(d)** path test recorded
  ([working-rules.md](working-rules.md) § Privacy); **H24 + C8 + H27** ★ block re-copied (5.2,
  6.1) and re-stamped `Copied from synapticforge1/…` after a 28 = 28 / 0-difference text check
  ([best-practices.md](best-practices.md)); **C11 / H7** fixtures re-stamped to wasmtk
  `4a5c3cf668d`, bytes proven identical by rebuilding, then `-js` `36aa661`'s stamp copied verbatim
  ([testing.md](testing.md)). Record-only: **H15** conforms (Dart scripts since `3883d61`); **H20**
  pub.dev published 0.2.1 after the org move; **H28** the email exception widened
  ([working-rules.md](working-rules.md) § Privacy; this repo keeps the address on commits only).
  **The pull line** (owner: "fix the handoff notation", 2026-10-26): `CLAUDE.md` now reads
  `workspace-correspondence.md` first, then `handoffs.md`, as INDEX and working-rules do.
- **0.2.1 released (2026-10-22, owner: "bump and push"), tag → `ae231db`:** README §10 correction,
  stamped fixtures, and the first release through the gate ([releasing.md](releasing.md)).
- **H6 (2026-10-22, `41b9fda`):** SemVer gate ([compat-gate.md](compat-gate.md)); ★ block copied
  ([best-practices.md](best-practices.md)); memory split per `memory-conventions.md`; tooling rules
  ([working-rules.md](working-rules.md)). `bump.dart` was already plain SemVer.
- **H7 / S4 (2026-10-22, `c7b37f6`):** fixtures = the stamped `-js` set ([testing.md](testing.md)).
- **Org transfer (2026-10-20, `733f54d`)**, Dart-only scripts (`3883d61`), LF (`18a2559`), 0.2.0 release
  (`5f1c294`).
