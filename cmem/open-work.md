# Open work — the ONE list (status lives here and nowhere else)

**State (2026-10-26):** 0.2.1 is the latest on pub.dev (SPEC 3.0.0 + §10), and `main` = `v0.2.1`
(`ae231db`, post-purge id) plus memory / fixture-stamp commits only. Every release from here on
passes the blocking compatibility gate in CI. The history was purged of a drive path and
force-pushed on 2026-10-26 (H19, [history-map-2026-10-26.md](history-map-2026-10-26.md)).

## Open

- **🗓️ OWNER: send the GitHub Support cleanup request (H19's last step).** GitHub still serves the
  19 pre-purge commits by hash until its own GC. Measured 2026-10-26: public repo, 0 forks, 0 pull
  requests, so no other ref holds them. Send from the account that administers the org, at
  support.github.com → "Remove data from a repository" (sensitive data removal). The letter, ready
  to paste:

  > **Subject:** Sensitive data removal — synapticforge1/universalWasmLoader-dart
  >
  > Hello. I administer the organization `synapticforge1`. The public repository
  > `synapticforge1/universalWasmLoader-dart` had a local filesystem path of my development machine
  > committed in `CLAUDE.md`. I have rewritten the repository's history to remove it and
  > force-pushed every branch and tag on 2026-10-26 (`main` is now `0bcd2e9`; tags `v0.1.0`,
  > `v0.2.0`, `v0.2.1` moved). The repository has no forks and no pull requests.
  >
  > The old commits are still reachable by hash. Please remove the cached views of these
  > dereferenced commits and run garbage collection on the repository:
  >
  > `c7884df40f035dd7436f346b1fd4d9d91f3c0c9f`, `e75c046114925726b201d7e3f09a0c20e58602da`,
  > `6aa6fb00428705d4460ea9b47eaa36d8ad7ba2f3`, `b62fdeb17040d480d9ae55d6c69b6e501018c00e`,
  > `edd1e46fe97bb409357a8b72e9532bb06c4da23c`, `2429345dce607c932688076e5f791e5eb6b8dc8e`,
  > `985039ff17aa09de74436c9df3c37feee9e029d0`, `4a9b9b746f1a6669eb693b5345d48f5574853d61`,
  > `df673dcebf348d2cea0d82fb6477997e6f4faf89`, `99edd4090a88ac01463faa5f987dbf98ea7be1d8`,
  > `a75b167429ef3995ec8bed59a43d2dc988e1fd33`, `e5529e490ba5324ab11208233d441e682f27cb50`,
  > `f550a3772929c63803f172367ba3f4be1af3233c`, `b9f4e9ceb3c8926f12281d1afec538f4a7165de4`,
  > `11dacb970fd6d1093e37d450d0485aa0700519b6`, `bc53669f37fdb48ebd448c59a041e15fbc533e25`,
  > `36378fdecf66445ce54d39c2ec756c50b3c29373`, `1fc075753797023db6efe5200ccd0f7c7357980b`,
  > `256c699cd1a2036f6c9cbdcef6906499e4d332f6`
  >
  > The sensitive content is the file `CLAUDE.md` in each of them. Thank you.

  Close this item when Support confirms; then `https://github.com/synapticforge1/universalWasmLoader-dart/commit/256c699`
  should return 404 (that is the check).
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
